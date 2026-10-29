import 'package:flutter/material.dart';

/// 设备来源平台，与网关 gateway/models.py 中的 Platform 对应。
enum DevicePlatform {
  xiaomi('小米', Color(0xFFFF6900)),
  huawei('华为', Color(0xFFCF0A2C)),
  tuya('涂鸦', Color(0xFFFF4800)),
  imou('乐橙', Color(0xFF1E88E5)),
  desman('德施曼', Color(0xFF6D4C41)),
  qihoo360('360', Color(0xFF2EAD4B)),
  other('其他', Colors.blueGrey);

  const DevicePlatform(this.label, this.color);

  final String label;
  final Color color;

  static DevicePlatform parse(String? value) =>
      values.firstWhere((p) => p.name == value, orElse: () => other);
}

enum DeviceType {
  light('灯', Icons.lightbulb_outline),
  switchDevice('开关', Icons.power_settings_new),
  climate('空调', Icons.ac_unit),
  cover('窗帘', Icons.curtains_outlined),
  fan('风扇', Icons.mode_fan_off_outlined),
  sensor('传感器', Icons.thermostat),
  binarySensor('传感器', Icons.sensors),
  lock('门锁', Icons.lock_outline),
  camera('摄像头', Icons.videocam_outlined),
  airPurifier('净化器', Icons.air),
  scene('场景', Icons.auto_awesome),
  unknown('设备', Icons.devices_other);

  const DeviceType(this.label, this.icon);

  final String label;
  final IconData icon;

  static const _wireNames = {
    'light': light,
    'switch': switchDevice,
    'climate': climate,
    'cover': cover,
    'fan': fan,
    'sensor': sensor,
    'binary_sensor': binarySensor,
    'lock': lock,
    'camera': camera,
    'air_purifier': airPurifier,
    'scene': scene,
  };

  static DeviceType parse(String? value) => _wireNames[value] ?? unknown;
}

/// 统一命令动作名，与网关 Action 枚举一致。
abstract final class DeviceAction {
  static const turnOn = 'turn_on';
  static const turnOff = 'turn_off';
  static const toggle = 'toggle';
  static const setBrightness = 'set_brightness';
  static const setColorTemp = 'set_color_temp';
  static const setTemperature = 'set_temperature';
  static const setHvacMode = 'set_hvac_mode';
  static const setPosition = 'set_position';
  static const setFanSpeed = 'set_fan_speed';
  static const open = 'open';
  static const close = 'close';
  static const stop = 'stop';
  static const setPresetMode = 'set_preset_mode';
  static const lock = 'lock';

  /// 需要在网关校验 PIN（params 中带 pin）
  static const unlock = 'unlock';
  static const activate = 'activate';
}

class Device {
  const Device({
    required this.id,
    required this.name,
    required this.type,
    required this.platform,
    this.room,
    this.online = true,
    this.state = const {},
    this.capabilities = const {},
  });

  factory Device.fromJson(Map<String, dynamic> json) => Device(
    id: json['id'] as String,
    name: json['name'] as String,
    type: DeviceType.parse(json['type'] as String?),
    platform: DevicePlatform.parse(json['platform'] as String?),
    room: json['room'] as String?,
    online: json['online'] as bool? ?? true,
    state: Map<String, dynamic>.from(json['state'] as Map? ?? const {}),
    capabilities: {for (final c in json['capabilities'] as List? ?? const []) c as String},
  );

  final String id;
  final String name;
  final DeviceType type;
  final DevicePlatform platform;
  final String? room;
  final bool online;
  final Map<String, dynamic> state;
  final Set<String> capabilities;

  bool can(String action) => capabilities.contains(action);

  /// 是否能在卡片上直接用开关控制
  bool get hasPowerSwitch =>
      can(DeviceAction.toggle) || (can(DeviceAction.turnOn) && can(DeviceAction.turnOff));

  bool get isOn => switch (type) {
    DeviceType.climate => (state['hvac_mode'] ?? 'off') != 'off',
    DeviceType.cover => (_num('position') ?? 0) > 0,
    // 门锁「开」表示未上锁，卡片据此高亮提醒
    DeviceType.lock => !isLocked,
    DeviceType.camera => cameraState == 'streaming' || cameraState == 'recording',
    _ => state['on'] == true,
  };

