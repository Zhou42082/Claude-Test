import pytest
from fastapi.testclient import TestClient
from pydantic import ValidationError

from gateway.adapters.mock import MockAdapter
from gateway.config import Settings
from gateway.main import create_app
from gateway.models import Action, Command

TOKEN = "test-token"
AUTH = {"Authorization": f"Bearer {TOKEN}"}


PIN = "2468"


def make_client(unlock_pin=""):
    app = create_app(
        Settings(token=TOKEN, adapters=("mock",), unlock_pin=unlock_pin), adapters=[MockAdapter()]
    )
    return TestClient(app)


@pytest.fixture
def client():
    with make_client() as c:
        yield c


@pytest.fixture
def pin_client():
    with make_client(unlock_pin=PIN) as c:
        yield c


def command(client, device_id, action, **params):
    return client.post(
        f"/api/devices/{device_id}/commands", json={"action": action, "params": params}, headers=AUTH
    )


def test_requires_token(client):
    assert client.get("/api/devices").status_code == 401
    assert client.get("/api/devices", headers={"Authorization": "Bearer wrong"}).status_code == 401
    assert client.get("/api/health").status_code == 200


def test_list_devices_covers_all_platforms(client):
    devices = client.get("/api/devices", headers=AUTH).json()
    assert {d["platform"] for d in devices if d["type"] != "scene"} == {
        "xiaomi",
        "huawei",
        "tuya",
        "imou",
        "desman",
    }
    assert client.get("/api/rooms", headers=AUTH).json() == sorted(["客厅", "卧室", "厨房", "门口"])


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


def test_unlock_disabled_without_configured_pin(client):
    assert command(client, "mock:entrance_lock", "unlock", pin="2468").status_code == 403
    # 上锁不需要 PIN
    assert command(client, "mock:entrance_lock", "lock").status_code == 202


def test_unlock_requires_correct_pin(pin_client):
    assert command(pin_client, "mock:entrance_lock", "unlock").status_code == 403
    assert command(pin_client, "mock:entrance_lock", "unlock", pin="0000").status_code == 403
    assert command(pin_client, "mock:entrance_lock", "unlock", pin=PIN).status_code == 202
    lock = pin_client.get("/api/devices/mock:entrance_lock", headers=AUTH).json()
    assert lock["state"]["lock_state"] == "unlocked"


def test_unlock_locks_out_after_repeated_failures(pin_client):
    for _ in range(5):
        assert command(pin_client, "mock:entrance_lock", "unlock", pin="0000").status_code == 403
    # 锁定期间正确的 PIN 也被拒绝
    assert command(pin_client, "mock:entrance_lock", "unlock", pin=PIN).status_code == 429


def test_purifier_preset_mode(client):
    assert command(client, "mock:bedroom_purifier", "set_preset_mode", preset_mode="sleep").status_code == 202
    purifier = client.get("/api/devices/mock:bedroom_purifier", headers=AUTH).json()
    assert purifier["state"]["preset_mode"] == "sleep"
    assert command(client, "mock:bedroom_purifier", "set_preset_mode").status_code == 422


def test_camera_snapshot_and_stream(client):
    resp = client.get("/api/devices/mock:entrance_cam/snapshot", headers=AUTH)
    assert resp.status_code == 200
    assert resp.headers["content-type"] == "image/png"
    assert resp.content.startswith(b"\x89PNG")

    assert client.get("/api/devices/mock:entrance_cam/snapshot").status_code == 401
    assert client.get("/api/devices/mock:living_light/snapshot", headers=AUTH).status_code == 422
    # 演示摄像头没有视频流
    assert client.post("/api/devices/mock:entrance_cam/stream", headers=AUTH).status_code == 502
    # 没有启用 HA 适配器时 HLS 代理无内容
    assert client.get("/api/hls/abc/master_playlist.m3u8").status_code == 404


def test_scene_runs_all_its_commands(client):
    assert command(client, "mock:scene_away", "activate").status_code == 202
    devices = {d["id"]: d for d in client.get("/api/devices", headers=AUTH).json()}
    assert devices["mock:living_light"]["state"]["on"] is False
    assert devices["mock:kitchen_plug"]["state"]["on"] is False
    assert devices["mock:living_curtain"]["state"]["position"] == 0
    assert devices["mock:living_ac"]["state"]["hvac_mode"] == "off"
    assert devices["mock:entrance_lock"]["state"]["lock_state"] == "locked"
    # 场景只能执行，不能开关
    assert command(client, "mock:scene_away", "turn_on").status_code == 422


def test_unlock_raises_alert_pushed_over_websocket(pin_client):
    with pin_client.websocket_connect(f"/api/ws?token={TOKEN}") as ws:
        assert ws.receive_json()["alerts"] == []
        assert command(pin_client, "mock:entrance_lock", "unlock", pin=PIN).status_code == 202
        assert ws.receive_json()["type"] == "device_updated"
        alert = ws.receive_json()
        assert alert["type"] == "alert"
        assert alert["alert"]["level"] == "info"
        assert alert["alert"]["message"] == "门锁已打开"
        assert alert["alert"]["device_name"] == "入户门锁"

    alerts = pin_client.get("/api/alerts", headers=AUTH).json()
    assert [a["message"] for a in alerts] == ["门锁已打开"]
    with pin_client.websocket_connect(f"/api/ws?token={TOKEN}") as ws:
        # 重连后的快照里带着最近告警
        assert ws.receive_json()["alerts"][0]["message"] == "门锁已打开"
