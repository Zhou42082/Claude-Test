import pytest

from gateway.alerts import AlertLog, detect_alerts
from gateway.models import AlertLevel, Device, DeviceType, Platform


def device(type_, online=True, **state):
    return Device(id="x:1", name="设备", type=type_, platform=Platform.OTHER, online=online, state=state)


def test_first_sight_never_alerts():
    assert detect_alerts(None, device(DeviceType.BINARY_SENSOR, on=True, device_class="smoke")) == []


@pytest.mark.parametrize(
    ("device_class", "text"), [("moisture", "漏水"), ("smoke", "烟雾"), ("gas", "燃气泄漏")]
)
def test_hazard_sensor_turning_on_is_critical(device_class, text):
    old = device(DeviceType.BINARY_SENSOR, on=False, device_class=device_class)
    new = device(DeviceType.BINARY_SENSOR, on=True, device_class=device_class)
    assert detect_alerts(old, new) == [(AlertLevel.CRITICAL, f"检测到{text}")]
    # 持续报警不重复告警
    assert detect_alerts(new, new) == []


def test_door_sensor_does_not_alert():
    old = device(DeviceType.BINARY_SENSOR, on=False, device_class="door")
    assert detect_alerts(old, device(DeviceType.BINARY_SENSOR, on=True, device_class="door")) == []


def test_lock_transitions():
    locked = device(DeviceType.LOCK, lock_state="locked")
    assert detect_alerts(locked, device(DeviceType.LOCK, lock_state="unlocked")) == [
        (AlertLevel.INFO, "门锁已打开")
    ]
    assert detect_alerts(locked, device(DeviceType.LOCK, lock_state="jammed")) == [
        (AlertLevel.CRITICAL, "门锁卡住，请检查")
    ]
    assert detect_alerts(device(DeviceType.LOCK, lock_state="unlocked"), locked) == []


def test_security_device_offline():
    cam = device(DeviceType.CAMERA)
    assert detect_alerts(cam, device(DeviceType.CAMERA, online=False)) == [(AlertLevel.WARNING, "设备离线")]
    # 普通灯离线不告警
    assert detect_alerts(device(DeviceType.LIGHT), device(DeviceType.LIGHT, online=False)) == []


def test_low_battery_and_filter_alert_once_when_crossing():
    assert detect_alerts(device(DeviceType.LOCK, battery=25), device(DeviceType.LOCK, battery=19)) == [
        (AlertLevel.WARNING, "电量低（19%），请更换电池或充电")
    ]
    assert detect_alerts(device(DeviceType.LOCK, battery=19), device(DeviceType.LOCK, battery=18)) == []
    old = device(DeviceType.AIR_PURIFIER, filter_life=12)
    assert detect_alerts(old, device(DeviceType.AIR_PURIFIER, filter_life=9)) == [
        (AlertLevel.WARNING, "滤芯剩余 9%，请及时更换")
    ]


def test_alert_log_keeps_newest_first_and_bounded():
    log = AlertLog(keep=3)
    d = device(DeviceType.LOCK)
    for i in range(5):
        log.add(d, AlertLevel.INFO, f"m{i}")
    assert [a.message for a in log.recent()] == ["m4", "m3", "m2"]
    assert [a.id for a in log.recent(2)] == [5, 4]


def test_doorbell_and_motion():
    idle = device(DeviceType.CAMERA, last_ring=None, motion=False)
    rang = device(DeviceType.CAMERA, last_ring="2026-10-29T10:00:00+00:00", motion=False)
    assert detect_alerts(idle, rang) == [(AlertLevel.WARNING, "有人按门铃")]
    assert detect_alerts(rang, rang) == []
    moving = device(DeviceType.CAMERA, motion=True)
    assert detect_alerts(idle, moving) == [(AlertLevel.INFO, "检测到移动")]


def test_motion_alert_cooldown_per_device():
    log = AlertLog()
    cam, other = (
        device(DeviceType.CAMERA),
        Device(id="x:2", name="后门", type=DeviceType.CAMERA, platform=Platform.OTHER),
    )
    assert log.add(cam, AlertLevel.INFO, "检测到移动") is not None
    assert log.add(cam, AlertLevel.INFO, "检测到移动") is None
    assert log.add(other, AlertLevel.INFO, "检测到移动") is not None
    # 其他消息不受冷却影响
    assert log.add(cam, AlertLevel.WARNING, "有人按门铃") is not None
    assert log.add(cam, AlertLevel.WARNING, "有人按门铃") is not None


def test_alert_log_persists_to_disk(tmp_path):
    path = str(tmp_path / "gateway.db")
    log = AlertLog(path)
    log.add(device(DeviceType.LOCK), AlertLevel.CRITICAL, "门锁卡住，请检查")
    log.close()

    reopened = AlertLog(path)
    [alert] = reopened.recent()
    assert alert.message == "门锁卡住，请检查"
    assert alert.level == AlertLevel.CRITICAL
    assert alert.time.tzinfo is not None
    # 新告警的 ID 接着往后排
    assert reopened.add(device(DeviceType.LOCK), AlertLevel.INFO, "门锁已打开").id == alert.id + 1
