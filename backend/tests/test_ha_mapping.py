import pytest

from gateway.adapters.ha_mapping import command_to_service, map_entity, resolve_platform
from gateway.models import Action, Command, DeviceType, Platform

AREAS = {"living_room": "客厅"}


def light_state(**attrs):
    return {
        "entity_id": "light.ceiling",
        "state": "on",
        "attributes": {
            "friendly_name": "吸顶灯",
            "supported_color_modes": ["color_temp"],
            "brightness": 128,
            "color_temp_kelvin": 4000,
            **attrs,
        },
    }


def test_light_from_xiaomi_integration():
    entity = {"entity_id": "light.ceiling", "platform": "xiaomi_home", "device_id": "d1"}
    device = {"id": "d1", "manufacturer": "Xiaomi", "area_id": "living_room"}
    result = map_entity(light_state(), entity, device, AREAS)

    assert result is not None
    assert result.id == "ha:light.ceiling"
    assert result.platform == Platform.XIAOMI
    assert result.type == DeviceType.LIGHT
    assert result.room == "客厅"
    assert result.state["on"] is True
    assert result.state["brightness"] == 50
    assert Action.SET_COLOR_TEMP in result.capabilities


def test_onoff_light_has_no_brightness():
    result = map_entity(light_state(supported_color_modes=["onoff"], brightness=None), None, None, {})
    assert Action.SET_BRIGHTNESS not in result.capabilities
    assert "brightness" not in result.state


@pytest.mark.parametrize(
    ("integration", "manufacturer", "expected"),
    [
        ("tuya", None, Platform.TUYA),
        ("xiaomi_miot", None, Platform.XIAOMI),
        ("matter", "HUAWEI", Platform.HUAWEI),
        ("huawei_smarthome", "欧普照明", Platform.HUAWEI),
        ("matter", "Signify", Platform.OTHER),
        (None, None, Platform.OTHER),
    ],
)
def test_resolve_platform(integration, manufacturer, expected):
    assert resolve_platform(integration, manufacturer) == expected


def test_unavailable_entity_is_offline():
    state = {"entity_id": "switch.plug", "state": "unavailable", "attributes": {}}
    assert map_entity(state, None, None, {}).online is False


@pytest.mark.parametrize(
    "entity",
    [{"disabled_by": "user"}, {"hidden_by": "user"}, {"entity_category": "diagnostic"}],
)
def test_hidden_entities_are_skipped(entity):
    state = {"entity_id": "switch.plug", "state": "on", "attributes": {}}
    assert map_entity(state, entity, None, {}) is None


def test_unsupported_domain_and_diagnostic_sensor_skipped():
    assert map_entity({"entity_id": "automation.x", "state": "on", "attributes": {}}, None, None, {}) is None
    rssi = {"entity_id": "sensor.rssi", "state": "-60", "attributes": {"device_class": "signal_strength"}}
    assert map_entity(rssi, None, None, {}) is None


def test_temperature_sensor_value_is_numeric():
    state = {
        "entity_id": "sensor.temp",
        "state": "24.5",
        "attributes": {"device_class": "temperature", "unit_of_measurement": "°C"},
    }
    result = map_entity(state, None, None, {})
    assert result.state == {"value": 24.5, "unit": "°C", "device_class": "temperature"}
    assert result.capabilities == []


def test_climate_capabilities_follow_supported_features():
    state = {
        "entity_id": "climate.ac",
        "state": "cool",
        "attributes": {
            "hvac_modes": ["off", "cool"],
            "temperature": 25,
            "current_temperature": 27,
            "supported_features": 1 | 128,
        },
    }
    result = map_entity(state, None, None, {})
    assert result.state["target_temperature"] == 25
    assert result.capabilities == [Action.TURN_OFF, Action.SET_TEMPERATURE, Action.SET_HVAC_MODE]


def test_cover_without_position_infers_from_state():
    state = {"entity_id": "cover.curtain", "state": "closed", "attributes": {"supported_features": 3}}
    result = map_entity(state, None, None, {})
    assert result.state["position"] == 0
    assert result.capabilities == [Action.OPEN, Action.CLOSE]


@pytest.mark.parametrize(
    ("entity_id", "command", "expected"),
    [
        ("switch.plug", Command(action=Action.TOGGLE), ("switch", "toggle", {})),
        (
            "light.a",
            Command(action=Action.SET_BRIGHTNESS, params={"brightness": 40}),
            ("light", "turn_on", {"brightness_pct": 40}),
        ),
        (
            "climate.ac",
            Command(action=Action.SET_TEMPERATURE, params={"temperature": 26}),
            ("climate", "set_temperature", {"temperature": 26}),
        ),
        ("cover.c", Command(action=Action.CLOSE), ("cover", "close_cover", {})),
    ],
)
def test_command_to_service(entity_id, command, expected):
    assert command_to_service(entity_id, command) == expected


