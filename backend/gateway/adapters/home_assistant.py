"""通过 Home Assistant WebSocket API 接入设备。

小米（官方 xiaomi_home 集成）、涂鸦（内置 tuya 集成）、华为（huawei_smarthome / Matter）、
乐橙（imou_life）、德施曼（desmanlock）等设备都先接入 HA，
网关只需要对接 HA 这一个上游，就能拿到所有平台的设备。
"""

from __future__ import annotations

import asyncio
import contextlib
import itertools
import json
import logging
import re
from typing import Any

import httpx
from websockets.asyncio.client import ClientConnection, connect
from websockets.exceptions import ConnectionClosed

from ..models import Action, Command, Device, DeviceEvent
from .base import AdapterError, DeviceAdapter, DeviceNotFound, EventCallback, MediaContent
from .ha_mapping import command_to_service, map_entity

log = logging.getLogger(__name__)

REQUEST_TIMEOUT = 10
MAX_BACKOFF = 60
# HA 返回的 HLS 地址形如 /api/hls/<一次性令牌>/master_playlist.m3u8，后续分片也在同一目录下
_HLS_PATH = re.compile(r"^[A-Za-z0-9_\-]+(/[A-Za-z0-9_\-.]+)*$")


class HomeAssistantAdapter(DeviceAdapter):
    name = "ha"

    def __init__(self, url: str, token: str) -> None:
        # http://host:8123 -> ws://host:8123/api/websocket
        self._http_url = url.rstrip("/")
        self._ws_url = self._http_url.replace("http", "ws", 1) + "/api/websocket"
        self._http: httpx.AsyncClient | None = None
        self._token = token
        self._on_event: EventCallback | None = None
        self._ws: ClientConnection | None = None
        self._ids = itertools.count(1)
        self._pending: dict[int, asyncio.Future[Any]] = {}
        self._task: asyncio.Task[None] | None = None
        self._ready = asyncio.Event()

        self._entities: dict[str, dict[str, Any]] = {}
        self._devices: dict[str, dict[str, Any]] = {}
        self._areas: dict[str, str] = {}
        self._states: dict[str, dict[str, Any]] = {}  # entity_id -> HA 原始状态
        self._by_device: dict[str, set[str]] = {}  # HA device_id -> entity_ids
        self._mapped: dict[str, Device] = {}  # entity_id -> Device

    async def start(self, on_event: EventCallback) -> None:
        self._on_event = on_event
        self._http = httpx.AsyncClient(
            base_url=self._http_url,
            headers={"Authorization": f"Bearer {self._token}"},
            timeout=REQUEST_TIMEOUT,
        )
        self._task = asyncio.create_task(self._run())
        # 首次连接失败不阻塞网关启动，后台会持续重连
        with contextlib.suppress(TimeoutError):
            await asyncio.wait_for(self._ready.wait(), REQUEST_TIMEOUT)

    async def stop(self) -> None:
        if self._task:
            self._task.cancel()
            with contextlib.suppress(asyncio.CancelledError):
                await self._task
        if self._http:
            await self._http.aclose()

    async def list_devices(self) -> list[Device]:
        return list(self._mapped.values())

    async def execute(self, native_id: str, command: Command) -> None:
        if native_id not in self._mapped:
            raise DeviceNotFound(native_id)
        if command.action == Action.PTZ:
            # 云台由同一设备下的按钮实体控制，按一次转动一步
            target = self._sibling_with_key(native_id, f"ptz_{command.params['direction']}")
            if target is None:
                raise AdapterError("该摄像头不支持这个方向")
            domain, service, data = "button", "press", {}
        else:
            target = native_id
            domain, service, data = command_to_service(native_id, command)
        await self._request(
            {
                "type": "call_service",
                "domain": domain,
                "service": service,
                "service_data": data,
                "target": {"entity_id": target},
            }
        )

    def _sibling_with_key(self, entity_id: str, translation_key: str) -> str | None:
        for other in self._same_device(entity_id) - {entity_id}:
            if (self._entities.get(other) or {}).get("translation_key") == translation_key:
                return other
        return None

    async def snapshot(self, native_id: str) -> MediaContent:
        self._require_camera(native_id)
        return await self._get(f"/api/camera_proxy/{native_id}")

    async def stream_url(self, native_id: str) -> str:
        device = self._require_camera(native_id)
        if not device.state.get("stream_supported"):
            raise AdapterError(f"{device.name} 不支持实时视频")
        result = await self._request({"type": "camera/stream", "entity_id": native_id, "format": "hls"})
        return result["url"]

    async def fetch_hls(self, path: str) -> MediaContent | None:
        # 请求会带上 HA 令牌，必须防止路径穿越到 /api/hls/ 之外
        if not _HLS_PATH.match(path) or ".." in path:
            return None
        return await self._get(f"/api/hls/{path}")

    def _require_camera(self, native_id: str) -> Device:
        device = self._mapped.get(native_id)
        if device is None or not native_id.startswith("camera."):
            raise DeviceNotFound(native_id)
        return device

    async def _get(self, path: str) -> MediaContent:
        if self._http is None:
            raise AdapterError("Home Assistant 未连接")
        try:
            resp = await self._http.get(path)
        except httpx.HTTPError as exc:
            raise AdapterError(f"请求 Home Assistant 失败: {exc}") from exc
        if resp.status_code != 200:
            raise AdapterError(f"Home Assistant 返回 {resp.status_code}")
        return MediaContent(resp.content, resp.headers.get("content-type", "application/octet-stream"))

    # ---- 连接管理 ----

    async def _run(self) -> None:
        backoff = 1
        while True:
            try:
                async with connect(self._ws_url, max_size=None) as ws:
                    self._ws = ws
                    await self._authenticate(ws)
                    reader = asyncio.create_task(self._read_loop(ws))
                    try:
                        await self._sync()
                        self._ready.set()
                        backoff = 1
                        log.info("已连接 Home Assistant，%d 个设备", len(self._mapped))
                        await reader
                    finally:
                        reader.cancel()
            except asyncio.CancelledError:
                raise
            except Exception as exc:  # noqa: BLE001 - 任何错误都走重连
                log.warning("Home Assistant 连接断开: %s，%ds 后重连", exc, backoff)
            finally:
                self._ws = None
                for fut in self._pending.values():
                    if not fut.done():
                        fut.set_exception(AdapterError("Home Assistant 连接已断开"))
                self._pending.clear()
            await asyncio.sleep(backoff)
            backoff = min(backoff * 2, MAX_BACKOFF)

    async def _authenticate(self, ws: ClientConnection) -> None:
        msg = json.loads(await ws.recv())
        if msg.get("type") != "auth_required":
            raise AdapterError(f"unexpected handshake: {msg}")
        await ws.send(json.dumps({"type": "auth", "access_token": self._token}))
        msg = json.loads(await ws.recv())
        if msg.get("type") != "auth_ok":
            raise AdapterError("Home Assistant 鉴权失败，请检查 HA_TOKEN")

    async def _sync(self) -> None:
        """拉取注册表和全部状态，然后订阅状态变化。"""
        entities, devices, areas, states = await asyncio.gather(
            self._request({"type": "config/entity_registry/list"}),
            self._request({"type": "config/device_registry/list"}),
            self._request({"type": "config/area_registry/list"}),
            self._request({"type": "get_states"}),
        )
        self._entities = {e["entity_id"]: e for e in entities}
        self._devices = {d["id"]: d for d in devices}
        self._areas = {a["area_id"]: a["name"] for a in areas}
        self._by_device = {}
        for e in entities:
            if e.get("device_id"):
                self._by_device.setdefault(e["device_id"], set()).add(e["entity_id"])
        self._states = {st["entity_id"]: st for st in states}

        previous = self._mapped
        self._mapped = {}
        for entity_id in self._states:
            await self._remap(entity_id, notify=False)
        await self._request({"type": "subscribe_events", "event_type": "state_changed"})

        # 重连后状态可能已变化，统一推送一次
        if self._on_event:
            for device in self._mapped.values():
                await self._on_event(DeviceEvent(type="device_updated", device=device))
            for gone in previous.keys() - self._mapped.keys():
                await self._on_event(DeviceEvent(type="device_removed", device=previous[gone]))

    async def _read_loop(self, ws: ClientConnection) -> None:
        try:
            async for raw in ws:
                msg = json.loads(raw)
                if msg.get("type") == "result":
                    fut = self._pending.pop(msg["id"], None)
                    if fut and not fut.done():
                        if msg.get("success"):
                            fut.set_result(msg.get("result"))
                        else:
                            err = msg.get("error", {})
                            fut.set_exception(AdapterError(err.get("message", "unknown error")))
                elif msg.get("type") == "event":
                    data = msg["event"].get("data", {})
                    if "entity_id" in data:
                        await self._apply_state(data["entity_id"], data.get("new_state"))
        except ConnectionClosed:
            pass

    async def _request(self, payload: dict[str, Any]) -> Any:
        ws = self._ws
        if ws is None:
            raise AdapterError("Home Assistant 未连接")
        msg_id = next(self._ids)
        fut: asyncio.Future[Any] = asyncio.get_running_loop().create_future()
        self._pending[msg_id] = fut
        await ws.send(json.dumps({"id": msg_id, **payload}))
        try:
            return await asyncio.wait_for(fut, REQUEST_TIMEOUT)
        finally:
            self._pending.pop(msg_id, None)

    # ---- 状态转换 ----

    async def _apply_state(self, entity_id: str, state: dict[str, Any] | None, notify: bool = True) -> None:
        if state is None:  # 实体被删除
            self._states.pop(entity_id, None)
            removed = self._mapped.pop(entity_id, None)
            if removed and notify and self._on_event:
                await self._on_event(DeviceEvent(type="device_removed", device=removed))
        else:
            self._states[entity_id] = state
        # 同一 HA 设备下的其他实体可能合并了这个实体的数据（如净化器的 PM2.5），一起刷新
        for affected in self._same_device(entity_id):
            await self._remap(affected, notify)

    def _same_device(self, entity_id: str) -> set[str]:
        entity = self._entities.get(entity_id) or {}
        return {entity_id} | self._by_device.get(entity.get("device_id") or "", set())

    async def _remap(self, entity_id: str, notify: bool = True) -> None:
        state = self._states.get(entity_id)
        if state is None:
            return
        entity = self._entities.get(entity_id)
        device_entry = self._devices.get(entity.get("device_id")) if entity else None
        siblings = [
            {**self._states[e], "translation_key": (self._entities.get(e) or {}).get("translation_key")}
            for e in self._same_device(entity_id) - {entity_id}
            if e in self._states
        ]
        device = map_entity(state, entity, device_entry, self._areas, self.name, siblings)

        old = self._mapped.get(entity_id)
        if device is None:
            if old is not None:
                del self._mapped[entity_id]
                if notify and self._on_event:
                    await self._on_event(DeviceEvent(type="device_removed", device=old))
            return
        if device == old:
            return
        self._mapped[entity_id] = device
        if notify and self._on_event:
            await self._on_event(DeviceEvent(type="device_updated", device=device))
