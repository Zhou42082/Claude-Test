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
    log = AlertLog(maxlen=3)
    d = device(DeviceType.LOCK)
    for i in range(5):
        log.add(d, AlertLevel.INFO, f"m{i}")
    assert [a.message for a in log.recent()] == ["m4", "m3", "m2"]
    assert [a.id for a in log.recent(2)] == [5, 4]
