import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/alert.dart';
import '../models/device.dart';
import '../state/device_store.dart';
import '../theme/app_theme.dart';
import 'air_quality_view.dart';
import 'camera_snapshot_view.dart';
import 'lock_controls.dart';
import 'platform_badge.dart';

typedef _Send = void Function(String action, [Map<String, Object?> params]);

/// 设备详情 / 控制面板。根据设备的 capabilities 动态展示控件，配色跟随设备类型。
class DeviceControlSheet extends StatelessWidget {
  const DeviceControlSheet({super.key, required this.deviceId});

  final String deviceId;

  static Future<void> show(BuildContext context, String deviceId) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (_) => DeviceControlSheet(deviceId: deviceId),
    );
  }

  @override
  Widget build(BuildContext context) {
    final device = context.select<DeviceStore, Device?>((s) => s.device(deviceId));
    if (device == null) {
      return const SizedBox(height: 160, child: Center(child: Text('设备已被移除')));
    }
    final store = context.read<DeviceStore>();
    final enabled = device.online;

    void send(String action, [Map<String, Object?> params = const {}]) => store.send(device, action, params);

    return Theme(
      data: AppTheme.forDevice(Theme.of(context), device.type),
      child: Builder(
        builder: (context) {
          final theme = Theme.of(context);
          return ConstrainedBox(
            constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.88),
            child: SafeArea(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _Header(device: device),
                    const SizedBox(height: 16),
                    if (device.type == DeviceType.sensor || device.type == DeviceType.binarySensor)
                      SectionCard(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 20),
                          child: Center(
                            child: Text(
                              device.summary,
                              style: theme.textTheme.displaySmall?.copyWith(
                                color: device.isAlarm ? theme.colorScheme.error : null,
                                fontWeight: FontWeight.w400,
                              ),
                            ),
                          ),
                        ),
                      ),
                    if (device.type == DeviceType.lock) SectionCard(child: LockControls(device: device)),
                    if (device.type == DeviceType.camera)
                      SectionCard(child: CameraSnapshotView(device: device)),
                    if (device.type == DeviceType.airPurifier)
                      SectionCard(child: AirQualityView(device: device)),
                    if (device.hasPowerSwitch) _PowerCard(device: device, enabled: enabled),
                    if (device.can(DeviceAction.setBrightness))
                      _SliderControl(
                        label: '亮度',
                        unit: '%',
                        value: (device.brightness ?? 0).toDouble(),
                        min: 1,
                        max: 100,
                        enabled: enabled,
                        onCommit: (v) => send(DeviceAction.setBrightness, {'brightness': v.round()}),
                      ),
                    if (device.can(DeviceAction.setColorTemp))
                      _SliderControl(
                        label: '色温',
                        unit: 'K',
                        value: (device.colorTempKelvin ?? 4000).toDouble(),
                        min: (device.state['min_color_temp_kelvin'] as num? ?? 2700).toDouble(),
                        max: (device.state['max_color_temp_kelvin'] as num? ?? 6500).toDouble(),
                        enabled: enabled,
                        onCommit: (v) => send(DeviceAction.setColorTemp, {'color_temp_kelvin': v.round()}),
                      ),
                    if (device.type == DeviceType.climate) ..._climateControls(context, device, send),
                    if (device.can(DeviceAction.setFanSpeed))
                      _SliderControl(
                        label: '风速',
                        unit: '%',
                        value: (device.fanPercentage ?? 0).toDouble(),
                        min: 0,
                        max: 100,
                        enabled: enabled,
                        onCommit: (v) => send(DeviceAction.setFanSpeed, {'percentage': v.round()}),
                      ),
                    if (device.can(DeviceAction.setPresetMode))
                      SectionCard(
                        title: '模式',
                        child: _Choices(
                          options: device.presetModes,
                          selected: device.presetMode,
                          label: presetModeLabel,
                          onSelected: enabled
                              ? (mode) => send(DeviceAction.setPresetMode, {'preset_mode': mode})
                              : null,
                        ),
                      ),
                    if (device.type == DeviceType.cover) ..._coverControls(device, send),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  List<Widget> _climateControls(BuildContext context, Device device, _Send send) {
    final theme = Theme.of(context);
    final target = device.targetTemperature;
    final enabled = device.online && device.isOn;
    return [
      if (device.can(DeviceAction.setTemperature) && target != null)
        SectionCard(
          title: '目标温度',
          trailing: device.currentTemperature == null
              ? null
              : Text('室内 ${device.currentTemperature!.toStringAsFixed(1)}°C'),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              IconButton.filledTonal(
                iconSize: 28,
                icon: const Icon(Icons.remove_rounded),
                onPressed: enabled && target > 16
                    ? () => send(DeviceAction.setTemperature, {'temperature': target - 1})
                    : null,
              ),
              SizedBox(
                width: 150,
                child: Text(
                  '${target.toStringAsFixed(0)}°C',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.displayMedium?.copyWith(
                    fontWeight: FontWeight.w300,
                    color: enabled ? theme.colorScheme.primary : theme.disabledColor,
                  ),
                ),
              ),
              IconButton.filledTonal(
                iconSize: 28,
                icon: const Icon(Icons.add_rounded),
                onPressed: enabled && target < 30
                    ? () => send(DeviceAction.setTemperature, {'temperature': target + 1})
                    : null,
              ),
            ],
          ),
        ),
      if (device.can(DeviceAction.setHvacMode))
        SectionCard(
          title: '模式',
          child: _Choices(
            options: device.hvacModes,
            selected: device.hvacMode,
            label: hvacModeLabel,
            onSelected: device.online ? (mode) => send(DeviceAction.setHvacMode, {'hvac_mode': mode}) : null,
          ),
        ),
    ];
  }

  List<Widget> _coverControls(Device device, _Send send) {
    final enabled = device.online;
    return [
      if (device.can(DeviceAction.setPosition))
        _SliderControl(
          label: '开合度',
          unit: '%',
          value: (device.position ?? 0).toDouble(),
          min: 0,
          max: 100,
          enabled: enabled,
          onCommit: (v) => send(DeviceAction.setPosition, {'position': v.round()}),
        ),
      SectionCard(
        child: Row(
          children: [
            Expanded(
              child: FilledButton.tonalIcon(
                onPressed: enabled ? () => send(DeviceAction.open) : null,
                icon: const Icon(Icons.unfold_more_rounded),
                label: const Text('打开'),
              ),
            ),
            if (device.can(DeviceAction.stop)) ...[
              const SizedBox(width: 8),
              Expanded(
                child: FilledButton.tonalIcon(
                  onPressed: enabled ? () => send(DeviceAction.stop) : null,
                  icon: const Icon(Icons.pause_rounded),
                  label: const Text('暂停'),
                ),
              ),
            ],
            const SizedBox(width: 8),
            Expanded(
              child: FilledButton.tonalIcon(
                onPressed: enabled ? () => send(DeviceAction.close) : null,
                icon: const Icon(Icons.unfold_less_rounded),
                label: const Text('关闭'),
              ),
            ),
          ],
        ),
      ),
    ];
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.device});

  final Device device;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final alarm = device.online && device.isAlarm;
    return Row(
      children: [
        IconBubble(
          icon: alarm ? Icons.warning_amber_rounded : device.type.icon,
          color: alarm ? AlertLevel.critical.color(theme.colorScheme) : device.type.accent,
          size: 56,
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(device.name, style: theme.textTheme.titleLarge),
              const SizedBox(height: 4),
              Row(
                children: [
                  PlatformBadge(device.platform),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text(
                      [
                        device.room ?? '未分配房间',
                        device.online ? device.summary : '离线',
                      ].where((s) => s.isNotEmpty).join(' · '),
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// 大号电源开关
class _PowerCard extends StatelessWidget {
  const _PowerCard({required this.device, required this.enabled});

  final Device device;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final on = device.isOn;
    return SectionCard(
      child: Row(
        children: [
          Icon(
            Icons.power_settings_new_rounded,
            color: on ? theme.colorScheme.primary : theme.colorScheme.outline,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('电源', style: theme.textTheme.titleSmall),
                Text(on ? '已开启' : '已关闭', style: theme.textTheme.bodySmall),
              ],
            ),
          ),
          Switch(
            value: on,
            onChanged: enabled ? (v) => context.read<DeviceStore>().setPower(device, v) : null,
          ),
        ],
      ),
    );
  }
}

class _Choices extends StatelessWidget {
  const _Choices({
    required this.options,
    required this.selected,
    required this.label,
    required this.onSelected,
  });

  final List<String> options;
  final String? selected;
  final String Function(String) label;
  final ValueChanged<String>? onSelected;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final option in options)
          ChoiceChip(
            label: Text(label(option)),
            selected: selected == option,
            backgroundColor: scheme.surfaceContainer,
            onSelected: onSelected == null ? null : (_) => onSelected!(option),
          ),
      ],
    );
  }
}

/// 拖动过程中只更新本地值，松手后才下发命令，避免频繁请求。
class _SliderControl extends StatefulWidget {
  const _SliderControl({
    required this.label,
    required this.unit,
    required this.value,
    required this.min,
    required this.max,
    required this.enabled,
    required this.onCommit,
  });

  final String label;
  final String unit;
  final double value;
  final double min;
  final double max;
  final bool enabled;
  final ValueChanged<double> onCommit;

  @override
  State<_SliderControl> createState() => _SliderControlState();
}

class _SliderControlState extends State<_SliderControl> {
  double? _dragValue;

  @override
  Widget build(BuildContext context) {
    final value = (_dragValue ?? widget.value).clamp(widget.min, widget.max);
    return SectionCard(
      title: widget.label,
      trailing: Text('${value.round()}${widget.unit}'),
      child: Slider(
        value: value,
        min: widget.min,
        max: widget.max,
        onChanged: widget.enabled ? (v) => setState(() => _dragValue = v) : null,
        onChangeEnd: (v) {
          setState(() => _dragValue = null);
          widget.onCommit(v);
        },
      ),
    );
  }
}
