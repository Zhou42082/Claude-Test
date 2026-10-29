from __future__ import annotations

from abc import ABC, abstractmethod
from collections.abc import Awaitable, Callable
from typing import NamedTuple

from ..models import Command, Device, DeviceEvent

EventCallback = Callable[[DeviceEvent], Awaitable[None]]


class MediaContent(NamedTuple):
    content: bytes
    content_type: str


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

    async def snapshot(self, native_id: str) -> MediaContent:
        """摄像头当前画面（JPEG / PNG）。"""
        raise AdapterError("该设备不支持画面截图")

    async def stream_url(self, native_id: str) -> str:
        """摄像头实时视频的 HLS 地址，以 /api/hls/ 开头，由网关的 HLS 代理转发。"""
        raise AdapterError("该设备不支持实时视频")

    async def fetch_hls(self, path: str) -> MediaContent | None:
        """转发 HLS 播放列表和分片；不是本适配器的路径返回 None。"""
        return None

    def demo_scenarios(self) -> dict[str, str]:
        """演示场景 ID -> 名称。只有演示适配器提供。"""
        return {}

    async def run_demo(self, scenario: str) -> None:
        raise DeviceNotFound(scenario)

    def device_id(self, native_id: str) -> str:
        return f"{self.name}:{native_id}"
