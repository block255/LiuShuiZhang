import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';

import 'notify_account_map.dart';
import 'notify_ingest.dart';
import 'notify_models.dart';

Future<Directory> _defaultDir() async {
  const channel = MethodChannel('lsz_storage');
  final path = await channel.invokeMethod<String>('getFilesDir');
  if (path == null || path.isEmpty) {
    throw StateError('lsz_storage/getFilesDir 返回空路径');
  }
  return Directory(path);
}

/// 原生通知暂存队列补拉器（Android）。
///
/// 目录默认经 MethodChannel 获取，测试可注入临时目录。
class NotifyQueueDrainer {
  NotifyQueueDrainer({Future<Directory> Function()? dirProvider})
      : _dirProvider = dirProvider ?? _defaultDir;

  final Future<Directory> Function() _dirProvider;

  static const String fileName = 'notify_queue.json';

  /// 队列条目结构（与原生 NotifyListenerService 写入一致）：
  /// {"pkg": 包名, "title": 标题, "text": 正文, "time": 到达时间 epochMs}
  Future<({int added, int processed})> drain() async {
    final dir = await _dirProvider();
    final f = File('${dir.path}/$fileName');
    if (!await f.exists()) return (added: 0, processed: 0);

    final List<dynamic> items;
    try {
      items = jsonDecode(await f.readAsString()) as List<dynamic>;
    } catch (_) {
      // 损坏队列：丢弃文件，不让它阻塞后续通知
      await f.delete();
      return (added: 0, processed: 0);
    }

    var added = 0;
    for (final e in items) {
      if (e is! Map<String, dynamic>) continue;
      final pkg = e['pkg'] as String?;
      final accountId = pkg == null ? null : NotifyAccountMap.accountForPackage(pkg);
      if (accountId == null) continue; // 未知包名：防御跳过
      final title = (e['title'] as String?) ?? '';
      final text = (e['text'] as String?) ?? '';
      final timeMs = (e['time'] as num?)?.toInt();
      final arrival = timeMs == null
          ? DateTime.now()
          : DateTime.fromMillisecondsSinceEpoch(timeMs);
      final result = NotifyIngest.ingest(NotifyMessage(
        accountId: accountId,
        title: title,
        text: text,
        arrival: arrival,
      ));
      if (result.outcome == NotifyIngestOutcome.pendingAdded) added++;
      // failed/ignored 已进"无法解析日志"，duplicate 已存在 → 均消费
    }

    await f.delete(); // 队列一次性消费（防重复依赖指纹去重兜底）
    return (added: added, processed: items.length);
  }
}

/// 顶层入口（默认目录提供者）
Future<int> drainNotifyQueue() async {
  final r = await NotifyQueueDrainer().drain();
  return r.added;
}
