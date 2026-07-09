from fastapi import WebSocket
from typing import List, Dict, Any


class RealtimeManager:
    def __init__(self):
        self.active_connections: List[WebSocket] = []

    async def connect(self, websocket: WebSocket):
        await websocket.accept()
        self.active_connections.append(websocket)
        print(f"WebSocket connected. total={len(self.active_connections)}")

    def disconnect(self, websocket: WebSocket):
        if websocket in self.active_connections:
            self.active_connections.remove(websocket)
        print(f"WebSocket disconnected. total={len(self.active_connections)}")

    async def broadcast(self, data: Dict[str, Any]):
        disconnected = []

        for connection in self.active_connections:
            try:
                await connection.send_json(data)
            except Exception:
                disconnected.append(connection)

        for connection in disconnected:
            self.disconnect(connection)


realtime_manager = RealtimeManager()