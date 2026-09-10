import 'package:flutter/foundation.dart' show debugPrint, kDebugMode;

/// 统一调试日志（2026-09-10 正式版整理）：
/// release 构建下 **零输出**——`kDebugMode` 是编译期常量，整个调用会被裁剪掉，
/// 既保持 logcat 干净，也不泄露运行时信息。
///
/// 为什么要单独抽一个文件：`material.dart` 并未导出 `kDebugMode`，而
/// `category_store.dart` 又不能直接 import foundation（foundation 的 `Category`
/// 注解类会与本项目的 `Category` 模型撞名）。
void debugLog(String message) {
  if (kDebugMode) debugPrint(message);
}
