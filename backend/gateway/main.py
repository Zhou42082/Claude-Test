"""网关 HTTP / WebSocket 接口，供移动端调用。

GET  /api/health                     健康检查（无需鉴权）
GET  /api/devices                    设备列表
GET  /api/devices/{id}               单个设备
POST /api/devices/{id}/commands      下发命令 {"action": "...", "params": {...}}
GET  /api/devices/{id}/snapshot      摄像头当前画面
POST /api/devices/{id}/stream        摄像头实时视频，返回 {"url": "/api/hls/..."}
GET  /api/hls/...                    HLS 代理（无需鉴权，地址中带一次性令牌）
GET  /api/rooms                      房间列表
GET  /api/alerts?limit=50            最近的告警（最新在前）
WS   /api/ws?token=...               推送：先发 snapshot（设备 + 最近告警），之后发 device_updated / device_removed / alert
"""

from __future__ import annotations

import logging
import secrets
import time
from collections.abc import AsyncIterator, Iterator
from contextlib import asynccontextmanager, contextmanager
from typing import Annotated, Any

from fastapi import Depends, FastAPI, Header, HTTPException, Response, WebSocket, WebSocketDisconnect, status

from .adapters.base import AdapterError, DeviceAdapter, DeviceNotFound
from .adapters.home_assistant import HomeAssistantAdapter
from .adapters.mock import MockAdapter
from .config import Settings
from .hub import CapabilityError, DeviceHub
from .models import SENSITIVE_ACTIONS, Alert, Command, Device

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


class UnlockGuard:
    """远程开锁的 PIN 校验。连续输错后锁定一段时间，防止暴力猜测。"""

    MAX_FAILURES = 5
    LOCKOUT_SECONDS = 300

    def __init__(self, pin: str) -> None:
        self._pin = pin
        self._failures = 0
        self._locked_until = 0.0

    def check(self, pin: Any) -> None:
        if not self._pin:
            raise HTTPException(status.HTTP_403_FORBIDDEN, "网关未设置 GATEWAY_UNLOCK_PIN，远程开锁已禁用")
        now = time.monotonic()
        if now < self._locked_until:
            wait = int(self._locked_until - now) + 1
            raise HTTPException(status.HTTP_429_TOO_MANY_REQUESTS, f"PIN 错误次数过多，请 {wait} 秒后再试")
        if not isinstance(pin, str) or not secrets.compare_digest(pin.encode(), self._pin.encode()):
            self._failures += 1
            if self._failures >= self.MAX_FAILURES:
                self._failures = 0
                self._locked_until = now + self.LOCKOUT_SECONDS
            raise HTTPException(status.HTTP_403_FORBIDDEN, "开锁 PIN 错误")
        self._failures = 0


@contextmanager
def _http_errors() -> Iterator[None]:
    try:
        yield
    except DeviceNotFound:
        raise HTTPException(status.HTTP_404_NOT_FOUND, "device not found") from None
    except CapabilityError as exc:
        raise HTTPException(422, str(exc)) from None
    except AdapterError as exc:
        raise HTTPException(status.HTTP_502_BAD_GATEWAY, str(exc)) from None


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
    unlock_guard = UnlockGuard(settings.unlock_pin)

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
        with _http_errors():
            return hub.get_device(device_id)

    @app.post("/api/devices/{device_id}/commands", dependencies=auth, status_code=202)
    async def send_command(device_id: str, command: Command) -> dict[str, str]:
        if command.action in SENSITIVE_ACTIONS:
            unlock_guard.check(command.params.get("pin"))
            # PIN 只在网关校验，不下发到设备平台
            command = command.model_copy(
                update={"params": {k: v for k, v in command.params.items() if k != "pin"}}
            )
        with _http_errors():
            await hub.execute(device_id, command)
        # 202：命令已下发，最终状态以 WebSocket 推送为准
        return {"status": "accepted"}

    @app.get("/api/devices/{device_id}/snapshot", dependencies=auth)
    async def snapshot(device_id: str) -> Response:
        with _http_errors():
            media = await hub.snapshot(device_id)
        return Response(media.content, media_type=media.content_type, headers={"Cache-Control": "no-store"})

    @app.post("/api/devices/{device_id}/stream", dependencies=auth)
    async def stream(device_id: str) -> dict[str, str]:
        with _http_errors():
            return {"url": await hub.stream_url(device_id)}

    @app.get("/api/hls/{path:path}")
    async def hls(path: str) -> Response:
        # 不校验网关令牌：播放器请求分片时带不上 Authorization，地址中的一次性令牌由 HA 校验
        with _http_errors():
            media = await hub.fetch_hls(path)
        if media is None:
            raise HTTPException(status.HTTP_404_NOT_FOUND, "not found")
        return Response(media.content, media_type=media.content_type, headers={"Cache-Control": "no-store"})

    @app.get("/api/rooms", dependencies=auth)
    async def rooms() -> list[str]:
        return hub.rooms()

    @app.get("/api/alerts", dependencies=auth)
    async def alerts(limit: int = 50) -> list[Alert]:
        return hub.alerts(max(1, min(limit, 200)))

    @app.websocket("/api/ws")
    async def events(ws: WebSocket, token: str | None = None) -> None:
        if not token_ok(token):
            await ws.close(code=status.WS_1008_POLICY_VIOLATION)
            return
        await ws.accept()
        queue = hub.subscribe()
        try:
            await ws.send_json(
                {
                    "type": "snapshot",
                    "devices": [d.model_dump(mode="json") for d in hub.list_devices()],
                    "alerts": [a.model_dump(mode="json") for a in hub.alerts()],
                }
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
