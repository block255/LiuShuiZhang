import '../../models/record.dart';

/// 通知监听：输入/输出模型（纯 Dart，Web/Android 共用）

/// 一条待解析的通知消息。
///
/// [accountId] 由上层给出，解析器不猜账户：
/// - Web：模拟通知面板手动选择；
/// - Android：NotificationListenerService 按包名映射（阶段 B）。
class NotifyMessage {
  final String accountId;
  final String title; // 通知标题（可能为空）
  final String text; // 通知正文
  final DateTime arrival; // 通知到达时刻（即交易参考时间）

  const NotifyMessage({
    required this.accountId,
    this.title = '',
    this.text = '',
    required this.arrival,
  });

  /// 判定用全文（标题在前，中间加空格）
  String get combined => title.trim().isEmpty ? text : '$title $text';
}

/// 解析结果分类
enum NotifyParseOutcome {
  ok, // 解析成功，可入库
  ignored, // 无效通知（含失败/取消等词），忽略
  failed, // 无法解析（方向冲突/缺金额/结构不认识），进日志待补规则
}

/// 解析结果
class NotifyParseResult {
  final NotifyParseOutcome outcome;
  final RecordType? type; // ok 时非空
  final int? amountCents; // ok 时非空（分）
  final String? counterpart; // 尽力而为，可能为 null
  final String reason; // ignored/failed 的人话原因

  const NotifyParseResult.ok({
    required this.type,
    required this.amountCents,
    this.counterpart,
  })  : outcome = NotifyParseOutcome.ok,
        reason = '';

  const NotifyParseResult.ignored(String thisReason)
      : outcome = NotifyParseOutcome.ignored,
        type = null,
        amountCents = null,
        counterpart = null,
        reason = thisReason;

  const NotifyParseResult.failed(String thisReason)
      : outcome = NotifyParseOutcome.failed,
        type = null,
        amountCents = null,
        counterpart = null,
        reason = thisReason;
}

/// 投递结果分类（ingest 层）
enum NotifyIngestOutcome {
  pendingAdded, // 已入待确认
  duplicate, // 指纹命中重复，丢弃
  failed, // 无法解析（已记日志）
  ignored, // 无效通知忽略（已记日志）
}

/// ingest 编排结果
class NotifyIngestResult {
  final NotifyIngestOutcome outcome;
  final String detail; // 人话说明（UI 展示用）
  final NotifyParseResult? parse; // 原始解析结果
  final Record? record; // pendingAdded 时的记录

  const NotifyIngestResult({
    required this.outcome,
    required this.detail,
    this.parse,
    this.record,
  });
}
