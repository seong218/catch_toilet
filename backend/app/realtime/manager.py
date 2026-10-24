import asyncio
import logging
from dataclasses import dataclass

from fastapi import WebSocket

from app.schemas.realtime import StallUpdated

logger = logging.getLogger(__name__)


@dataclass
class _Connection:
    queue: asyncio.Queue[str]
    sender: asyncio.Task[None]


class ConnectionManager:
    """One event loop/process; each socket has an independent bounded sender."""

    def __init__(self, *, queue_size: int = 64, send_timeout: float = 2.0):
        self._queue_size = queue_size
        self._send_timeout = send_timeout
        self._connections: dict[WebSocket, _Connection] = {}
        self._tasks: set[asyncio.Task[None]] = set()
        # Hold across transaction + enqueue to preserve commit/snapshot order.
        # Multiple workers/replicas require a shared ordered message broker.
        self.update_lock = asyncio.Lock()

    @property
    def connection_count(self) -> int:
        return len(self._connections)

    def _track(self, task: asyncio.Task[None]) -> asyncio.Task[None]:
        self._tasks.add(task)
        task.add_done_callback(self._tasks.discard)
        return task

    async def connect(self, websocket: WebSocket) -> None:
        await websocket.accept()
        queue: asyncio.Queue[str] = asyncio.Queue(maxsize=self._queue_size)
        sender = self._track(asyncio.create_task(self._send(websocket, queue)))
        self._connections[websocket] = _Connection(queue, sender)

    def broadcast(self, event: StallUpdated) -> None:
        # No network await: a slow client cannot delay HTTP or another sender.
        message = event.model_dump_json()
        for websocket, connection in tuple(self._connections.items()):
            try:
                connection.queue.put_nowait(message)
            except asyncio.QueueFull:
                logger.warning("Closing WebSocket whose outgoing queue is full")
                self._drop(websocket, code=1011)

    async def _send(self, websocket: WebSocket, queue: asyncio.Queue[str]) -> None:
        try:
            while True:
                message = await queue.get()
                await asyncio.wait_for(websocket.send_text(message), timeout=self._send_timeout)
        except asyncio.CancelledError:
            raise
        except Exception:
            logger.warning("Closing WebSocket after send failure or timeout")
            self._drop(websocket, code=1011)

    def _drop(self, websocket: WebSocket, *, code: int) -> asyncio.Task[None] | None:
        connection = self._connections.pop(websocket, None)
        if connection is None:
            return None
        if connection.sender is not asyncio.current_task():
            connection.sender.cancel()
        return self._track(asyncio.create_task(
            self._finish_disconnect(websocket, connection.sender, code)
        ))

    async def _finish_disconnect(
        self, websocket: WebSocket, sender: asyncio.Task[None], code: int,
    ) -> None:
        await asyncio.gather(sender, return_exceptions=True)
        try:
            await asyncio.wait_for(websocket.close(code=code), timeout=self._send_timeout)
        except Exception:
            # The peer/ASGI server may have already closed the socket.
            pass

    async def disconnect(self, websocket: WebSocket, *, code: int = 1000) -> None:
        cleanup = self._drop(websocket, code=code)
        if cleanup is not None:
            await asyncio.shield(cleanup)

    async def close(self) -> None:
        for websocket in tuple(self._connections):
            self._drop(websocket, code=1000)
        await asyncio.gather(*tuple(self._tasks), return_exceptions=True)
