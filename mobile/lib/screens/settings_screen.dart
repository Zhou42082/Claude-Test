import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/gateway_client.dart';
import '../state/device_store.dart';
import '../state/settings_store.dart';

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
    final config = context.read<SettingsStore>().config;
    _url = TextEditingController(text: config.baseUrl);
    _token = TextEditingController(text: config.token);
  }

  @override
  void dispose() {
    _url.dispose();
    _token.dispose();
    super.dispose();
  }

  GatewayConfig get _config => GatewayConfig(baseUrl: _url.text.trim(), token: _token.text.trim());

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
      final list = await client.fetchDevices();
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
    return Scaffold(
      appBar: AppBar(title: Text(widget.firstRun ? '连接家庭网关' : '网关设置')),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            const Text('App 通过家庭网关统一控制小米、华为、涂鸦设备。请填写网关地址和访问令牌（GATEWAY_TOKEN）。'),
            const SizedBox(height: 20),
            TextFormField(
              controller: _url,
              keyboardType: TextInputType.url,
              decoration: const InputDecoration(
                labelText: '网关地址',
                hintText: 'http://192.168.1.10:8000',
                border: OutlineInputBorder(),
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
            const SizedBox(height: 16),
            TextFormField(
              controller: _token,
              obscureText: _obscureToken,
              decoration: InputDecoration(
                labelText: '访问令牌',
                border: const OutlineInputBorder(),
                suffixIcon: IconButton(
                  icon: Icon(_obscureToken ? Icons.visibility : Icons.visibility_off),
                  onPressed: () => setState(() => _obscureToken = !_obscureToken),
                ),
              ),
              validator: (v) => (v?.trim().isEmpty ?? true) ? '请输入访问令牌' : null,
            ),
            const SizedBox(height: 24),
            FilledButton(
              onPressed: _testing ? null : _testAndSave,
              child: _testing
                  ? const SizedBox.square(dimension: 20, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Text('测试并保存'),
            ),
          ],
        ),
      ),
    );
  }
}
