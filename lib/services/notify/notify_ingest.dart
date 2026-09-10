import '../../data/record_store.dart';
import '../../models/record.dart';
import 'notify_log.dart';
import 'notify_models.dart';
import 'notify_parser.dart';

/// 通知入库编排（Web 模拟面板与 Android 监听层共用的统一入口）：
/// 解析 → 指纹去重 → 转 pending Record 入库；失败/无效原文进日志。
class NotifyIngest {
  NotifyIngest._();

  /// 去重时间窗（分钟）：同账户同方向同金额、到达时间差 ≤ 此值 → 重复
  static const int dupWindowMinutes = 1;

  /// 投递一条通知。不会抛异常；结果见 [NotifyIngestResult]。
  static NotifyIngestResult ingest(NotifyMessage msg) {
    final parse = NotifyParser.parse(msg);

    // 无法解析 / 无效：留档日志，不建档
    if (parse.outcome == NotifyParseOutcome.failed ||
        parse.outcome == NotifyParseOutcome.ignored) {
      NotifyLogStore.instance.add(NotifyLogEntry(
        time: DateTime.now(),
        accountId: msg.accountId,
        title: msg.title,
        text: msg.text,
        reason: parse.reason,
      ));
      return NotifyIngestResult(
        outcome: parse.outcome == NotifyParseOutcome.ignored
            ? NotifyIngestOutcome.ignored
            : NotifyIngestOutcome.failed,
        detail: parse.reason,
        parse: parse,
      );
    }

    // 指纹去重（不限 status：pending/confirmed 都算，防同一条投两遍）
    final t = msg.arrival;
    final win = Duration(minutes: dupWindowMinutes);
    final near = RecordStore.instance.query(RecordQuery(
      accountId: msg.accountId,
      start: t.subtract(win),
      end: t.add(win),
      statusList: RecordStatus.values,
    ));
    final dup = near.records.any((r) =>
        r.type == parse.type && r.amountCents == parse.amountCents);
    if (dup) {
      return const NotifyIngestResult(
        outcome: NotifyIngestOutcome.duplicate,
        detail: '与 ±1 分钟内同账户同金额同方向的记录重复，已跳过',
      );
    }

    // 入库：pending 待确认
    final record = Record(
      id: Record.newId(),
      accountId: msg.accountId,
      source: RecordSource.notify,
      type: parse.type!,
      amountCents: parse.amountCents!,
      time: t,
      counterpart: parse.counterpart,
      // categoryId 刻意留空：通知无语义线索，确认前后由用户补分类
      status: RecordStatus.pending,
    );
    RecordStore.instance.add(record);
    return NotifyIngestResult(
      outcome: NotifyIngestOutcome.pendingAdded,
      detail: '已进入待确认',
      parse: parse,
      record: record,
    );
  }
}
