"""用一个最小的假 Home Assistant WebSocket 服务验证适配器的协议实现。"""

import asyncio
import json

import pytest
from websockets.asyncio.server import serve

from gateway.adapters.base import AdapterError
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
    def __init__(self, token="secret"):
        self.token = token
        self.service_calls = []
        self.conn = None
        self.subscription_id = None

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
            if msg["type"] in REGISTRY:
                result = REGISTRY[msg["type"]]
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


@pytest.fixture
async def fake_ha():
    fake = FakeHA()
    async with serve(fake.handler, "127.0.0.1", 0) as server:
        port = server.sockets[0].getsockname()[1]
        yield fake, f"http://127.0.0.1:{port}"


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
