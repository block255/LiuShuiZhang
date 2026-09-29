import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'notify_account_map.dart';

/// 一条「未识别通知」记录（疑似收付款但没被自动记账）。
///
/// 两个来源（[source]）：
/// - `native`：被原生标题闸门拦下（标题不含支付关键词）
/// - `parser`：放行后解析器认不出（方向不明 / 无锚定金额 / 无效通知）
///
/// 用途：App 内「未识别通知」页查看 + 一键复制导出（自己留档核对，或反馈问题时附上）。
class NotifyLogEntry {
  final DateTime time;

  /// `native` / `parser`
  final String source;
  final String pkg; // 来源包名（可能为空）
  final String accountId; // 归属账户 id（可能为空）
  final String title;
  final String text;
  final String reason; // 人话原因
  final String channel; // 通知渠道（安卓才有）

  const NotifyLogEntry({
    required this.time,
    required this.reason,
    this.source = 'parser',
    this.pkg = '',
    this.accountId = '',
    this.title = '',
    this.text = '',
    this.channel = '',
  });

  /// 展示用来源名（微信 / 支付宝 / 其它）
  String get platformName {
    final byPkg = pkg.isEmpty ? null : NotifyAccountMap.accountForPackage(pkg);
    final id = accountId.isNotEmpty ? accountId : byPkg;
    return switch (id) {
      'acc_wechat' => '微信',
      'acc_alipay' => '支付宝',
      _ => '未知来源',
    };
  }

  /// 展示用来源标签（原生拦下 / 解析未识别）
  String get sourceName => source == 'native' ? '未放行' : '未解析';

  Map<String, dynamic> toJson() => {
        'time': time.millisecondsSinceEpoch,
        'source': source,
        if (pkg.isNotEmpty) 'pkg': pkg,
        if (accountId.isNotEmpty) 'accountId': accountId,
        'title': title,
        'text': text,
        'reason': reason,
        if (channel.isNotEmpty) 'channel': channel,
      };

  static NotifyLogEntry? fromJson(Map<String, dynamic> j) {
    final ms = (j['time'] as num?)?.toInt();
    if (ms == null) return null;
    final pkg = (j['pkg'] as String?) ?? '';
    return NotifyLogEntry(
      time: DateTime.fromMillisecondsSinceEpoch(ms),
      source: (j['source'] as String?) ?? 'native',
      pkg: pkg,
      accountId: (j['accountId'] as String?) ??
          NotifyAccountMap.accountForPackage(pkg) ??
          '',
      title: (j['title'] as String?) ?? '',
      text: (j['text'] as String?) ?? '',
      reason: (j['reason'] as String?) ?? '',
      channel: (j['channel'] as String?) ?? '',
    );
  }

  /// 复制用的单行文本（便于留档 / 反馈问题时定位）
  String toReportLine() {
    final t = '${time.month.toString().padLeft(2, '0')}-'
        '${time.day.toString().padLeft(2, '0')} '
        '${time.hour.toString().padLeft(2, '0')}:'
        '${time.minute.toString().padLeft(2, '0')}';
    final body = [title, text].where((s) => s.trim().isNotEmpty).join(' ｜ ');
    return '$t [$platformName·$sourceName] $body —— $reason';
  }
}

/// 「未识别通知」留痕（方案 C，2026-09-29）。
///
/// 持久化在原生侧（应用私有目录 `unparsed_log.json`，环形 100 条）：
/// 原生拦下的通知由 [NotifyListenerService]/UnparsedLog 写入，Dart 侧解析失败的通知
/// 经 `lsz_notify/appendUnparsedLog` 追加 —— **单一写入者**（原生 @Synchronized），
/// 避免两端读改写互相覆盖。
///
/// Web / 桌面（无该通道）：退化为纯内存日志（与旧行为一致），不影响开发调试。
class NotifyLogStore extends ChangeNotifier {
  NotifyLogStore._();

  static final NotifyLogStore instance = NotifyLogStore._();

  static const MethodChannel _channel = MethodChannel('lsz_notify');

  /// 环形上限（与原生 UnparsedLog.MAX 保持一致）
  static const int maxEntries = 100;

  final List<NotifyLogEntry> _entries = [];

  /// 原生留痕是否可用（安卓真机 load 成功后为 true）
  bool _persistent = false;
  bool _loading = false;

  bool get persistent => _persistent;

  /// 最新的在前
  List<NotifyLogEntry> get entries => List.unmodifiable(_entries);

  int get count => _entries.length;

  /// 从原生文件刷新（App 启动、进入设置页时调用）。
  /// 非安卓/通道不可用 → 静默保留内存态，不抛异常。
  Future<void> load() async {
    if (_loading) return;
    _loading = true;
    try {
      final raw = await _channel.invokeMethod<String>('readUnparsedLog');
      if (raw == null) return; // 非安卓：保持内存
      final list = jsonDecode(raw) as List<dynamic>;
      _persistent = true;
      final loaded = <NotifyLogEntry>[];
      for (final e in list) {
        if (e is! Map<String, dynamic>) continue;
        final entry = NotifyLogEntry.fromJson(e);
        if (entry != null) loaded.add(entry);
      }
      // 文件为追加序（旧→新）→ 展示倒序（新→旧），并裁到环形上限
      loaded.sort((a, b) => b.time.compareTo(a.time));
      _entries
        ..clear()
        ..addAll(loaded.take(maxEntries));
      notifyListeners();
    } catch (_) {
      // 通道缺失（Web/桌面）或文件异常：仅内存日志，不影响主流程
    } finally {
      _loading = false;
    }
  }

  /// 追加一条（内存立即生效；原生落盘异步，失败不影响 UI）
  void add(NotifyLogEntry entry) {
    _entries.insert(0, entry);
    while (_entries.length > maxEntries) {
      _entries.removeLast();
    }
    notifyListeners();
    unawaited(_appendNative(entry));
  }

  Future<void> _appendNative(NotifyLogEntry entry) async {
    if (!_persistent) return; // 非安卓不写文件
    try {
      await _channel.invokeMethod('appendUnparsedLog', {
        'entry': jsonEncode(entry.toJson()),
      });
    } catch (_) {
      // 落盘失败（存储满/通道异常）：内存里仍有，不打扰用户
    }
  }

  /// 清空（内存 + 原生文件）。保持同步签名：测试与调用方无需 await。
  void clear() {
    _entries.clear();
    notifyListeners();
    unawaited(_clearNative());
  }

  /// 测试专用：恢复初始状态（内存清空 + 原生留痕标记复位）
  @visibleForTesting
  void resetForTest() {
    _entries.clear();
    _persistent = false;
    _loading = false;
  }

  Future<void> _clearNative() async {
    if (!_persistent) return;
    try {
      await _channel.invokeMethod('clearUnparsedLog');
    } catch (_) {}
  }
}
