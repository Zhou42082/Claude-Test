"""Home Assistant 实体 <-> 统一设备模型 的转换（纯函数，便于单测）。"""

from __future__ import annotations

from typing import Any

from ..models import Action, Command, Device, DeviceType, Platform

# 设备来源判断：优先看实体所属的 HA 集成，其次看设备厂商。
# 华为设备走 Matter / HomeKit 等通用协议时，集成名无法区分品牌，只能靠厂商名。
INTEGRATION_PLATFORMS: dict[str, Platform] = {
    # 社区集成，华为账号登录走华为云 github.com/xiasi0/ha-huawei-smarthome
    # 华为智慧生活里的设备很多是第三方品牌（欧普、杜亚等），厂商名判断不出来，必须按集成名归类
    "huawei_smarthome": Platform.HUAWEI,
    "huawei_hilink_opple": Platform.HUAWEI,  # 欧普 HiLink 吸顶灯局域网控制 github.com/0xlic/ha-huawei-hilink-opple
    "xiaomi_home": Platform.XIAOMI,  # 小米官方集成 github.com/XiaoMi/ha_xiaomi_home
    "xiaomi_miot": Platform.XIAOMI,
    "xiaomi_miio": Platform.XIAOMI,
    "xiaomi_ble": Platform.XIAOMI,
    "xiaomi_aqara": Platform.XIAOMI,
    "tuya": Platform.TUYA,  # HA 内置涂鸦集成（智能生活 App 扫码登录）
    "localtuya": Platform.TUYA,
    "tuya_local": Platform.TUYA,
    "imou_life": Platform.IMOU,  # 乐橙开放平台官方集成 github.com/Imou-OpenPlatform/Imou-Home-Assistant
    "imou": Platform.IMOU,  # HA 内置乐橙集成
    "desmanlock": Platform.DESMAN,  # 社区集成 github.com/chliny/ha-desmanlock
}
MANUFACTURER_HINTS: list[tuple[str, Platform]] = [
    ("huawei", Platform.HUAWEI),
    ("hilink", Platform.HUAWEI),
    ("xiaomi", Platform.XIAOMI),
    ("mijia", Platform.XIAOMI),
    ("tuya", Platform.TUYA),
    ("imou", Platform.IMOU),
    ("乐橙", Platform.IMOU),
    ("desman", Platform.DESMAN),
    ("德施曼", Platform.DESMAN),
    ("qihoo", Platform.QIHOO360),
]

DOMAIN_TYPES: dict[str, DeviceType] = {
    "light": DeviceType.LIGHT,
    "switch": DeviceType.SWITCH,
    "climate": DeviceType.CLIMATE,
    "cover": DeviceType.COVER,
    "fan": DeviceType.FAN,
    "sensor": DeviceType.SENSOR,
    "binary_sensor": DeviceType.BINARY_SENSOR,
    "lock": DeviceType.LOCK,
    "camera": DeviceType.CAMERA,
    # 场景和脚本在 HA 里配置（或用 HA 的场景编辑器），App 里一键执行
    "scene": DeviceType.SCENE,
    "script": DeviceType.SCENE,
}

# fan 实体满足以下任一条件时视为空气净化器：名称 / 型号含关键词，或同一设备上有 PM2.5 传感器
PURIFIER_KEYWORDS = ("purifier", "净化")
FILTER_KEYWORDS = ("filter", "滤芯", "滤网")

# 只展示对用户有意义的传感器，信号强度、电池电压之类的诊断数据不进 App
SENSOR_CLASSES = {"temperature", "humidity", "pm25", "carbon_dioxide", "illuminance", "power"}
BINARY_SENSOR_CLASSES = {"door", "window", "opening", "motion", "occupancy", "moisture", "smoke", "gas"}

# HA 的 supported_features 位
FAN_SET_SPEED = 1
FAN_PRESET_MODE = 8
CAMERA_STREAM = 2
COVER_SET_POSITION = 4
COVER_STOP = 8
CLIMATE_TARGET_TEMPERATURE = 1
CLIMATE_TURN_OFF = 128
CLIMATE_TURN_ON = 256

_ONOFF = [Action.TURN_ON, Action.TURN_OFF, Action.TOGGLE]


def resolve_platform(integration: str | None, manufacturer: str | None) -> Platform:
    if integration in INTEGRATION_PLATFORMS:
        return INTEGRATION_PLATFORMS[integration]
    lowered = (manufacturer or "").lower()
    for hint, platform in MANUFACTURER_HINTS:
        if hint in lowered:
            return platform
    return Platform.OTHER


