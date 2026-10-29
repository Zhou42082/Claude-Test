import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

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

class _CameraSnapshotViewState extends State<CameraSnapshotView> {
  late Future<Uint8List> _snapshot;

  @override
  void initState() {
    super.initState();
    _snapshot = _load();
  }

  Future<Uint8List> _load() => context.read<DeviceStore>().snapshot(widget.device.id);

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
            TextButton.icon(
              onPressed: () {
                // 赋值表达式的值是 Future，setState 回调必须写成代码块
                setState(() {
                  _snapshot = _load();
                });
              },
              icon: const Icon(Icons.refresh),
              label: const Text('刷新画面'),
            ),
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
      ],
    );
  }
}
