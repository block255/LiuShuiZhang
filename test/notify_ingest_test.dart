import 'package:bill_record_app/data/record_store.dart';
import 'package:bill_record_app/models/record.dart';
import 'package:bill_record_app/services/notify/notify_ingest.dart';
import 'package:bill_record_app/services/notify/notify_log.dart';
import 'package:bill_record_app/services/notify/notify_models.dart';
import 'package:bill_record_app/services/notify/notify_samples.dart';
import 'package:bill_record_app/services/storage/record_storage_stub.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late MemoryRecordStorage storage;
  late RecordStore store;

  setUp(() async {
    storage = MemoryRecordStorage();
    store = RecordStore.replaceForTest(storage);
    await store.init();
    NotifyLogStore.instance.clear();
  });

  NotifySample sampleOf(String label) =>
      notifySamples.firstWhere((s) => s.label == label);

  NotifyIngestResult ingest(NotifySample s, DateTime at) =>
      NotifyIngest.ingest(sampleMessage(s, arrival: at));

  group('NotifyIngest 入库', () {
    test('微信支出样本 → pending 入库，字段正确', () {
      final at = DateTime(2026, 9, 7, 20, 30);
      final r = ingest(sampleOf('微信·已支付 ¥3.7（真实）'), at);
      expect(r.outcome, NotifyIngestOutcome.pendingAdded);
      expect(r.record, isNotNull);

      final pendings = store.pending().records;
      expect(pendings, hasLength(1));
      final rec = pendings.single;
      expect(rec.accountId, 'acc_wechat');
      expect(rec.source, RecordSource.notify);
      expect(rec.status, RecordStatus.pending);
      expect(rec.type, RecordType.expense);
      expect(rec.amountCents, 370);
      expect(rec.time, at);
      expect(rec.categoryId, isNull); // 通知不带分类
    });

    test('支付宝收入样本 → income pending', () {
      final r =
          ingest(sampleOf('支付宝·红包收入'), DateTime(2026, 9, 7, 21, 0));
      expect(r.outcome, NotifyIngestOutcome.pendingAdded);
      expect(store.pending().records.single.type, RecordType.income);
    });

    test('提取到对方（张三）', () {
      final r = ingest(sampleOf('微信·向对方付款（带对方）'),
          DateTime(2026, 9, 7, 21, 0));
      expect(r.outcome, NotifyIngestOutcome.pendingAdded);
      expect(r.record!.counterpart, '张三');
    });
  });

  group('NotifyIngest 指纹去重', () {
    final at = DateTime(2026, 9, 7, 20, 0);
    final s = sampleOf('微信·已支付 ¥3.7（真实）');

    test('同指纹再次投递 → duplicate，不重复入库', () {
      expect(ingest(s, at).outcome, NotifyIngestOutcome.pendingAdded);
      expect(ingest(s, at).outcome, NotifyIngestOutcome.duplicate);
      expect(ingest(s, at).outcome, NotifyIngestOutcome.duplicate);
      expect(store.pending().records, hasLength(1));
    });

    test('±59 秒内同文案 → duplicate', () {
      expect(ingest(s, at).outcome, NotifyIngestOutcome.pendingAdded);
      expect(ingest(s, at.subtract(const Duration(seconds: 59))).outcome,
          NotifyIngestOutcome.duplicate);
      expect(ingest(s, at.add(const Duration(seconds: 59))).outcome,
          NotifyIngestOutcome.duplicate);
      expect(store.pending().records, hasLength(1));
    });

    test('超过时间窗的同文案 → 允许再入（非重复）', () {
      expect(ingest(s, at).outcome, NotifyIngestOutcome.pendingAdded);
      final r2 = ingest(s, at.add(const Duration(minutes: 2)));
      expect(r2.outcome, NotifyIngestOutcome.pendingAdded);
      expect(store.pending().records, hasLength(2));
    });

    test('不同账户同文案 → 不判重复', () {
      expect(ingest(s, at).outcome, NotifyIngestOutcome.pendingAdded);
      final alipayAt = at;
      final alipay = sampleOf('微信·已支付 ¥3.7（真实）');
      final r2 = NotifyIngest.ingest(NotifyMessage(
        accountId: 'acc_alipay',
        title: alipay.title,
        text: alipay.text,
        arrival: alipayAt,
      ));
      expect(r2.outcome, NotifyIngestOutcome.pendingAdded);
      expect(store.pending().records, hasLength(2));
    });

    test('pending 已确认入账后，同指纹通知仍判重复（防历史重复推）', () {
      final r = ingest(s, at);
      store.update(r.record!.copyWith(status: RecordStatus.confirmed));
      expect(store.pending().records, isEmpty);
      expect(ingest(s, at).outcome, NotifyIngestOutcome.duplicate);
      expect(store.all, hasLength(1));
    });
  });

  group('NotifyIngest 拒收与日志', () {
    test('failed 样本不入库，原文进日志', () {
      final s = sampleOf('方向冲突：收款码支付（应失败）');
      final r = ingest(s, DateTime(2026, 9, 7, 20, 0));
      expect(r.outcome, NotifyIngestOutcome.failed);
      expect(store.pending().records, isEmpty);
      expect(store.all, isEmpty);
      expect(NotifyLogStore.instance.count, 1);
      expect(NotifyLogStore.instance.entries.single.reason,
          contains('方向冲突'));
    });

    test('ignored 样本（支付失败）不入库，进日志', () {
      final s = sampleOf('支付宝·支付失败（应忽略）');
      final r = ingest(s, DateTime(2026, 9, 7, 20, 0));
      expect(r.outcome, NotifyIngestOutcome.ignored);
      expect(store.all, isEmpty);
      expect(NotifyLogStore.instance.count, 1);
    });

    test('日志环形上限 30 条', () {
      final s = sampleOf('支付宝·支付失败（应忽略）');
      for (var i = 0; i < 40; i++) {
        NotifyIngest.ingest(sampleMessage(s,
            arrival: DateTime(2026, 9, 7, 20, 0).add(Duration(minutes: i))));
      }
      expect(NotifyLogStore.instance.count, NotifyLogStore.maxEntries);
    });
  });
}
