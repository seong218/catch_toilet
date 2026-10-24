import asyncio
import json
import unittest

from app.realtime.manager import ConnectionManager
from app.schemas.realtime import StallUpdated


class FakeSocket:
    def __init__(self, *, fail=False, block=False):
        self.fail = fail
        self.block = block
        self.messages = asyncio.Queue()
        self.started = asyncio.Event()
        self.closed = asyncio.Event()
        self.close_code = None

    async def accept(self):
        pass

    async def send_text(self, message):
        self.started.set()
        if self.fail:
            raise RuntimeError("peer disconnected")
        if self.block:
            await asyncio.Event().wait()
        self.messages.put_nowait(json.loads(message))

    async def close(self, code):
        self.close_code = code
        self.closed.set()


class ConnectionManagerTests(unittest.IsolatedAsyncioTestCase):
    async def asyncSetUp(self):
        self.manager = ConnectionManager(send_timeout=0.1)
        self.addAsyncCleanup(self.manager.close)

    def notification(self, occupied=True):
        return StallUpdated(
            restroom_id=1, stall_id=1, occupied=occupied, total_stalls=1,
            available_stalls=int(not occupied), available_bidet_stalls=int(not occupied),
        )

    async def receive(self, socket):
        return await asyncio.wait_for(socket.messages.get(), timeout=1)

    async def test_multiple_clients_receive_fifo_and_shutdown_closes_all(self):
        sockets = [FakeSocket(), FakeSocket()]
        for socket in sockets:
            await self.manager.connect(socket)
        for state in (True, False, True):
            self.manager.broadcast(self.notification(state))
        for socket in sockets:
            received = [await self.receive(socket) for _ in range(3)]
            self.assertEqual([message["occupied"] for message in received], [True, False, True])
        await self.manager.close()
        self.assertEqual(self.manager.connection_count, 0)
        self.assertTrue(all(socket.close_code == 1000 for socket in sockets))

    async def test_send_failure_isolated_from_healthy_client(self):
        failed, healthy = FakeSocket(fail=True), FakeSocket()
        await self.manager.connect(failed)
        await self.manager.connect(healthy)
        self.manager.broadcast(self.notification())
        self.assertTrue((await self.receive(healthy))["occupied"])
        await asyncio.wait_for(failed.closed.wait(), timeout=1)
        self.assertEqual(failed.close_code, 1011)
        self.assertEqual(self.manager.connection_count, 1)
        self.manager.broadcast(self.notification(False))
        self.assertFalse((await self.receive(healthy))["occupied"])

    async def test_slow_send_does_not_delay_healthy_client_and_times_out(self):
        slow, healthy = FakeSocket(block=True), FakeSocket()
        await self.manager.connect(slow)
        await self.manager.connect(healthy)
        self.manager.broadcast(self.notification())
        await self.receive(healthy)
        self.assertFalse(slow.closed.is_set())
        await asyncio.wait_for(slow.closed.wait(), timeout=1)
        self.assertEqual(slow.close_code, 1011)
        self.assertEqual(self.manager.connection_count, 1)

    async def test_full_queue_drops_only_slow_client(self):
        manager = ConnectionManager(queue_size=1, send_timeout=5)
        self.addAsyncCleanup(manager.close)
        slow, healthy = FakeSocket(block=True), FakeSocket()
        await manager.connect(slow)
        await manager.connect(healthy)
        manager.broadcast(self.notification())
        await asyncio.wait_for(slow.started.wait(), timeout=1)
        await self.receive(healthy)
        manager.broadcast(self.notification(False))
        await self.receive(healthy)
        manager.broadcast(self.notification())
        self.assertTrue((await self.receive(healthy))["occupied"])
        await asyncio.wait_for(slow.closed.wait(), timeout=1)
        self.assertEqual(slow.close_code, 1011)
        self.assertEqual(manager.connection_count, 1)

    async def test_disconnect_is_idempotent_and_removes_recipient(self):
        socket = FakeSocket()
        await self.manager.connect(socket)
        await self.manager.disconnect(socket)
        await self.manager.disconnect(socket)
        self.manager.broadcast(self.notification())
        self.assertTrue(socket.messages.empty())
        self.assertEqual(socket.close_code, 1000)
        self.assertEqual(self.manager.connection_count, 0)


if __name__ == "__main__":
    unittest.main()
