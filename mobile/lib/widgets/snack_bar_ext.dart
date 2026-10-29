import 'package:flutter/material.dart';

extension ShowLatestSnackBar on ScaffoldMessengerState {
  /// 替换当前提示而不是排队：否则一条 10 秒的紧急告警后面的操作反馈要等很久才出来。
  /// 被替换的告警仍保留在告警列表和未读数里。
  void showLatest(SnackBar snackBar) {
    hideCurrentSnackBar();
    showSnackBar(snackBar);
  }
}
