"""告警规则：比较设备状态的前后变化，只在状态「跨过」阈值时产生一次告警。"""

from __future__ import annotations

import itertools
from collections import deque
from datetime import UTC, datetime

from .models import Alert, AlertLevel, Device, DeviceType

LOW_BATTERY = 20
LOW_FILTER = 10
HAZARDS = {"moisture": "漏水", "smoke": "烟雾", "gas": "燃气泄漏"}
# 离线需要提醒的设备：安防类，离线意味着可能失去保护
SECURITY_TYPES = {DeviceType.LOCK, DeviceType.CAMERA}


def detect_alerts(old: Device | None, new: Device) -> list[tuple[AlertLevel, str]]:
    """返回 (级别, 消息) 列表。old 为 None（首次出现的设备）时不告警，避免网关重启时刷屏。"""
    if old is None:
        return []
    found: list[tuple[AlertLevel, str]] = []
    o, n = old.state, new.state

    hazard = HAZARDS.get(n.get("device_class", ""))
    if new.type == DeviceType.BINARY_SENSOR and hazard and n.get("on") and not o.get("on"):
        found.append((AlertLevel.CRITICAL, f"检测到{hazard}"))

    if new.type == DeviceType.LOCK:
        before, after = o.get("lock_state"), n.get("lock_state")
        if after == "jammed" and before != "jammed":
            found.append((AlertLevel.CRITICAL, "门锁卡住，请检查"))
        elif after in ("unlocked", "open") and before == "locked":
            found.append((AlertLevel.INFO, "门锁已打开"))

    is_security = new.type in SECURITY_TYPES or (new.type == DeviceType.BINARY_SENSOR and hazard)
    if is_security and old.online and not new.online:
        found.append((AlertLevel.WARNING, "设备离线"))

    if _crossed_below(o.get("battery"), n.get("battery"), LOW_BATTERY):
        found.append((AlertLevel.WARNING, f"电量低（{round(n['battery'])}%），请更换电池或充电"))
    if _crossed_below(o.get("filter_life"), n.get("filter_life"), LOW_FILTER):
        found.append((AlertLevel.WARNING, f"滤芯剩余 {round(n['filter_life'])}%，请及时更换"))
    return found


def _crossed_below(before: object, after: object, threshold: float) -> bool:
    if not isinstance(after, (int, float)) or after >= threshold:
        return False
    # 之前没有读数时也视为跨过（例如传感器刚恢复上报）
    return not isinstance(before, (int, float)) or before >= threshold


class AlertLog:
    """最近的告警，保存在内存中（网关重启后清空）。"""

    def __init__(self, maxlen: int = 200) -> None:
        self._alerts: deque[Alert] = deque(maxlen=maxlen)
        self._ids = itertools.count(1)

    def add(self, device: Device, level: AlertLevel, message: str) -> Alert:
        alert = Alert(
            id=next(self._ids),
            time=datetime.now(UTC),
            level=level,
            device_id=device.id,
            device_name=device.name,
            room=device.room,
            message=message,
        )
        self._alerts.append(alert)
        return alert

    def recent(self, limit: int = 50) -> list[Alert]:
        """最新的在前。"""
        return list(reversed(self._alerts))[:limit]