def map_entity(
    state: dict[str, Any],
    entity: dict[str, Any] | None,
    device: dict[str, Any] | None,
    areas: dict[str, str],
    adapter_name: str = "ha",
    siblings: list[dict[str, Any]] | None = None,
) -> Device | None:
    """把一个 HA 实体转换成统一设备；不需要展示的实体返回 None。

    siblings 是同一个 HA 设备下其他实体的状态。HA 把一台净化器拆成风扇 + PM2.5 传感器 +
    滤芯传感器等多个实体，这里把 PM2.5、滤芯、电量等合并到主实体上，App 只看到一台设备。
    """
    siblings = siblings or []
    entity_id: str = state["entity_id"]
    domain = entity_id.split(".", 1)[0]
    device_type = DOMAIN_TYPES.get(domain)
    if device_type is None:
        return None

    entity = entity or {}
    device = device or {}
    if entity.get("disabled_by") or entity.get("hidden_by") or entity.get("entity_category"):
        return None

    attrs: dict[str, Any] = state.get("attributes", {})
    device_class = attrs.get("device_class") or entity.get("device_class")
    if device_type == DeviceType.SENSOR and device_class not in SENSOR_CLASSES:
        return None
    if device_type == DeviceType.SENSOR and device_class == "pm25" and _has_domain(siblings, "fan"):
        return None  # 已合并到净化器
    if device_type == DeviceType.BINARY_SENSOR and device_class not in BINARY_SENSOR_CLASSES:
        return None

    area_id = entity.get("area_id") or device.get("area_id")
    name = (
        attrs.get("friendly_name")
        or entity.get("name")
        or entity.get("original_name")
        or device.get("name_by_user")
        or device.get("name")
        or entity_id
    )
    if device_type == DeviceType.FAN and _is_purifier(entity_id, name, device, siblings):
        device_type = DeviceType.AIR_PURIFIER

    raw_state = state.get("state")
    unified_state, capabilities = _map_state(device_type, raw_state, attrs)
    if device_class:
        unified_state["device_class"] = device_class
    _merge_siblings(device_type, unified_state, siblings)

    return Device(
        id=f"{adapter_name}:{entity_id}",
        name=name,
        type=device_type,
        platform=resolve_platform(entity.get("platform"), device.get("manufacturer")),
        room=areas.get(area_id) if area_id else None,
        online=raw_state != "unavailable",
        state=unified_state,
        capabilities=capabilities,
    )


def _map_state(
    device_type: DeviceType, raw: str | None, attrs: dict[str, Any]
) -> tuple[dict[str, Any], list[Action]]:
    features = int(attrs.get("supported_features") or 0)
    s: dict[str, Any] = {}
    caps: list[Action] = []

    match device_type:
        case DeviceType.LIGHT:
            s["on"] = raw == "on"
            caps = list(_ONOFF)
            modes = set(attrs.get("supported_color_modes") or [])
            if modes - {"onoff", "unknown"}:
                caps.append(Action.SET_BRIGHTNESS)
                if attrs.get("brightness") is not None:
                    s["brightness"] = round(attrs["brightness"] / 255 * 100)
            if "color_temp" in modes:
                caps.append(Action.SET_COLOR_TEMP)
                for key in ("color_temp_kelvin", "min_color_temp_kelvin", "max_color_temp_kelvin"):
                    if attrs.get(key) is not None:
                        s[key] = attrs[key]
        case DeviceType.SWITCH:
            s["on"] = raw == "on"
            caps = list(_ONOFF)
        case DeviceType.FAN | DeviceType.AIR_PURIFIER:
            s["on"] = raw == "on"
            caps = list(_ONOFF)
            if features & FAN_SET_SPEED:
                caps.append(Action.SET_FAN_SPEED)
                if attrs.get("percentage") is not None:
                    s["percentage"] = attrs["percentage"]
            if features & FAN_PRESET_MODE and attrs.get("preset_modes"):
                caps.append(Action.SET_PRESET_MODE)
                s["preset_modes"] = attrs["preset_modes"]
                s["preset_mode"] = attrs.get("preset_mode")
        case DeviceType.CLIMATE:
            s["hvac_mode"] = raw
            s["hvac_modes"] = attrs.get("hvac_modes", [])
            s["current_temperature"] = attrs.get("current_temperature")
            s["target_temperature"] = attrs.get("temperature")
            if features & CLIMATE_TURN_ON:
                caps.append(Action.TURN_ON)
            if features & CLIMATE_TURN_OFF:
                caps.append(Action.TURN_OFF)
            if features & CLIMATE_TARGET_TEMPERATURE:
                caps.append(Action.SET_TEMPERATURE)
            if s["hvac_modes"]:
                caps.append(Action.SET_HVAC_MODE)
        case DeviceType.COVER:
            if attrs.get("current_position") is not None:
                s["position"] = attrs["current_position"]
            else:
                s["position"] = 0 if raw == "closed" else 100
            if raw in ("opening", "closing"):
                s["moving"] = raw
            caps = [Action.OPEN, Action.CLOSE]
            if features & COVER_STOP:
                caps.append(Action.STOP)
            if features & COVER_SET_POSITION:
                caps.append(Action.SET_POSITION)
        case DeviceType.SENSOR:
            s["value"] = _number_or_raw(raw)
            s["unit"] = attrs.get("unit_of_measurement")
        case DeviceType.BINARY_SENSOR:
            s["on"] = raw == "on"
        case DeviceType.LOCK:
            s["lock_state"] = raw
            caps = [Action.LOCK, Action.UNLOCK]
        case DeviceType.CAMERA:
            s["camera_state"] = raw
            s["stream_supported"] = bool(features & CAMERA_STREAM)
        case DeviceType.SCENE:
            # scene 的状态是上次执行时间，script 的状态是是否正在运行
            caps = [Action.ACTIVATE]
    return s, caps


