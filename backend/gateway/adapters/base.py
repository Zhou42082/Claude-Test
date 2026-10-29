from __future__ import annotations

from abc import ABC, abstractmethod
from collections.abc import Awaitable, Callable

from ..models import Command, Device, DeviceEvent

EventCallback = Callable[[DeviceEvent], Awaitable[None]]


class DeviceNotFound(Exception):
    pass


class AdapterError(Exception):
    """下游平台执行失败（网络错误、平台拒绝等）。"""


class DeviceAdapter(ABC):
    """平台适配器。

    每个适配器负责把一个下游设备来源（Home Assistant、Mock、未来可能的直连云 API）
    转换成统一的 Device 模型。适配器返回的 Device.id 必须以 f"{name}:" 开头，
    DeviceHub 依靠这个前缀把命令路由回对应的适配器。
    """

    name: str

    @abstractmethod
    async def start(self, on_event: EventCallback) -> None:
        """建立连接，并在设备状态变化时调用 on_event。"""

    @abstractmethod
    async def stop(self) -> None: ...

    @abstractmethod
    async def list_devices(self) -> list[Device]: ...

    @abstractmethod
    async def execute(self, native_id: str, command: Command) -> None:
        """执行命令。native_id 是去掉 '<name>:' 前缀后的原始 ID。"""

    def device_id(self, native_id: str) -> str:
        return f"{self.name}:{native_id}"
