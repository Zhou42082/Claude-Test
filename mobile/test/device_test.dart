import 'package:flutter_test/flutter_test.dart';
import 'package:smart_home/models/device.dart';

import 'fakes.dart';

void main() {
  test('parses gateway json', () {
    final d = lamp(on: true);
    expect(d.type, DeviceType.light);
    expect(d.platform, DevicePlatform.tuya);
    expect(d.isOn, isTrue);
    expect(d.hasPowerSwitch, isTrue);
    expect(d.summary, '亮度 40%');
  });

  test('unknown enum values fall back safely', () {
    final d = Device.fromJson({'id': 'x:1', 'name': 'n', 'type': 'vacuum', 'platform': 'apple'});
    expect(d.type, DeviceType.unknown);
    expect(d.platform, DevicePlatform.other);
    expect(d.hasPowerSwitch, isFalse);
  });

  test('summaries', () {
    expect(thermometer().summary, '24.6°C');
    expect(lamp(online: false).summary, '离线');

    final ac = Device.fromJson({
      'id': 'ha:climate.ac',
      'name': '空调',
      'type': 'climate',
      'platform': 'huawei',
      'state': {'hvac_mode': 'cool', 'target_temperature': 25},
    });
    expect(ac.isOn, isTrue);
    expect(ac.summary, '制冷 · 25°C');

    final door = Device.fromJson({
      'id': 'ha:binary_sensor.door',
      'name': '门',
      'type': 'binary_sensor',
      'platform': 'tuya',
      'state': {'on': true, 'device_class': 'door'},
    });
    expect(door.summary, '已打开');
  });

  test('lock, purifier and camera', () {
    final lock = frontLock();
    expect(lock.type, DeviceType.lock);
    expect(lock.platform, DevicePlatform.desman);
    expect(lock.isLocked, isTrue);
    expect(lock.isOn, isFalse);
    expect(lock.hasPowerSwitch, isFalse);
    expect(lock.summary, '已上锁 · 电量 76%');
    expect(frontLock(lockState: 'jammed').summary, '锁舌卡住 · 电量 76%');

    final p = purifier();
    expect(p.type, DeviceType.airPurifier);
    expect(p.summary, 'PM2.5 82 · 自动');
    expect(p.presetModes, ['auto', 'sleep']);

    final cam = doorCamera();
    expect(cam.platform, DevicePlatform.imou);
    expect(cam.streamSupported, isTrue);
    expect(cam.summary, '在线');
  });
}
