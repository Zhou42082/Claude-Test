"""网关 HTTP / WebSocket 接口，供移动端调用。

GET  /api/health                     健康检查（无需鉴权）
GET  /api/devices                    设备列表
GET  /api/devices/{id}               单个设备
POST /api/devices/{id}/commands      下发命令 {"action": "...", "params": {...}}
GET  /api/rooms                      房间列表
WS   /api/ws?token=...               推送：先发 snapshot，之后发 device_updated / device_removed
"""

from __future__ import annotations

import logging
import secrets
from collections.abc import AsyncIterator
from contextlib import asynccontextmanager
from typing import Annotated

from fastapi import Depends, FastAPI, Header, HTTPException, WebSocket, WebSocketDisconnect, status

from .adapters.base import AdapterError, DeviceAdapter, DeviceNotFound
from .adapters.home_assistant import HomeAssistantAdapter
from .adapters.mock import MockAdapter
from .config import Settings
from .hub import CapabilityError, DeviceHub
from .models import Command, Device

log = logging.getLogger(__name__)


def build_adapters(settings: Settings) -> list[DeviceAdapter]:
    adapters: list[DeviceAdapter] = []
    for name in settings.adapters:
        if name == "mock":
            adapters.append(MockAdapter())
        elif name == "ha":
            if not settings.ha_token:
                raise RuntimeError("启用 ha 适配器需要设置 HA_TOKEN")
            adapters.append(HomeAssistantAdapter(settings.ha_url, settings.ha_token))
        else:
            raise RuntimeError(f"未知适配器: {name}")
    return adapters


def create_app(settings: Settings | None = None, adapters: list[DeviceAdapter] | None = None) -> FastAPI:
    settings = settings or Settings()
    if not settings.token:
        raise RuntimeError("必须设置 GATEWAY_TOKEN")
    hub = DeviceHub(adapters if adapters is not None else build_adapters(settings))

    @asynccontextmanager
    async def lifespan(_: FastAPI) -> AsyncIterator[None]:
        await hub.start()
        yield
        await hub.stop()

    app = FastAPI(title="Smart Home Gateway", version="0.1.0", lifespan=lifespan)
    app.state.hub = hub

    def token_ok(token: str | None) -> bool:
        return token is not None and secrets.compare_digest(token, settings.token)

    def require_auth(authorization: Annotated[str | None, Header()] = None) -> None:
        token = authorization.removeprefix("Bearer ") if authorization else None
        if not token_ok(token):
            raise HTTPException(status.HTTP_401_UNAUTHORIZED, "invalid token")

    auth = [Depends(require_auth)]

    @app.get("/api/health")
    async def health() -> dict[str, str]:
        return {"status": "ok"}

    @app.get("/api/devices", dependencies=auth)
    async def list_devices() -> list[Device]:
        return hub.list_devices()

    @app.get("/api/devices/{device_id}", dependencies=auth)
    async def get_device(device_id: str) -> Device:
        try:
            return hub.get_device(device_id)
        except DeviceNotFound:
            raise HTTPException(status.HTTP_404_NOT_FOUND, "device not found") from None

    @app.post("/api/devices/{device_id}/commands", dependencies=auth, status_code=202)
    async def send_command(device_id: str, command: Command) -> dict[str, str]:
        try:
            await hub.execute(device_id, command)
        except DeviceNotFound:
            raise HTTPException(status.HTTP_404_NOT_FOUND, "device not found") from None
        except CapabilityError as exc:
            raise HTTPException(422, str(exc)) from None
        except AdapterError as exc:
            raise HTTPException(status.HTTP_502_BAD_GATEWAY, str(exc)) from None
        # 202：命令已下发，最终状态以 WebSocket 推送为准
        return {"status": "accepted"}

    @app.get("/api/rooms", dependencies=auth)
    async def rooms() -> list[str]:
        return hub.rooms()

    @app.websocket("/api/ws")
    async def events(ws: WebSocket, token: str | None = None) -> None:
        if not token_ok(token):
            await ws.close(code=status.WS_1008_POLICY_VIOLATION)
            return
        await ws.accept()
        queue = hub.subscribe()
        try:
            await ws.send_json(
                {"type": "snapshot", "devices": [d.model_dump(mode="json") for d in hub.list_devices()]}
            )
            while (event := await queue.get()) is not None:
                await ws.send_json(event.model_dump(mode="json"))
            await ws.close(code=status.WS_1013_TRY_AGAIN_LATER)
        except WebSocketDisconnect:
            pass
        finally:
            hub.unsubscribe(queue)

    return app


def app() -> FastAPI:
    """uvicorn 入口：uvicorn gateway.main:app --factory"""
    logging.basicConfig(level=logging.INFO)
    return create_app()
