from fastapi import APIRouter, WebSocket, WebSocketDisconnect

from app.realtime.manager import ConnectionManager

router = APIRouter()


@router.websocket("/ws")
async def websocket_updates(websocket: WebSocket) -> None:
    manager: ConnectionManager = websocket.app.state.connection_manager
    await manager.connect(websocket)
    try:
        while True:
            message = await websocket.receive()
            if message["type"] == "websocket.disconnect":
                break
            # There are no application commands/subscriptions in the MVP.
    except WebSocketDisconnect:
        pass
    finally:
        await manager.disconnect(websocket)
