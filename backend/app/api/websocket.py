from typing import Annotated

from fastapi import APIRouter, Depends, WebSocket, WebSocketDisconnect

from app.config import Settings, get_settings
from app.realtime.manager import ConnectionManager

router = APIRouter()


@router.websocket("/ws")
async def websocket_updates(websocket: WebSocket, settings: Annotated[Settings, Depends(get_settings)]) -> None:
    origins = websocket.headers.getlist("origin")
    allowed = settings.ws_allowed_origins or settings.cors_allowed_origins
    if origins and (len(origins) != 1 or origins[0] == "null" or origins[0] not in allowed):
        await websocket.close(code=1008)
        return
    manager: ConnectionManager = websocket.app.state.connection_manager
    if not await manager.connect(websocket):
        return
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
