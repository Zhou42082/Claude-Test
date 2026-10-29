import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/alert.dart';
import '../models/device.dart';
import '../screens/camera_live_screen.dart';
import '../state/device_store.dart';

/// 摄像头当前画面。截图经网关转发，App 不直接连接摄像头或厂商云。
class CameraSnapshotView extends StatefulWidget {
  const CameraSnapshotView({super.key, required this.device});

  final Device device;

  @override
  State<CameraSnapshotView> createState() => _CameraSnapshotViewState();
}

/// 云台转动后等待多久再刷新截图。乐橙集成默认每次转动约 1 秒。
const ptzSettleDelay = Duration(milliseconds: 1200);

class _CameraSnapshotViewState extends State<CameraSnapshotView> {
  late Future<Uint8List> _snapshot;

  @override
  void initState() {
    super.initState();
    _snapshot = _load();
  }

  Future<Uint8List> _load() => context.read<DeviceStore>().snapshot(widget.device.id);

  void _refresh() {
    // 赋值表达式的值是 Future，setState 回调必须写成代码块
    setState(() {
      _snapshot = _load();
    });
  }

  /// 云台转动一步，等摄像头转完再刷新画面
  Future<void> _ptz(String direction) async {
    final ok = await context.read<DeviceStore>().send(widget.device, DeviceAction.ptz, {
      'direction': direction,
    });
    if (!ok) return;
    await Future<void>.delayed(ptzSettleDelay);
    if (mounted) _refresh();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: AspectRatio(
            aspectRatio: 16 / 9,
            child: ColoredBox(
              color: Colors.black,
              child: FutureBuilder<Uint8List>(
                future: _snapshot,
                builder: (context, snap) {
                  if (snap.hasError) {
                    return Center(
                      child: Text('画面加载失败：${snap.error}', style: const TextStyle(color: Colors.white70)),
                    );
                  }
                  if (!snap.hasData) return const Center(child: CircularProgressIndicator());
                  return Image.memory(snap.data!, fit: BoxFit.cover, gaplessPlayback: true);
                },
              ),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            TextButton.icon(onPressed: _refresh, icon: const Icon(Icons.refresh), label: const Text('刷新画面')),
            const Spacer(),
            if (widget.device.streamSupported)
              FilledButton.icon(
                onPressed: widget.device.online
                    ? () => Navigator.of(
                        context,
                      ).push(MaterialPageRoute(builder: (_) => CameraLiveScreen(device: widget.device)))
                    : null,
                icon: const Icon(Icons.play_arrow),
                label: const Text('实时画面'),
              )
            else
              Text('该摄像头不支持实时视频', style: theme.textTheme.bodySmall),
          ],
        ),
        _CameraStatus(device: widget.device),
        if (widget.device.can(DeviceAction.ptz)) ...[
          const SizedBox(height: 8),
          _PtzPad(directions: widget.device.ptzDirections, enabled: widget.device.online, onMove: _ptz),
        ],
      ],
    );
  }
}

class _CameraStatus extends StatelessWidget {
  const _CameraStatus({required this.device});

  final Device device;

  @override
  Widget build(BuildContext context) {
    final ring = device.lastRing;
    final scheme = Theme.of(context).colorScheme;
    return Wrap(
      spacing: 8,
      children: [
        if (device.motionDetected)
          Chip(
            avatar: Icon(Icons.directions_walk, color: scheme.error, size: 18),
            label: const Text('检测到移动'),
          ),
        if (ring != null)
          Chip(
            avatar: const Icon(Icons.doorbell_outlined, size: 18),
            label: Text('最近门铃 ${formatAlertTime(ring)}'),
          ),
      ],
    );
  }
}

/// 上下左右四个方向键，摄像头不支持的方向不显示
class _PtzPad extends StatelessWidget {
  const _PtzPad({required this.directions, required this.enabled, required this.onMove});

  final List<String> directions;
  final bool enabled;
  final ValueChanged<String> onMove;

  Widget _button(String direction, IconData icon, String tooltip) {
    if (!directions.contains(direction)) return const SizedBox.square(dimension: 48);
    return IconButton.filledTonal(
      tooltip: tooltip,
      icon: Icon(icon),
      onPressed: enabled ? () => onMove(direction) : null,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text('云台', style: Theme.of(context).textTheme.labelMedium),
        _button('up', Icons.keyboard_arrow_up, '向上'),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _button('left', Icons.keyboard_arrow_left, '向左'),
            const SizedBox(width: 48),
            _button('right', Icons.keyboard_arrow_right, '向右'),
          ],
        ),
        _button('down', Icons.keyboard_arrow_down, '向下'),
      ],
    );
  }
}