def _has_domain(states: list[dict[str, Any]], domain: str) -> bool:
    return any(st["entity_id"].startswith(f"{domain}.") for st in states)


def _is_purifier(entity_id: str, name: str, device: dict[str, Any], siblings: list[dict[str, Any]]) -> bool:
    text = " ".join(str(v).lower() for v in (entity_id, name, device.get("name"), device.get("model")) if v)
    if any(k in text for k in PURIFIER_KEYWORDS):
        return True
    return any(
        st["entity_id"].startswith("sensor.") and st.get("attributes", {}).get("device_class") == "pm25"
        for st in siblings
    )


def _merge_siblings(device_type: DeviceType, s: dict[str, Any], siblings: list[dict[str, Any]]) -> None:
    for st in siblings:
        if not st["entity_id"].startswith("sensor."):
            continue
        attrs = st.get("attributes", {})
        value = _number_or_raw(st.get("state"))
        if not isinstance(value, float):
            continue
        device_class = attrs.get("device_class")
        if device_class == "battery" and device_type != DeviceType.SENSOR:
            s["battery"] = value
        elif device_type == DeviceType.AIR_PURIFIER:
            label = f"{st['entity_id']} {attrs.get('friendly_name', '')}".lower()
            if device_class == "pm25":
                s["pm25"] = value
            elif attrs.get("unit_of_measurement") == "%" and any(k in label for k in FILTER_KEYWORDS):
                s["filter_life"] = value


def _number_or_raw(raw: str | None) -> Any:
    try:
        return float(raw) if raw is not None else None
    except ValueError:
        return raw


def command_to_service(entity_id: str, command: Command) -> tuple[str, str, dict[str, Any]]:
    """统一命令 -> HA 服务调用 (domain, service, service_data)。"""
    domain = entity_id.split(".", 1)[0]
    p = command.params
    match command.action:
        case Action.TURN_ON | Action.TURN_OFF | Action.TOGGLE:
            return domain, command.action.value, {}
        case Action.SET_BRIGHTNESS:
            return "light", "turn_on", {"brightness_pct": p["brightness"]}
        case Action.SET_COLOR_TEMP:
            return "light", "turn_on", {"color_temp_kelvin": p["color_temp_kelvin"]}
        case Action.SET_TEMPERATURE:
            return "climate", "set_temperature", {"temperature": p["temperature"]}
        case Action.SET_HVAC_MODE:
            return "climate", "set_hvac_mode", {"hvac_mode": p["hvac_mode"]}
        case Action.SET_FAN_SPEED:
            return "fan", "set_percentage", {"percentage": p["percentage"]}
        case Action.SET_PRESET_MODE:
            return "fan", "set_preset_mode", {"preset_mode": p["preset_mode"]}
        case Action.ACTIVATE:
            return domain, "turn_on", {}
        case Action.LOCK:
            return "lock", "lock", {}
        case Action.UNLOCK:
            return "lock", "unlock", {}
        case Action.SET_POSITION:
            return "cover", "set_cover_position", {"position": p["position"]}
        case Action.OPEN:
            return "cover", "open_cover", {}
        case Action.CLOSE:
            return "cover", "close_cover", {}
        case Action.STOP:
            return "cover", "stop_cover", {}
    raise ValueError(f"unsupported action {command.action}")
