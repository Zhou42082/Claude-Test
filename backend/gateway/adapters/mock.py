"""演示用适配器：不需要任何真实设备即可跑通 App 全流程。"""

from __future__ import annotations

import struct
import zlib

from ..models import Action, Command, Device, DeviceEvent, DeviceType, Platform
from .base import AdapterError, DeviceAdapter, DeviceNotFound, EventCallback, MediaContent

_ONOFF = [Action.TURN_ON, Action.TURN_OFF, Action.TOGGLE]


def _seed() -> list[Device]:
    return [
        Device(
            id="mock:living_light",
            name="客厅吸顶灯",
            type=DeviceType.LIGHT,
            platform=Platform.XIAOMI,
            room="客厅",
            state={"on": True, "brightness": 80, "color_temp_kelvin": 4000},
            capabilities=[*_ONOFF, Action.SET_BRIGHTNESS, Action.SET_COLOR_TEMP],
        ),
        Device(
            id="mock:living_ac",
            name="客厅空调",
            type=DeviceType.CLIMATE,
            platform=Platform.HUAWEI,
            room="客厅",
            state={
                "hvac_mode": "cool",
                "hvac_modes": ["off", "cool", "heat", "auto", "dry", "fan_only"],
                "current_temperature": 27.5,
                "target_temperature": 25,
            },
            capabilities=[*_ONOFF[:2], Action.SET_TEMPERATURE, Action.SET_HVAC_MODE],
        ),
        Device(
            id="mock:living_curtain",
            name="客厅窗帘",
            type=DeviceType.COVER,
            platform=Platform.TUYA,
            room="客厅",
            state={"position": 100},
            capabilities=[Action.OPEN, Action.CLOSE, Action.STOP, Action.SET_POSITION],
        ),
        Device(
            id="mock:bedroom_lamp",
            name="卧室床头灯",
            type=DeviceType.LIGHT,
            platform=Platform.TUYA,
            room="卧室",
            state={"on": False, "brightness": 30},
            capabilities=[*_ONOFF, Action.SET_BRIGHTNESS],
        ),
        Device(
            id="mock:bedroom_fan",
            name="卧室风扇",
            type=DeviceType.FAN,
            platform=Platform.XIAOMI,
            room="卧室",
            state={"on": False, "percentage": 40},
            capabilities=[*_ONOFF, Action.SET_FAN_SPEED],
        ),
        Device(
            id="mock:bedroom_th",
            name="卧室温湿度计",
            type=DeviceType.SENSOR,
            platform=Platform.XIAOMI,
            room="卧室",
            state={"value": 24.6, "unit": "°C", "device_class": "temperature"},
        ),
        Device(
            id="mock:kitchen_plug",
            name="厨房智能插座",
            type=DeviceType.SWITCH,
            platform=Platform.HUAWEI,
            room="厨房",
            state={"on": True},
            capabilities=_ONOFF,
        ),
        Device(
            id="mock:kitchen_door",
            name="厨房门窗传感器",
            type=DeviceType.BINARY_SENSOR,
            platform=Platform.TUYA,
            room="厨房",
            online=False,
            state={"on": False, "device_class": "door"},
        ),
        Device(
            id="mock:entrance_cam",
            name="门口摄像头",
            type=DeviceType.CAMERA,
            platform=Platform.IMOU,
            room="门口",
            state={"camera_state": "idle", "stream_supported": False},
        ),
        Device(
            id="mock:entrance_lock",
            name="入户门锁",
            type=DeviceType.LOCK,
            platform=Platform.DESMAN,
            room="门口",
            state={"lock_state": "locked", "battery": 76},
            capabilities=[Action.LOCK, Action.UNLOCK],
        ),
        Device(
            id="mock:bedroom_purifier",
            name="卧室空气净化器",
            type=DeviceType.AIR_PURIFIER,
            platform=Platform.TUYA,
            room="卧室",
            state={
                "on": True,
                "percentage": 50,
                "preset_mode": "auto",
                "preset_modes": ["auto", "sleep", "strong"],
                "pm25": 18,
                "filter_life": 63,
            },
            capabilities=[*_ONOFF, Action.SET_FAN_SPEED, Action.SET_PRESET_MODE],
        ),
    ]


