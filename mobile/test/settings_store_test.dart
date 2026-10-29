import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:smart_home/services/gateway_client.dart';
import 'package:smart_home/state/settings_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => FlutterSecureStorage.setMockInitialValues({}));

  test('migrates a plain-text token into secure storage', () async {
    SharedPreferences.setMockInitialValues({'gateway_url': 'http://gw:8000', 'gateway_token': 'old'});
    final store = SettingsStore();
    await store.load();

    expect(store.config.token, 'old');
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('gateway_token'), isNull);
    expect(await const FlutterSecureStorage().read(key: 'gateway_token'), 'old');
  });

  test('saves token to secure storage and remembers read alerts', () async {
    SharedPreferences.setMockInitialValues({});
    final store = SettingsStore();
    await store.load();
    await store.save(const GatewayConfig(baseUrl: 'http://gw:8000', token: 'new'));
    final seen = DateTime.utc(2026, 10, 29, 8);
    await store.saveAlertsSeen(seen);

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('gateway_token'), isNull);

    final reloaded = SettingsStore();
    await reloaded.load();
    expect(reloaded.config.baseUrl, 'http://gw:8000');
    expect(reloaded.config.token, 'new');
    expect(reloaded.alertsSeenUntil, seen);
  });
}
