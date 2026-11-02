import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/device.dart';
import '../services/gateway_client.dart';
import '../state/device_store.dart';
import '../state/settings_store.dart';
import '../demo_only.dart';
import '../theme/app_theme.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key, this.firstRun = false});

  /// 首次启动时作为首页展示，保存后由 App 根组件切换到主页
  final bool firstRun;

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _url;
  late final TextEditingController _token;
  bool _testing = false;
  bool _obscureToken = true;

  @override
  void initState() {
    super.initState();
    final saved = context.read<SettingsStore>().config;
    final config = saved.isDemo ? const GatewayConfig(baseUrl: '', token: '') : saved;
    // 网页版通常由网关直接提供，默认填当前页面的地址（只有演示的网页版除外）
    final defaultUrl = kIsWeb && !demoOnlyBuild && config.baseUrl.isEmpty ? Uri.base.origin : config.baseUrl;
    _url = TextEditingController(text: defaultUrl);
    _token = TextEditingController(text: config.token);
  }

  @override
  void dispose() {
    _url.dispose();
    _token.dispose();
    super.dispose();
  }

  GatewayConfig get _config => GatewayConfig(baseUrl: _url.text.trim(), token: _token.text.trim());

  Future<void> _useDemo() async {
    final navigator = Navigator.of(context);
    await context.read<SettingsStore>().save(GatewayConfig.demo);
    if (!mounted) return;
    context.read<DeviceStore>().connect(GatewayConfig.demo);
    if (!widget.firstRun) navigator.pop();
  }

  Future<void> _testAndSave() async {
    if (!_formKey.currentState!.validate()) return;
    final config = _config;
    final settings = context.read<SettingsStore>();
    final devices = context.read<DeviceStore>();
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);

    setState(() => _testing = true);
    final client = GatewayClient(config);
    try {
      final list = (await client.fetchDevices()).where((d) => d.type != DeviceType.scene).toList();
      await settings.save(config);
      devices.connect(config);
      messenger.showSnackBar(SnackBar(content: Text('连接成功，发现 ${list.length} 个设备')));
      if (!widget.firstRun) navigator.pop();
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('连接失败：$e')));
    } finally {
      client.close();
      if (mounted) setState(() => _testing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    final form = Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  const IconBubble(icon: Icons.router_rounded, color: AppTheme.seed, size: 40),
                  const SizedBox(width: 12),
                  Expanded(child: Text('连接家庭网关', style: theme.textTheme.titleMedium)),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                '填写网关地址和访问令牌（GATEWAY_TOKEN），统一控制小米、华为、涂鸦、乐橙、德施曼等设备。',
                style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _url,
                keyboardType: TextInputType.url,
                decoration: const InputDecoration(
                  labelText: '网关地址',
                  hintText: 'http://192.168.1.10:8000',
                  prefixIcon: Icon(Icons.link_rounded),
                ),
                validator: (v) {
                  final uri = Uri.tryParse(v?.trim() ?? '');
                  if (uri == null || !uri.hasScheme || uri.host.isEmpty) {
                    return '请输入完整地址，如 http://192.168.1.10:8000';
                  }
                  if (uri.scheme != 'http' && uri.scheme != 'https') return '仅支持 http / https';
                  return null;
                },
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _token,
                obscureText: _obscureToken,
                decoration: InputDecoration(
                  labelText: '访问令牌',
                  prefixIcon: const Icon(Icons.key_rounded),
                  suffixIcon: IconButton(
                    icon: Icon(_obscureToken ? Icons.visibility_rounded : Icons.visibility_off_rounded),
                    onPressed: () => setState(() => _obscureToken = !_obscureToken),
                  ),
                ),
                validator: (v) => (v?.trim().isEmpty ?? true) ? '请输入访问令牌' : null,
              ),
              const SizedBox(height: 20),
              FilledButton(
                onPressed: _testing ? null : _testAndSave,
                child: _testing
                    ? const SizedBox.square(dimension: 20, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Text('测试并保存'),
              ),
            ],
          ),
        ),
      ),
    );

    final demo = Card(
      color: Color.alphaBlend(DeviceType.scene.accent.withValues(alpha: 0.12), scheme.surface),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                IconBubble(icon: Icons.science_rounded, color: DeviceType.scene.accent, size: 40),
                const SizedBox(width: 12),
                Expanded(child: Text('还没有网关？', style: theme.textTheme.titleMedium)),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              '演示模式在 App 内模拟一个家，包含小米、华为、涂鸦、乐橙、德施曼的设备和场景，可以模拟漏水、门铃等告警。',
              style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
            ),
            const SizedBox(height: 16),
            OutlinedButton.icon(
              onPressed: _testing ? null : _useDemo,
              icon: const Icon(Icons.play_arrow_rounded),
              label: const Text('体验演示模式'),
            ),
          ],
        ),
      ),
    );

    return Scaffold(
      appBar: widget.firstRun ? null : AppBar(title: const Text('网关设置')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
          children: [if (widget.firstRun) const _Welcome(), form, const SizedBox(height: 12), demo],
        ),
      ),
    );
  }
}

class _Welcome extends StatelessWidget {
  const _Welcome();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 32, 4, 24),
      child: Column(
        children: [
          Container(
            width: 88,
            height: 88,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color(0xFF2E7D6B), Color(0xFF5BA88F)],
              ),
              boxShadow: [
                BoxShadow(
                  color: AppTheme.seed.withValues(alpha: 0.3),
                  blurRadius: 24,
                  offset: const Offset(0, 10),
                ),
              ],
            ),
            child: const Icon(Icons.cottage_rounded, size: 44, color: Colors.white),
          ),
          const SizedBox(height: 20),
          Text('欢迎回家', style: theme.textTheme.headlineSmall),
          const SizedBox(height: 6),
          Text(
            '一个 App 管理全屋的智能设备',
            style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}
