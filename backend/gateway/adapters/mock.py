"""演示用适配器：不需要任何真实设备即可跑通 App 全流程。"""

from __future__ import annotations

import asyncio
import struct
import zlib
from datetime import UTC, datetime

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
            state={
                "camera_state": "idle",
                "stream_supported": False,
                "ptz_directions": ["up", "down", "left", "right"],
                "last_ring": None,
                "motion": False,
            },
            capabilities=[Action.PTZ],
        ),
        Device(
            id="mock:kitchen_leak",
            name="厨房水浸传感器",
            type=DeviceType.BINARY_SENSOR,
            platform=Platform.XIAOMI,
            room="厨房",
            state={"on": False, "device_class": "moisture", "battery": 90},
        ),
        Device(
            id="mock:living_smoke",
            name="客厅烟雾报警器",
            type=DeviceType.BINARY_SENSOR,
            platform=Platform.HUAWEI,
            room="客厅",
            state={"on": False, "device_class": "smoke"},
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
        *(
            Device(
                id=f"mock:{key}",
                name=name,
                type=DeviceType.SCENE,
                platform=Platform.OTHER,
                capabilities=[Action.ACTIVATE],
            )
            for key, (name, _) in _SCENES.items()
        ),
    ]


def _cmd(action: Action, **params: object) -> Command:
    return Command(action=action, params=params)


# 演示场景：场景 ID -> (名称, [(设备原始 ID, 命令)])
_SCENES: dict[str, tuple[str, list[tuple[str, Command]]]] = {
    "scene_home": (
        "回家",
        [
            ("living_light", _cmd(Action.TURN_ON)),
            ("living_curtain", _cmd(Action.OPEN)),
            ("living_ac", _cmd(Action.TURN_ON)),
        ],
    ),
    "scene_away": (
        "离家",
        [
            ("living_light", _cmd(Action.TURN_OFF)),
            ("bedroom_lamp", _cmd(Action.TURN_OFF)),
            ("bedroom_fan", _cmd(Action.TURN_OFF)),
            ("living_ac", _cmd(Action.TURN_OFF)),
            ("kitchen_plug", _cmd(Action.TURN_OFF)),
            ("living_curtain", _cmd(Action.CLOSE)),
            ("entrance_lock", _cmd(Action.LOCK)),
        ],
    ),
    "scene_sleep": (
        "睡眠",
        [
            ("living_light", _cmd(Action.TURN_OFF)),
            ("bedroom_lamp", _cmd(Action.TURN_OFF)),
            ("living_curtain", _cmd(Action.CLOSE)),
            ("bedroom_purifier", _cmd(Action.SET_PRESET_MODE, preset_mode="sleep")),
        ],
    ),
}


def _camera_png(pan: int, tilt: int, width: int = 320, height: int = 180) -> bytes:
    """画一张简单的门口画面：墙、地面和一扇门。门的位置随云台转动而移动，便于测试云台。"""

    def chunk(kind: bytes, data: bytes) -> bytes:
        return struct.pack(">I", len(data)) + kind + data + struct.pack(">I", zlib.crc32(kind + data))

    horizon = height * 2 // 3 + tilt * 15
    door_left = width // 2 - 30 - pan * 40
    door_top = horizon - 90
    rows = bytearray()
    for y in range(height):
        rows.append(0)  # PNG 行过滤类型：None
        for x in range(width):
            if door_left <= x < door_left + 60 and door_top <= y < horizon:
                rgb = (121, 85, 72)  # 门
            elif y >= horizon:
                rgb = (96, 125, 139)  # 地面
            else:
                shade = 200 - y // 4
                rgb = (shade, shade - 10, shade - 30)  # 墙
            rows += bytes(max(0, min(255, c)) for c in rgb)
    return (
        b"\x89PNG\r\n\x1a\n"
        + chunk(b"IHDR", struct.pack(">IIBBBBB", width, height, 8, 2, 0, 0, 0))
        + chunk(b"IDAT", zlib.compress(bytes(rows)))
        + chunk(b"IEND", b"")
    )


