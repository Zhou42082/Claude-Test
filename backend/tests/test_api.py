import pytest
from fastapi.testclient import TestClient
from pydantic import ValidationError

from gateway.adapters.mock import MockAdapter
from gateway.config import Settings
from gateway.main import create_app
from gateway.models import Action, Command

TOKEN = "test-token"
AUTH = {"Authorization": f"Bearer {TOKEN}"}


@pytest.fixture
def client():
    app = create_app(Settings(token=TOKEN, adapters=("mock",)), adapters=[MockAdapter()])
    with TestClient(app) as c:
        yield c


def test_requires_token(client):
    assert client.get("/api/devices").status_code == 401
    assert client.get("/api/devices", headers={"Authorization": "Bearer wrong"}).status_code == 401
    assert client.get("/api/health").status_code == 200


def test_list_devices_covers_all_platforms(client):
    devices = client.get("/api/devices", headers=AUTH).json()
    assert {d["platform"] for d in devices} == {"xiaomi", "huawei", "tuya"}
    assert client.get("/api/rooms", headers=AUTH).json() == sorted(["客厅", "卧室", "厨房"])


def test_command_updates_state_and_pushes_event(client):
    with client.websocket_connect(f"/api/ws?token={TOKEN}") as ws:
        snapshot = ws.receive_json()
        assert snapshot["type"] == "snapshot"
        lamp = next(d for d in snapshot["devices"] if d["id"] == "mock:bedroom_lamp")
        assert lamp["state"]["on"] is False

        resp = client.post(
            "/api/devices/mock:bedroom_lamp/commands",
            json={"action": "set_brightness", "params": {"brightness": 60}},
            headers=AUTH,
        )
        assert resp.status_code == 202

        event = ws.receive_json()
        assert event["type"] == "device_updated"
        assert event["device"]["state"] == {"on": True, "brightness": 60}

    assert client.get("/api/devices/mock:bedroom_lamp", headers=AUTH).json()["state"]["brightness"] == 60


def test_ws_rejects_bad_token(client):
    from starlette.websockets import WebSocketDisconnect

    with pytest.raises(WebSocketDisconnect), client.websocket_connect("/api/ws?token=wrong") as ws:
        ws.receive_json()


def test_unsupported_action_rejected(client):
    resp = client.post("/api/devices/mock:kitchen_plug/commands", json={"action": "open"}, headers=AUTH)
    assert resp.status_code == 422


def test_offline_device_returns_502(client):
    hub = client.app.state.hub
    hub.get_device("mock:kitchen_plug").online = False
    hub._adapters["mock"]._devices["mock:kitchen_plug"].online = False
    resp = client.post("/api/devices/mock:kitchen_plug/commands", json={"action": "toggle"}, headers=AUTH)
    assert resp.status_code == 502


def test_invalid_params_rejected(client):
    resp = client.post(
        "/api/devices/mock:living_light/commands",
        json={"action": "set_brightness", "params": {"brightness": 300}},
        headers=AUTH,
    )
    assert resp.status_code == 422
    assert (
        client.post("/api/devices/nope/commands", json={"action": "toggle"}, headers=AUTH).status_code == 404
    )


@pytest.mark.parametrize("params", [{}, {"brightness": "50"}, {"brightness": True}])
def test_command_param_validation(params):
    with pytest.raises(ValidationError):
        Command(action=Action.SET_BRIGHTNESS, params=params)
