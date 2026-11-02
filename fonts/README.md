# 网页版字体

国内访问不了 Flutter 网页版默认使用的 fonts.gstatic.com，所以字体随网页版一起发布（不进 APK）：

- `NotoSansSC-Regular.ttf` / `NotoSansSC-Bold.ttf`：思源黑体（Noto Sans SC）的子集，只含 GB2312 常用汉字、ASCII 和常用符号，由 `tools/subset_cjk_font.py` 生成。SIL Open Font License 1.1，见 `OFL.txt`。
- `fallback/roboto/`：Flutter 引擎启动时加载的默认 Roboto 字体（SIL Open Font License 1.1）。升级 Flutter 后如果浏览器控制台出现 `fonts/fallback/...` 的 404，按控制台里的路径从 fonts.gstatic.com 下载对应文件放到这里。

字体由 `lib/web_fonts.dart` 在启动时加载，`web/flutter_bootstrap.js` 把 CanvasKit 和回退字体都指向本站。