def sensor(entity_id, value, device_class=None, unit=None, name=""):
    attrs = {"friendly_name": name}
    if device_class:
        attrs["device_class"] = device_class
    if unit:
        attrs["unit_of_measurement"] = unit
    return {"entity_id": entity_id, "state": str(value), "attributes": attrs}


PURIFIER_FAN = {
    "entity_id": "fan.bedroom",
    "state": "on",
    "attributes": {
        "friendly_name": "卧室",
        "supported_features": 1 | 8,
        "percentage": 40,
        "preset_modes": ["auto", "sleep"],
        "preset_mode": "auto",
    },
}


def test_fan_with_pm25_sibling_becomes_purifier():
    siblings = [
        sensor("sensor.bedroom_pm25", 12, "pm25", "µg/m³"),
        sensor("sensor.bedroom_filter_life", 63, unit="%", name="滤芯剩余寿命"),
        sensor("sensor.bedroom_battery", 80, "battery", "%"),
    ]
    entity = {"entity_id": "fan.bedroom", "platform": "tuya", "device_id": "d1"}
    result = map_entity(PURIFIER_FAN, entity, {"id": "d1"}, {}, siblings=siblings)

    assert result.type == DeviceType.AIR_PURIFIER
    assert result.platform == Platform.TUYA
    assert result.state["pm25"] == 12
    assert result.state["filter_life"] == 63
    assert result.state["preset_mode"] == "auto"
    assert Action.SET_PRESET_MODE in result.capabilities
    assert Action.SET_FAN_SPEED in result.capabilities


def test_purifier_detected_by_model_name():
    fan = {**PURIFIER_FAN, "attributes": {"friendly_name": "风扇"}}
    result = map_entity(fan, None, {"model": "Air Purifier 4"}, {})
    assert result.type == DeviceType.AIR_PURIFIER
    assert Action.SET_PRESET_MODE not in result.capabilities


def test_plain_fan_stays_fan_and_pm25_sensor_merged_away():
    assert map_entity({**PURIFIER_FAN, "attributes": {}}, None, None, {}).type == DeviceType.FAN
    pm25 = sensor("sensor.bedroom_pm25", 12, "pm25")
    assert map_entity(pm25, None, None, {}, siblings=[PURIFIER_FAN]) is None
    # 独立的 PM2.5 传感器照常展示
    assert map_entity(pm25, None, None, {}).type == DeviceType.SENSOR


def test_lock_from_desman_integration():
    state = {"entity_id": "lock.front_door", "state": "locked", "attributes": {"friendly_name": "入户门"}}
    entity = {"entity_id": "lock.front_door", "platform": "desmanlock", "device_id": "d1"}
    result = map_entity(
        state, entity, {"id": "d1"}, {}, siblings=[sensor("sensor.lock_battery", 55, "battery")]
    )
    assert result.type == DeviceType.LOCK
    assert result.platform == Platform.DESMAN
    assert result.state == {"lock_state": "locked", "battery": 55.0}
    assert result.capabilities == [Action.LOCK, Action.UNLOCK]


def test_camera_from_imou_integration():
    state = {"entity_id": "camera.door", "state": "streaming", "attributes": {"supported_features": 2}}
    result = map_entity(state, {"platform": "imou_life"}, None, {})
    assert result.type == DeviceType.CAMERA
    assert result.platform == Platform.IMOU
    assert result.state == {"camera_state": "streaming", "stream_supported": True}
    no_stream = {**state, "attributes": {}}
    assert map_entity(no_stream, None, None, {}).state["stream_supported"] is False


@pytest.mark.parametrize(
    ("command", "expected"),
    [
        (Command(action=Action.LOCK), ("lock", "lock", {})),
        (Command(action=Action.UNLOCK), ("lock", "unlock", {})),
        (
            Command(action=Action.SET_PRESET_MODE, params={"preset_mode": "sleep"}),
            ("fan", "set_preset_mode", {"preset_mode": "sleep"}),
        ),
    ],
)
def test_new_commands_to_service(command, expected):
    assert command_to_service("lock.x" if expected[0] == "lock" else "fan.x", command) == expected


@pytest.mark.parametrize("entity_id", ["scene.away", "script.good_night"])
def test_scenes_and_scripts_are_activatable(entity_id):
    state = {"entity_id": entity_id, "state": "unknown", "attributes": {"friendly_name": "离家"}}
    result = map_entity(state, None, None, {})
    assert result.type == DeviceType.SCENE
    assert result.online is True
    assert result.capabilities == [Action.ACTIVATE]
    domain = entity_id.split(".")[0]
    assert command_to_service(entity_id, Command(action=Action.ACTIVATE)) == (domain, "turn_on", {})
