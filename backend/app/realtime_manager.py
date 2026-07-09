from fastapi import WebSocket
from typing import List, Dict, Any


class RealtimeManager:
    def __init__(self):
        self.active_connections: List[WebSocket] = []

    @property
    def connection_count(self) -> int:
        return len(self.active_connections)

    async def connect(self, websocket: WebSocket):
        await websocket.accept()
        self.active_connections.append(websocket)
        print(f"[WS] connected. total={len(self.active_connections)}")

    def disconnect(self, websocket: WebSocket):
        if websocket in self.active_connections:
            self.active_connections.remove(websocket)
        print(f"[WS] disconnected. total={len(self.active_connections)}")

    async def broadcast(self, data: Dict[str, Any]) -> int:
        print(f"[WS] broadcast target count={len(self.active_connections)}")
        print(f"[WS] data={data}")

        disconnected = []
        sent_count = 0

        for connection in self.active_connections:
            try:
                await connection.send_json(data)
                sent_count += 1
            except Exception as e:
                print(f"[WS] send failed: {e}")
                disconnected.append(connection)

        for connection in disconnected:
            self.disconnect(connection)

        print(f"[WS] sent_count={sent_count}")
        return sent_count


realtime_manager = RealtimeManager()