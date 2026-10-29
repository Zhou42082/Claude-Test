import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;

/// 网页版使用的中文字体。字体文件放在 web/fonts/ 下，只进网页版构建，不进 APK。
const webFontFamily = 'NotoSansSC';

/// 网页版启动时加载中文字体。
///
/// Flutter 网页版遇到中文默认去 fonts.gstatic.com 下载字体，国内访问不了，界面会变成方块。
/// 加载失败时返回 false，界面退回默认字体。
Future<bool> loadWebFonts() async {
  if (!kIsWeb) return false;
  try {
    final loader = FontLoader(webFontFamily);
    for (final style in ['Regular', 'Bold']) {
      final resp = await http.get(Uri.base.resolve('fonts/NotoSansSC-$style.ttf'));
      if (resp.statusCode != 200) return false;
      loader.addFont(Future.value(ByteData.sublistView(resp.bodyBytes)));
    }
    await loader.load();
    return true;
  } catch (_) {
    return false;
  }
}
