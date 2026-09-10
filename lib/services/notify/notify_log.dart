import 'package:flutter/foundation.dart';

/// "无法解析/无效通知"原文日志（内存环形，上限 [maxEntries]）。
///
/// 目的：解析器宁缺毋滥，拒绝的通知原文留档，供模拟面板查看，
/// 真机阶段靠它收集漏网文案来精调词表。
/// v1 内存即可（Web 调试会话内可见）；持久化留待阶段 B。
class NotifyLogEntry {
  final DateTime time;
  final String accountId;
  final String title;
  final String text;
  final String reason; // 无法解析：… / 无效词：…

  const NotifyLogEntry({
    required this.time,
    required this.accountId,
    this.title = '',
    this.text = '',
    required this.reason,
  });
}

class NotifyLogStore extends ChangeNotifier {
  NotifyLogStore._();

  static final NotifyLogStore instance = NotifyLogStore._();

  /// 环形上限（新到顶掉最旧）
  static const int maxEntries = 30;

  final List<NotifyLogEntry> _entries = [];

  /// 最新的在前
  List<NotifyLogEntry> get entries => List.unmodifiable(_entries);

  int get count => _entries.length;

  void add(NotifyLogEntry entry) {
    _entries.insert(0, entry);
    while (_entries.length > maxEntries) {
      _entries.removeLast();
    }
    notifyListeners();
  }

  void clear() {
    _entries.clear();
    notifyListeners();
  }
}
