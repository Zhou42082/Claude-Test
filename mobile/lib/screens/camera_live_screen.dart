import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:video_player/video_player.dart';

import '../models/device.dart';
import '../state/device_store.dart';

/// 摄像头实时画面：网关返回 HLS 地址，由系统播放器（ExoPlayer / AVPlayer）播放。
class CameraLiveScreen extends StatefulWidget {
  const CameraLiveScreen({super.key, required this.device});

  final Device device;

  @override
  State<CameraLiveScreen> createState() => _CameraLiveScreenState();
}

class _CameraLiveScreenState extends State<CameraLiveScreen> {
  VideoPlayerController? _controller;
  String? _error;

  @override
  void initState() {
    super.initState();
    _start();
  }

  Future<void> _start() async {
    final store = context.read<DeviceStore>();
    setState(() => _error = null);
    try {
      final uri = await store.streamUri(widget.device.id);
      final controller = VideoPlayerController.networkUrl(uri);
      await controller.initialize();
      await controller.play();
      if (!mounted) {
        await controller.dispose();
        return;
      }
      setState(() => _controller = controller);
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    final Widget body;
    if (_error != null) {
      body = Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('无法播放：$_error', style: const TextStyle(color: Colors.white70)),
          TextButton(onPressed: _start, child: const Text('重试')),
        ],
      );
    } else if (controller == null) {
      body = const CircularProgressIndicator();
    } else {
      body = AspectRatio(aspectRatio: controller.value.aspectRatio, child: VideoPlayer(controller));
    }
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: Text(widget.device.name),
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
      ),
      body: Center(child: body),
    );
  }
}