  int? get brightness => _num('brightness')?.round();
  int? get colorTempKelvin => _num('color_temp_kelvin')?.round();
  double? get currentTemperature => _num('current_temperature')?.toDouble();
  double? get targetTemperature => _num('target_temperature')?.toDouble();
  String? get hvacMode => state['hvac_mode'] as String?;
  List<String> get hvacModes => [for (final m in state['hvac_modes'] as List? ?? const []) m as String];
  int? get position => _num('position')?.round();
  int? get fanPercentage => _num('percentage')?.round();
  String? get presetMode => state['preset_mode'] as String?;
  List<String> get presetModes => [for (final m in state['preset_modes'] as List? ?? const []) m as String];
  double? get pm25 => _num('pm25')?.toDouble();
  int? get filterLife => _num('filter_life')?.round();
  int? get battery => _num('battery')?.round();
  String? get lockState => state['lock_state'] as String?;
  bool get isLocked => lockState == 'locked';
  String? get cameraState => state['camera_state'] as String?;
  bool get streamSupported => state['stream_supported'] == true;

  /// 卡片上显示的一句话状态
  String get summary {
    if (!online) return '离线';
    switch (type) {
      case DeviceType.light:
        if (!isOn) return '已关闭';
        return brightness != null ? '亮度 $brightness%' : '已开启';
      case DeviceType.climate:
        final mode = hvacModeLabel(hvacMode);
        final target = targetTemperature;
        return isOn && target != null ? '$mode · ${target.toStringAsFixed(0)}°C' : mode;
      case DeviceType.cover:
        final p = position;
        return p == null ? '' : (p == 0 ? '已关闭' : '开合 $p%');
      case DeviceType.fan:
        return isOn ? '风速 ${fanPercentage ?? 0}%' : '已关闭';
      case DeviceType.airPurifier:
        final parts = [
          if (pm25 != null) 'PM2.5 ${pm25!.round()}',
          isOn ? (presetMode != null ? presetModeLabel(presetMode) : '运行中') : '已关闭',
        ];
        return parts.join(' · ');
      case DeviceType.lock:
        final label = lockStateLabel(lockState);
        return battery != null ? '$label · 电量 $battery%' : label;
      case DeviceType.camera:
        return switch (cameraState) {
          'streaming' => '直播中',
          'recording' => '录像中',
          _ => '在线',
        };
      case DeviceType.sensor:
        final value = state['value'];
        final display = value is num ? value.toStringAsFixed(1) : '${value ?? '--'}';
        return '$display${state['unit'] ?? ''}';
      case DeviceType.binarySensor:
        return binarySensorLabel(state['device_class'] as String?, isOn);
      case DeviceType.scene:
        return '';
      case DeviceType.switchDevice:
      case DeviceType.unknown:
        return isOn ? '已开启' : '已关闭';
    }
  }

  num? _num(String key) {
    final v = state[key];
    return v is num ? v : null;
  }
}

String hvacModeLabel(String? mode) => switch (mode) {
  'off' => '关闭',
  'cool' => '制冷',
  'heat' => '制热',
  'auto' => '自动',
  'dry' => '除湿',
  'fan_only' => '送风',
  'heat_cool' => '冷暖',
  _ => mode ?? '--',
};

String binarySensorLabel(String? deviceClass, bool on) => switch (deviceClass) {
  'door' || 'window' || 'opening' => on ? '已打开' : '已关闭',
  'motion' || 'occupancy' => on ? '有人' : '无人',
  'moisture' => on ? '漏水' : '正常',
  'smoke' || 'gas' => on ? '报警' : '正常',
  _ => on ? '触发' : '正常',
};

String lockStateLabel(String? state) => switch (state) {
  'locked' => '已上锁',
  'unlocked' => '未上锁',
  'locking' => '正在上锁',
  'unlocking' => '正在开锁',
  'jammed' => '锁舌卡住',
  'open' || 'opening' => '门已打开',
  _ => '状态未知',
};

/// 净化器 / 风扇模式名由设备决定，这里只翻译常见的
String presetModeLabel(String? mode) => switch (mode?.toLowerCase()) {
  'auto' => '自动',
  'sleep' => '睡眠',
  'silent' || 'quiet' => '静音',
  'strong' || 'turbo' || 'high' => '强力',
  'medium' || 'mid' => '中档',
  'low' => '低档',
  'manual' || 'favorite' => '手动',
  _ => mode ?? '--',
};
