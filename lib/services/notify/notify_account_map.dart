/// 包名 → 账户 映射（真机通知监听的归属判定）。
///
/// Android 原生侧只做"是否关注"过滤（NotifyListenerService 的 TARGET_PACKAGES，
/// 两处需同步维护）；真正决定记录归属哪个账户在这里 —— 保持纯 Dart 可测。
class NotifyAccountMap {
  NotifyAccountMap._();

  /// 关注的平台包名 → 预置账户 id
  static const Map<String, String> platform = {
    'com.tencent.mm': 'acc_wechat', // 微信
    'com.eg.android.AlipayGphone': 'acc_alipay', // 支付宝（真机 logcat 实证包名）
  };

  static String? accountForPackage(String pkg) => platform[pkg];

  static bool isWatched(String pkg) => platform.containsKey(pkg);
}
