"""统一设备模型：所有平台的设备都转换成这里的结构后再交给移动端。"""

from __future__ import annotations

from enum import StrEnum
from typing import Any, Literal

from pydantic import BaseModel, Field, model_validator


class Platform(StrEnum):
    """设备所属的生态平台，用于在 App 中标注来源。"""

    XIAOMI = "xiaomi"  # 小米 / 米家
    HUAWEI = "huawei"  # 华为智慧生活 (HiLink)
    TUYA = "tuya"  # 涂鸦智能生活 (Smart Life)，App Store 上的「智能生活 - 智慧家居」也是它
    IMOU = "imou"  # 乐橙
    DESMAN = "desman"  # 德施曼
    QIHOO360 = "qihoo360"  # 360 智能家居
    OTHER = "other"


class DeviceType(StrEnum):
    LIGHT = "light"
    SWITCH = "switch"
    CLIMATE = "climate"
    COVER = "cover"
    FAN = "fan"
    SENSOR = "sensor"
    BINARY_SENSOR = "binary_sensor"
    LOCK = "lock"
    CAMERA = "camera"
    AIR_PURIFIER = "air_purifier"


class Action(StrEnum):
    TURN_ON = "turn_on"
    TURN_OFF = "turn_off"
    TOGGLE = "toggle"
    SET_BRIGHTNESS = "set_brightness"
    SET_COLOR_TEMP = "set_color_temp"
    SET_TEMPERATURE = "set_temperature"
    SET_HVAC_MODE = "set_hvac_mode"
    SET_POSITION = "set_position"
    SET_FAN_SPEED = "set_fan_speed"
    OPEN = "open"
    CLOSE = "close"
    STOP = "stop"
    SET_PRESET_MODE = "set_preset_mode"
    LOCK = "lock"
    UNLOCK = "unlock"


# 敏感动作：网关需要额外校验开锁 PIN（见 config.Settings.unlock_pin）
SENSITIVE_ACTIONS = frozenset({Action.UNLOCK})
# 需要字符串参数的动作：动作 -> 参数名
STRING_PARAMS: dict[Action, str] = {
    Action.SET_HVAC_MODE: "hvac_mode",
    Action.SET_PRESET_MODE: "preset_mode",
}

# 需要数值参数的动作：动作 -> (参数名, 最小值, 最大值)
NUMERIC_PARAMS: dict[Action, tuple[str, float, float]] = {
    Action.SET_BRIGHTNESS: ("brightness", 0, 100),
    Action.SET_COLOR_TEMP: ("color_temp_kelvin", 1500, 9000),
    Action.SET_TEMPERATURE: ("temperature", 5, 35),
    Action.SET_POSITION: ("position", 0, 100),
    Action.SET_FAN_SPEED: ("percentage", 0, 100),
}


class Device(BaseModel):
    """统一设备。

    state 中使用的约定字段：
      on: bool                     开关状态（灯、开关、风扇、二元传感器）
      brightness: int 0-100        亮度
      color_temp_kelvin: int       色温
      current_temperature: float   当前温度（空调）
      target_temperature: float    目标温度（空调）
      hvac_mode: str               空调模式 off/cool/heat/auto/dry/fan_only
      hvac_modes: list[str]        支持的空调模式
      position: int 0-100          窗帘开合度
      moving: str                  opening / closing（窗帘运动中）
      percentage: int 0-100        风速
      preset_mode: str             风扇 / 净化器模式（auto、sleep 等，取值来自设备）
      preset_modes: list[str]      支持的模式
      pm25: float                  PM2.5（净化器，来自同一设备的传感器）
      filter_life: float 0-100     滤芯剩余寿命（净化器）
      lock_state: str              门锁状态 locked/unlocked/locking/unlocking/jammed/open
      battery: float 0-100         电量（门锁、传感器等电池设备）
      camera_state: str            摄像头状态 idle/streaming/recording
      stream_supported: bool       摄像头是否支持实时视频
      value: Any, unit: str        传感器读数及单位
    """

    id: str = Field(description="全局唯一 ID，格式为 '<adapter>:<原始 ID>'")
    name: str
    type: DeviceType
    platform: Platform
    room: str | None = None
    online: bool = True
    state: dict[str, Any] = Field(default_factory=dict)
    capabilities: list[Action] = Field(default_factory=list)


class Command(BaseModel):
    action: Action
    params: dict[str, Any] = Field(default_factory=dict)

    @model_validator(mode="after")
    def _check_params(self) -> Command:
        if self.action in NUMERIC_PARAMS:
            key, lo, hi = NUMERIC_PARAMS[self.action]
            value = self.params.get(key)
            if isinstance(value, bool) or not isinstance(value, (int, float)):
                raise ValueError(f"动作 {self.action} 需要数值参数 '{key}'")
            if not lo <= value <= hi:
                raise ValueError(f"参数 '{key}' 必须在 {lo} 到 {hi} 之间")
        elif self.action in STRING_PARAMS:
            key = STRING_PARAMS[self.action]
            if not isinstance(self.params.get(key), str):
                raise ValueError(f"动作 {self.action} 需要字符串参数 '{key}'")
        return self


class DeviceEvent(BaseModel):
    type: Literal["device_updated", "device_removed"]
    device: Device
