"""DeviceHub：聚合所有适配器，维护设备缓存，检测告警，并把状态变化和告警广播给已连接的 App。"""

from __future__ import annotations

import asyncio
import logging

from .adapters.base import DeviceAdapter, DeviceNotFound, MediaContent
from .alerts import AlertLog, detect_alerts
from .models import Alert, AlertEvent, Command, Device, DeviceEvent, DeviceType

log = logging.getLogger(__name__)

SUBSCRIBER_QUEUE_SIZE = 256

# 推送给 App 的消息；None 表示订阅已被丢弃
Message = DeviceEvent | AlertEvent


class CapabilityError(Exception):
    pass


class DeviceHub:
    def __init__(self, adapters: list[DeviceAdapter], alert_log: AlertLog | None = None) -> None:
        self._adapters = {a.name: a for a in adapters}
        self._devices: dict[str, Device] = {}
        self._subscribers: set[asyncio.Queue[Message | None]] = set()
        self._alerts = alert_log or AlertLog()

    async def start(self) -> None:
        for adapter in self._adapters.values():
            await adapter.start(self._handle_event)
            for device in await adapter.list_devices():
                self._devices[device.id] = device

    async def stop(self) -> None:
        for adapter in self._adapters.values():
            await adapter.stop()
        self._alerts.close()

    def list_devices(self) -> list[Device]:
        return sorted(self._devices.values(), key=lambda d: (d.room or "￿", d.name))

    def get_device(self, device_id: str) -> Device:
        try:
            return self._devices[device_id]
        except KeyError:
            raise DeviceNotFound(device_id) from None

    def alerts(self, limit: int = 50) -> list[Alert]:
        return self._alerts.recent(limit)

    def rooms(self) -> list[str]:
        return sorted({d.room for d in self._devices.values() if d.room})

    async def execute(self, device_id: str, command: Command) -> None:
        device = self.get_device(device_id)
        if command.action not in device.capabilities:
            raise CapabilityError(f"设备 {device.name} 不支持 {command.action}")
        adapter, native_id = self._route(device_id)
        await adapter.execute(native_id, command)

    async def snapshot(self, device_id: str) -> MediaContent:
        adapter, native_id = self._route_camera(device_id)
        return await adapter.snapshot(native_id)

    async def stream_url(self, device_id: str) -> str:
        adapter, native_id = self._route_camera(device_id)
        return await adapter.stream_url(native_id)

    async def fetch_hls(self, path: str) -> MediaContent | None:
        for adapter in self._adapters.values():
            if (media := await adapter.fetch_hls(path)) is not None:
                return media
        return None

    def demo_scenarios(self) -> list[dict[str, str]]:
        return [
            {"id": f"{adapter.name}:{key}", "name": name}
            for adapter in self._adapters.values()
            for key, name in adapter.demo_scenarios().items()
        ]

    async def run_demo(self, scenario_id: str) -> None:
        adapter_name, _, key = scenario_id.partition(":")
        adapter = self._adapters.get(adapter_name)
        if adapter is None or key not in adapter.demo_scenarios():
            raise DeviceNotFound(scenario_id)
        await adapter.run_demo(key)

    def _route(self, device_id: str) -> tuple[DeviceAdapter, str]:
        adapter_name, native_id = device_id.split(":", 1)
        return self._adapters[adapter_name], native_id

    def _route_camera(self, device_id: str) -> tuple[DeviceAdapter, str]:
        device = self.get_device(device_id)
        if device.type != DeviceType.CAMERA:
            raise CapabilityError(f"设备 {device.name} 不是摄像头")
        return self._route(device_id)

    def subscribe(self) -> asyncio.Queue[Message | None]:
        """订阅设备事件和告警。队列中收到 None 表示订阅已被丢弃，客户端应重连以获取完整快照。"""
        queue: asyncio.Queue[Message | None] = asyncio.Queue(SUBSCRIBER_QUEUE_SIZE)
        self._subscribers.add(queue)
        return queue

    def unsubscribe(self, queue: asyncio.Queue[Message | None]) -> None:
        self._subscribers.discard(queue)

    async def _handle_event(self, event: DeviceEvent) -> None:
        alerts: list[Alert] = []
        if event.type == "device_removed":
            self._devices.pop(event.device.id, None)
        else:
            old = self._devices.get(event.device.id)
            self._devices[event.device.id] = event.device
            for level, message in detect_alerts(old, event.device):
                if alert := self._alerts.add(event.device, level, message):
                    log.info("告警 [%s] %s：%s", level, event.device.name, message)
                    alerts.append(alert)
        self._broadcast(event)
        for alert in alerts:
            self._broadcast(AlertEvent(alert=alert))

    def _broadcast(self, message: Message) -> None:
        for queue in list(self._subscribers):
            try:
                queue.put_nowait(message)
            except asyncio.QueueFull:
                # 客户端消费太慢：丢弃该订阅，客户端重连后会拿到完整快照
                log.warning("subscriber queue full, dropping subscriber")
                self._subscribers.discard(queue)
                while not queue.empty():
                    queue.get_nowait()
                queue.put_nowait(None)