# 演示工具：模拟告警场景，便于在没有真实设备时测试告警和界面
DEMO_SCENARIOS: dict[str, str] = {
    "leak": "厨房漏水",
    "smoke": "客厅烟雾报警",
    "doorbell": "有人按门铃",
    "motion": "门口有人经过",
    "lock_jam": "门锁卡住",
    "low_battery": "门锁电量低",
    "filter_low": "净化器滤芯耗尽",
    "camera_offline": "摄像头离线",
    "reset": "全部恢复初始状态",
}
MOTION_SECONDS = 15


class MockAdapter(DeviceAdapter):
    name = "mock"

    def __init__(self) -> None:
        self._devices = {d.id: d for d in _seed()}
        self._on_event: EventCallback | None = None
        self._pan = 0
        self._tilt = 0
        self._motion_reset: asyncio.Task[None] | None = None

    async def start(self, on_event: EventCallback) -> None:
        self._on_event = on_event

    async def stop(self) -> None:
        self._on_event = None
        if self._motion_reset:
            self._motion_reset.cancel()

    async def list_devices(self) -> list[Device]:
        return [d.model_copy(deep=True) for d in self._devices.values()]

    async def snapshot(self, native_id: str) -> MediaContent:
        device = self._devices.get(self.device_id(native_id))
        if device is None or device.type != DeviceType.CAMERA:
            raise DeviceNotFound(native_id)
        return MediaContent(_camera_png(self._pan, self._tilt), "image/png")

    async def execute(self, native_id: str, command: Command) -> None:
        device = self._devices.get(self.device_id(native_id))
        if device is None:
            raise DeviceNotFound(native_id)
        if not device.online:
            raise AdapterError(f"设备 {device.name} 离线")
        if command.action == Action.ACTIVATE:
            await self._run_scene(native_id)
            return

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
            case Action.PTZ:
                dx, dy = {"left": (-1, 0), "right": (1, 0), "up": (0, -1), "down": (0, 1)}[p["direction"]]
                self._pan = max(-2, min(2, self._pan + dx))
                self._tilt = max(-2, min(2, self._tilt + dy))

        await self._emit(device)

    def demo_scenarios(self) -> dict[str, str]:
        return DEMO_SCENARIOS

    async def run_demo(self, scenario: str) -> None:
        match scenario:
            case "leak":
                await self._update("kitchen_leak", on=True)
            case "smoke":
                await self._update("living_smoke", on=True)
            case "doorbell":
                await self._update("entrance_cam", last_ring=datetime.now(UTC).isoformat())
            case "motion":
                await self._update("entrance_cam", motion=True)
                if self._motion_reset:
                    self._motion_reset.cancel()
                self._motion_reset = asyncio.create_task(self._clear_motion())
            case "lock_jam":
                await self._update("entrance_lock", lock_state="jammed")
            case "low_battery":
                await self._update("entrance_lock", battery=15)
            case "filter_low":
                await self._update("bedroom_purifier", filter_life=5)
            case "camera_offline":
                device = self._devices[self.device_id("entrance_cam")]
                device.online = False
                await self._emit(device)
            case "reset":
                self._pan = self._tilt = 0
                for fresh in _seed():
                    if self._devices[fresh.id] != fresh:
                        self._devices[fresh.id] = fresh
                        await self._emit(fresh)
            case _:
                raise DeviceNotFound(scenario)

    async def _clear_motion(self) -> None:
        await asyncio.sleep(MOTION_SECONDS)
        await self._update("entrance_cam", motion=False)

    async def _update(self, native_id: str, **state: object) -> None:
        device = self._devices[self.device_id(native_id)]
        device.state.update(state)
        await self._emit(device)

    async def _emit(self, device: Device) -> None:
        if self._on_event:
            await self._on_event(DeviceEvent(type="device_updated", device=device.model_copy(deep=True)))

    async def _run_scene(self, scene_id: str) -> None:
        # 和 HA 场景一样尽力执行：某个设备失败不影响其他设备
        for native_id, command in _SCENES[scene_id][1]:
            device = self._devices[self.device_id(native_id)]
            if device.online and command.action in device.capabilities:
                await self.execute(native_id, command)
