import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/gateway_client.dart';

/// 保存网关地址、令牌和告警已读位置。
///
/// 令牌放在系统安全存储（Android Keystore / iOS Keychain）。网页版没有安全存储，
/// 且非 HTTPS 页面用不了 WebCrypto，所以网页版退回到浏览器本地存储。
class SettingsStore extends ChangeNotifier {
  SettingsStore({FlutterSecureStorage? secureStorage})
    : _secure = secureStorage ?? const FlutterSecureStorage();

  static const _urlKey = 'gateway_url';
  static const _tokenKey = 'gateway_token';
  static const _alertsSeenKey = 'alerts_seen_until';

  final FlutterSecureStorage _secure;

  GatewayConfig _config = const GatewayConfig(baseUrl: '', token: '');
  GatewayConfig get config => _config;

  DateTime? _alertsSeenUntil;
  DateTime? get alertsSeenUntil => _alertsSeenUntil;

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    var token = await _readToken(prefs);
    // 旧版本把令牌存在 SharedPreferences 里，迁移到安全存储
    final legacy = prefs.getString(_tokenKey);
    if (!kIsWeb && legacy != null) {
      if (token.isEmpty) {
        await _secure.write(key: _tokenKey, value: legacy);
        token = legacy;
      }
      await prefs.remove(_tokenKey);
    }
    _config = GatewayConfig(baseUrl: prefs.getString(_urlKey) ?? '', token: token);
    final seen = prefs.getString(_alertsSeenKey);
    _alertsSeenUntil = seen == null ? null : DateTime.tryParse(seen);
    notifyListeners();
  }

  Future<void> save(GatewayConfig config) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_urlKey, config.baseUrl);
    if (kIsWeb) {
      await prefs.setString(_tokenKey, config.token);
    } else {
      await _secure.write(key: _tokenKey, value: config.token);
    }
    _config = config;
    notifyListeners();
  }

  /// 不触发重建：只是持久化，界面上的未读数由 DeviceStore 负责
  Future<void> saveAlertsSeen(DateTime until) async {
    _alertsSeenUntil = until;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_alertsSeenKey, until.toUtc().toIso8601String());
  }

  Future<String> _readToken(SharedPreferences prefs) async {
    if (kIsWeb) return prefs.getString(_tokenKey) ?? '';
    return await _secure.read(key: _tokenKey) ?? '';
  }
}
