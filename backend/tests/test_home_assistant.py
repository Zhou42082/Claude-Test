"""用一个最小的假 Home Assistant WebSocket 服务验证适配器的协议实现。"""

import asyncio
import json
from http import HTTPStatus

import pytest
from websockets.asyncio.server import serve

from gateway.adapters.base import AdapterError, DeviceNotFound
from gateway.adapters.home_assistant import HomeAssistantAdapter
from gateway.models import Action, Command, Platform

STATES = [
    {"entity_id": "light.ceiling", "state": "off", "attributes": {"supported_color_modes": ["brightness"]}},
    {"entity_id": "automation.morning", "state": "on", "attributes": {}},
]
REGISTRY = {
    "config/entity_registry/list": [
        {"entity_id": "light.ceiling", "platform": "tuya", "device_id": "d1", "area_id": None}
    ],
    "config/device_registry/list": [{"id": "d1", "manufacturer": "Tuya", "area_id": "bedroom"}],
    "config/area_registry/list": [{"area_id": "bedroom", "name": "卧室"}],
    "get_states": STATES,
}


class FakeHA:
    def __init__(self, token="secret", registry=None):
        self.token = token
        self.registry = registry or REGISTRY
        self.service_calls = []
        self.http_requests = []
        self.conn = None
        self.subscription_id = None

    def process_request(self, connection, request):
        """模拟 HA 的 HTTP 接口：摄像头截图需要令牌，HLS 不需要。"""
        if request.path.startswith("/api/camera_proxy/"):
            self.http_requests.append((request.path, request.headers.get("Authorization")))
            if request.headers.get("Authorization") != f"Bearer {self.token}":
                return connection.respond(HTTPStatus.UNAUTHORIZED, "unauthorized")
            return connection.respond(HTTPStatus.OK, "JPEG-BYTES")
        if request.path.startswith("/api/hls/"):
            self.http_requests.append((request.path, None))
            return connection.respond(HTTPStatus.OK, "#EXTM3U")
        return None

    async def handler(self, ws):
        self.conn = ws
        await ws.send(json.dumps({"type": "auth_required"}))
        auth = json.loads(await ws.recv())
        if auth["access_token"] != self.token:
            await ws.send(json.dumps({"type": "auth_invalid"}))
            return
        await ws.send(json.dumps({"type": "auth_ok"}))
        async for raw in ws:
            msg = json.loads(raw)
            result, success = None, True
            if msg["type"] in self.registry:
                result = self.registry[msg["type"]]
            elif msg["type"] == "camera/stream":
                result = {"url": "/api/hls/tok123/master_playlist.m3u8"}
            elif msg["type"] == "subscribe_events":
                self.subscription_id = msg["id"]
            elif msg["type"] == "call_service":
                self.service_calls.append(msg)
                success = msg["target"]["entity_id"] != "light.broken"
            await ws.send(
                json.dumps(
                    {"id": msg["id"], "type": "result", "success": success, "result": result}
                    | ({} if success else {"error": {"message": "boom"}})
                )
            )

    async def push_state(self, entity_id, new_state):
        await self.conn.send(
            json.dumps(
                {
                    "id": self.subscription_id,
                    "type": "event",
                    "event": {"data": {"entity_id": entity_id, "new_state": new_state}},
                }
            )
        )


async def start_fake(registry=None):
    fake = FakeHA(registry=registry)
    server = await serve(fake.handler, "127.0.0.1", 0, process_request=fake.process_request)
    port = server.sockets[0].getsockname()[1]
    return fake, server, f"http://127.0.0.1:{port}"


@pytest.fixture
async def fake_ha():
    fake, server, url = await start_fake()
    yield fake, url
    server.close()
    await server.wait_closed()


async def wait_for(predicate):
    for _ in range(100):
        if predicate():
            return
        await asyncio.sleep(0.01)
    raise AssertionError("condition not met")


