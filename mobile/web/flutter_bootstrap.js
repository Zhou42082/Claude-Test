{{flutter_js}}
{{flutter_build_config}}

// 渲染引擎 CanvasKit 从本站加载，而不是默认的 www.gstatic.com（国内无法访问）。
// 回退字体也指向本站：中文字体由 App 自己加载（lib/web_fonts.dart），不需要 fonts.gstatic.com。
_flutter.loader.load({
  config: {
    canvasKitBaseUrl: "canvaskit/",
    fontFallbackBaseUrl: "fonts/fallback/",
  },
});
