import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/gateway_client.dart';

/// 保存网关地址与令牌。
///
/// TODO: 正式版改用 flutter_secure_storage 保存令牌（Keychain / Keystore）。
class SettingsStore extends ChangeNotifier {
  static const _urlKey = 'gateway_url';
  static const _tokenKey = 'gateway_token';

  GatewayConfig _config = const GatewayConfig(baseUrl: '', token: '');
  GatewayConfig get config => _config;

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    _config = GatewayConfig(baseUrl: prefs.getString(_urlKey) ?? '', token: prefs.getString(_tokenKey) ?? '');
    notifyListeners();
  }

  Future<void> save(GatewayConfig config) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_urlKey, config.baseUrl);
    await prefs.setString(_tokenKey, config.token);
    _config = config;
    notifyListeners();
  }
}
