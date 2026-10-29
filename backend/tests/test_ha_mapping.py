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