def _solid_png(width: int, height: int, rgb: tuple[int, int, int]) -> bytes:
    """生成纯色 PNG，作为演示摄像头的画面。"""

    def chunk(kind: bytes, data: bytes) -> bytes:
        return struct.pack(">I", len(data)) + kind + data + struct.pack(">I", zlib.crc32(kind + data))

    row = b"\x00" + bytes(rgb) * width
    return (
        b"\x89PNG\r\n\x1a\n"
        + chunk(b"IHDR", struct.pack(">IIBBBBB", width, height, 8, 2, 0, 0, 0))
        + chunk(b"IDAT", zlib.compress(row * height))
        + chunk(b"IEND", b"")
    )


class MockAdapter(DeviceAdapter):
    name = "mock"

    def __init__(self) -> None:
        self._devices = {d.id: d for d in _seed()}
        self._on_event: EventCallback | None = None

    async def start(self, on_event: EventCallback) -> None:
        self._on_event = on_event

    async def stop(self) -> None:
        self._on_event = None

    async def list_devices(self) -> list[Device]:
        return [d.model_copy(deep=True) for d in self._devices.values()]

    async def snapshot(self, native_id: str) -> MediaContent:
        device = self._devices.get(self.device_id(native_id))
        if device is None or device.type != DeviceType.CAMERA:
            raise DeviceNotFound(native_id)
        return MediaContent(_solid_png(320, 180, (46, 125, 107)), "image/png")

    async def execute(self, native_id: str, command: Command) -> None:
        device = self._devices.get(self.device_id(native_id))
        if device is None:
            raise DeviceNotFound(native_id)
        if not device.online:
            raise AdapterError(f"设备 {device.name} 离线")

        s = device.state
        p = command.params
        match command.action:
            case Action.TURN_ON:
                if device.type == DeviceType.CLIMATE:
                    s["hvac_mode"] = "auto"
                else:
                    s["on"] = True
            case Action.TURN_OFF:
                if device.type == DeviceType.CLIMATE:
                    s["hvac_mode"] = "off"
                else:
                    s["on"] = False
            case Action.TOGGLE:
                s["on"] = not s.get("on", False)
            case Action.SET_BRIGHTNESS:
                s["brightness"] = int(p["brightness"])
                s["on"] = s["brightness"] > 0
            case Action.SET_COLOR_TEMP:
                s["color_temp_kelvin"] = int(p["color_temp_kelvin"])
            case Action.SET_TEMPERATURE:
                s["target_temperature"] = p["temperature"]
            case Action.SET_HVAC_MODE:
                if p["hvac_mode"] not in s.get("hvac_modes", []):
                    raise AdapterError(f"不支持的模式 {p['hvac_mode']}")
                s["hvac_mode"] = p["hvac_mode"]
            case Action.SET_FAN_SPEED:
                s["percentage"] = int(p["percentage"])
                s["on"] = s["percentage"] > 0
            case Action.SET_POSITION:
                s["position"] = int(p["position"])
            case Action.OPEN:
                s["position"] = 100
            case Action.CLOSE:
                s["position"] = 0
            case Action.STOP:
                pass
            case Action.SET_PRESET_MODE:
                if p["preset_mode"] not in s.get("preset_modes", []):
                    raise AdapterError(f"不支持的模式 {p['preset_mode']}")
                s["preset_mode"] = p["preset_mode"]
            case Action.LOCK:
                s["lock_state"] = "locked"
            case Action.UNLOCK:
                s["lock_state"] = "unlocked"

        if self._on_event:
            await self._on_event(DeviceEvent(type="device_updated", device=device.model_copy(deep=True)))
