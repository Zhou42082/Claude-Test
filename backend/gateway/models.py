"""统一设备模型：所有平台的设备都转换成这里的结构后再交给移动端。"""

from __future__ import annotations

from enum import StrEnum
from typing import Any, Literal

from pydantic import BaseModel, Field, model_validator


class Platform(StrEnum):
    """设备所属的生态平台，用于在 App 中标注来源。"""

    XIAOMI = "xiaomi"  # 小米 / 米家
    HUAWEI = "huawei"  # 华为智慧生活 (HiLink)
    TUYA = "tuya"  # 涂鸦智能生活 (Smart Life)
    OTHER = "other"


class DeviceType(StrEnum):
    LIGHT = "light"
    SWITCH = "switch"
    CLIMATE = "climate"
    COVER = "cover"
    FAN = "fan"
    SENSOR = "sensor"
    BINARY_SENSOR = "binary_sensor"


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
        elif self.action == Action.SET_HVAC_MODE:
            if not isinstance(self.params.get("hvac_mode"), str):
                raise ValueError("动作 set_hvac_mode 需要字符串参数 'hvac_mode'")
        return self


class DeviceEvent(BaseModel):
    type: Literal["device_updated", "device_removed"]
    device: Device