async def test_sync_execute_and_events(fake_ha):
    fake, url = fake_ha
    events = []

    async def on_event(event):
        events.append(event)

    adapter = HomeAssistantAdapter(url, "secret")
    await adapter.start(on_event)
    try:
        devices = await adapter.list_devices()
        assert [d.id for d in devices] == ["ha:light.ceiling"]
        assert devices[0].platform == Platform.TUYA
        assert devices[0].room == "卧室"

        await adapter.execute(
            "light.ceiling", Command(action=Action.SET_BRIGHTNESS, params={"brightness": 70})
        )
        call = fake.service_calls[-1]
        assert (call["domain"], call["service"], call["service_data"]) == (
            "light",
            "turn_on",
            {"brightness_pct": 70},
        )

        events.clear()
        await fake.push_state(
            "light.ceiling",
            {
                "entity_id": "light.ceiling",
                "state": "on",
                "attributes": {"supported_color_modes": ["brightness"], "brightness": 255},
            },
        )
        for _ in range(50):
            if events:
                break
            await asyncio.sleep(0.01)
        assert events[0].type == "device_updated"
        assert events[0].device.state == {"on": True, "brightness": 100}

        await fake.push_state("light.ceiling", None)
        for _ in range(50):
            if len(events) > 1:
                break
            await asyncio.sleep(0.01)
        assert events[1].type == "device_removed"
        assert await adapter.list_devices() == []
    finally:
        await adapter.stop()


async def test_service_error_raises_adapter_error(fake_ha):
    _, url = fake_ha
    REGISTRY["get_states"] = STATES + [{"entity_id": "light.broken", "state": "on", "attributes": {}}]
    try:
        adapter = HomeAssistantAdapter(url, "secret")

        async def noop(_):
            pass

        await adapter.start(noop)
        with pytest.raises(AdapterError, match="boom"):
            await adapter.execute("light.broken", Command(action=Action.TOGGLE))
        await adapter.stop()
    finally:
        REGISTRY["get_states"] = STATES


HOME_REGISTRY = {
    "config/entity_registry/list": [
        {"entity_id": "fan.purifier", "platform": "tuya", "device_id": "p1"},
        {"entity_id": "sensor.purifier_pm25", "platform": "tuya", "device_id": "p1"},
        {"entity_id": "camera.door", "platform": "imou_life", "device_id": "c1"},
    ],
    "config/device_registry/list": [{"id": "p1", "model": "空气净化器"}, {"id": "c1"}],
    "config/area_registry/list": [],
    "get_states": [
        {"entity_id": "fan.purifier", "state": "on", "attributes": {}},
        {"entity_id": "sensor.purifier_pm25", "state": "30", "attributes": {"device_class": "pm25"}},
        {"entity_id": "camera.door", "state": "idle", "attributes": {"supported_features": 2}},
    ],
}


async def test_sibling_sensor_updates_purifier_and_camera_media():
    fake, server, url = await start_fake(HOME_REGISTRY)
    events = []

    async def on_event(event):
        events.append(event)

    adapter = HomeAssistantAdapter(url, "secret")
    await adapter.start(on_event)
    try:
        devices = {d.id: d for d in await adapter.list_devices()}
        # PM2.5 传感器合并进净化器，不单独出现
        assert set(devices) == {"ha:fan.purifier", "ha:camera.door"}
        assert devices["ha:fan.purifier"].state["pm25"] == 30

        events.clear()
        await fake.push_state(
            "sensor.purifier_pm25",
            {"entity_id": "sensor.purifier_pm25", "state": "75", "attributes": {"device_class": "pm25"}},
        )
        await wait_for(lambda: events)
        assert [e.device.id for e in events] == ["ha:fan.purifier"]
        assert events[0].device.state["pm25"] == 75

        snap = await adapter.snapshot("camera.door")
        assert snap.content == b"JPEG-BYTES"
        assert fake.http_requests[-1] == ("/api/camera_proxy/camera.door", "Bearer secret")

        assert await adapter.stream_url("camera.door") == "/api/hls/tok123/master_playlist.m3u8"
        playlist = await adapter.fetch_hls("tok123/master_playlist.m3u8")
        assert playlist.content == b"#EXTM3U"
        # 路径穿越和非摄像头实体都被拒绝
        assert await adapter.fetch_hls("tok123/../../config") is None
        with pytest.raises(DeviceNotFound):
            await adapter.snapshot("fan.purifier")
    finally:
        await adapter.stop()
        server.close()
        await server.wait_closed()
