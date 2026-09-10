import 'package:flutter/services.dart';

/// `lsz_notify` 原生通道封装（Android 通知监听辅助）。
/// 非 Android 平台调用会抛 MissingPluginException，调用方自行兜底。
class NotifyPlatform {
  NotifyPlatform._();

  static const MethodChannel _channel = MethodChannel('lsz_notify');

  /// 发一条本 App 的系统通知（走 系统→监听服务→队列 完整链路，debug 自测用）
  /// 返回 'posted' / 'permission_requested'
  static Future<String> postTestNotification({
    required String title,
    required String text,
    required String targetPkg,
  }) async {
    return await _channel.invokeMethod<String>('postTestNotification', {
      'title': title,
      'text': text,
      'targetPkg': targetPkg,
    }) ??
        '';
  }

  /// 跳系统"通知使用权"设置页
  static Future<void> openListenerSettings() =>
      _channel.invokeMethod('openListenerSettings');

  /// 跳本应用通知权限设置页
  static Future<void> openAppNotificationSettings() =>
      _channel.invokeMethod('openAppNotificationSettings');

  /// 自愈：禁用再启用监听服务组件 → 触发系统重新绑定
  static Future<void> selfHeal() =>
      _channel.invokeMethod('selfHealListener');

  /// 主开关：设置"通知自动记账"是否启用（原生监听服务检查此标志，关闭即不采集）
  static Future<void> setListenerEnabled(bool enabled) =>
      _channel.invokeMethod('setListenerEnabled', {'enabled': enabled});

  /// 读取主开关当前状态
  static Future<bool> getListenerEnabled() async {
    final v = await _channel.invokeMethod<bool>('getListenerEnabled');
    return v ?? true;
  }

  /// 监听健康检测：原生发 probe 通知并回读队列确认监听是否活着。
  /// 返回状态：'ok' 正常 / 'dead' 失联（可修复）/ 'no_access' 未授权「通知使用权」
  /// / 'no_permission' 未授予本应用通知权限（自检需要发一条通知）/ '' 非安卓或失败
  static Future<String> checkListenerHealth() async {
    final v = await _channel.invokeMethod<String>('checkListenerHealth');
    return v ?? '';
  }

  /// 方案 B：设置前台保活开关（启停保活服务）
  static Future<void> setKeepAlive(bool enabled) =>
      _channel.invokeMethod('setKeepAlive', {'enabled': enabled});

  /// 读取前台保活开关状态
  static Future<bool> getKeepAlive() async {
    final v = await _channel.invokeMethod<bool>('getKeepAlive');
    return v ?? false;
  }

  /// App 启动时调用：保活开关开着则拉起保活服务
  static Future<void> startKeepAliveIfEnabled() async {
    try {
      await _channel.invokeMethod('startKeepAliveIfEnabled');
    } catch (_) {
      // 非安卓忽略
    }
  }
}
