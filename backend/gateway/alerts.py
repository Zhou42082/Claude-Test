"""告警规则：比较设备状态的前后变化，只在状态「跨过」阈值时产生一次告警。"""

from __future__ import annotations

import sqlite3
import time
from datetime import UTC, datetime

from .models import Alert, AlertLevel, Device, DeviceType

LOW_BATTERY = 20
LOW_FILTER = 10
HAZARDS = {"moisture": "漏水", "smoke": "烟雾", "gas": "燃气泄漏"}
# 离线需要提醒的设备：安防类，离线意味着可能失去保护
SECURITY_TYPES = {DeviceType.LOCK, DeviceType.CAMERA}
MOTION = "检测到移动"
# 同一设备同一消息在冷却时间内只告警一次，避免移动侦测刷屏
COOLDOWN_SECONDS = {MOTION: 300}


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

    if new.type == DeviceType.CAMERA:
        if n.get("last_ring") and n.get("last_ring") != o.get("last_ring"):
            found.append((AlertLevel.WARNING, "有人按门铃"))
        if n.get("motion") and not o.get("motion"):
            found.append((AlertLevel.INFO, MOTION))

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
    """告警记录，保存在 SQLite 中（path 为 ":memory:" 时只在内存中，重启清空）。"""

    def __init__(self, path: str = ":memory:", keep: int = 1000) -> None:
        self._db = sqlite3.connect(path, check_same_thread=False)
        self._db.execute(
            """CREATE TABLE IF NOT EXISTS alerts (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                time TEXT NOT NULL,
                level TEXT NOT NULL,
                device_id TEXT NOT NULL,
                device_name TEXT NOT NULL,
                room TEXT,
                message TEXT NOT NULL
            )"""
        )
        self._db.commit()
        self._keep = keep
        self._last_fired: dict[tuple[str, str], float] = {}

    def add(self, device: Device, level: AlertLevel, message: str) -> Alert | None:
        """记录告警；处于冷却时间内时返回 None。"""
        cooldown = COOLDOWN_SECONDS.get(message)
        key = (device.id, message)
        now = time.monotonic()
        if cooldown is not None and now - self._last_fired.get(key, -cooldown) < cooldown:
            return None
        self._last_fired[key] = now

        at = datetime.now(UTC)
        cur = self._db.execute(
            "INSERT INTO alerts (time, level, device_id, device_name, room, message) VALUES (?, ?, ?, ?, ?, ?)",
            (at.isoformat(), level.value, device.id, device.name, device.room, message),
        )
        alert_id = cur.lastrowid or 0
        self._db.execute("DELETE FROM alerts WHERE id <= ?", (alert_id - self._keep,))
        self._db.commit()
        return Alert(
            id=alert_id,
            time=at,
            level=level,
            device_id=device.id,
            device_name=device.name,
            room=device.room,
            message=message,
        )

    def recent(self, limit: int = 50) -> list[Alert]:
        """最新的在前。"""
        rows = self._db.execute(
            "SELECT id, time, level, device_id, device_name, room, message FROM alerts ORDER BY id DESC LIMIT ?",
            (limit,),
        )
        return [
            Alert(
                id=r[0],
                time=datetime.fromisoformat(r[1]),
                level=AlertLevel(r[2]),
                device_id=r[3],
                device_name=r[4],
                room=r[5],
                message=r[6],
            )
            for r in rows
        ]

    def close(self) -> None:
        self._db.close()
