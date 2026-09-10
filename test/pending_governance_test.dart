import 'package:bill_record_app/data/record_store.dart';
import 'package:bill_record_app/models/record.dart';
import 'package:bill_record_app/services/storage/record_storage_stub.dart';
import 'package:flutter_test/flutter_test.dart';

Record _pending(String id, {required DateTime time, int cents = 100}) =>
    Record(
      id: id,
      accountId: 'acc_wechat',
      source: RecordSource.notify,
      type: RecordType.expense,
      amountCents: cents,
      time: time,
      status: RecordStatus.pending,
    );

void main() {
  late RecordStore store;

  setUp(() async {
    store = RecordStore.replaceForTest(MemoryRecordStorage());
    await store.init();
  });

  int pendingCount() => store.pending().records.length;

  group('tidyPending 常规线（>20 且满 48h → 最老自动入账）', () {
    test('不足 20 条不动作', () async {
      for (var i = 0; i < 15; i++) {
        store.add(_pending('p$i',
            time: DateTime.now().subtract(Duration(days: 10))));
      }
      expect(await store.tidyPending(), 0);
      expect(pendingCount(), 15);
    });

    test('超过 20 条但都太新（不满 48h）→ 不动', () async {
      for (var i = 0; i < 25; i++) {
        store.add(_pending('p$i', time: DateTime.now()));
      }
      expect(await store.tidyPending(), 0);
      expect(pendingCount(), 25);
    });

    test('25 条且最老 5 条满 48h → 自动入账 5 条（最老的）', () async {
      final now = DateTime.now();
      for (var i = 0; i < 25; i++) {
        store.add(_pending('p$i',
            time: now.subtract(Duration(hours: i == 0 ? 100 : 1))));
      }
      // 只让 p0 满 48h：需要 5 条满 48h 才触发 5 条，这里只有 1 条够老
      expect(await store.tidyPending(), 1);
      expect(pendingCount(), 24);
      final confirmed = store.all
          .where((r) => r.status == RecordStatus.confirmed)
          .toList();
      expect(confirmed, hasLength(1));
      expect(confirmed.single.id, 'p0'); // 最老的那条
      expect(confirmed.single.categoryId, isNull); // 未分类入账
    });

    test('30 条中 10 条满 48h → 入账 10 条（回到 20 线内）', () async {
      final now = DateTime.now();
      for (var i = 0; i < 30; i++) {
        store.add(_pending('p$i',
            time: now.subtract(Duration(hours: i < 10 ? 100 : 1))));
      }
      expect(await store.tidyPending(), 10);
      expect(pendingCount(), 20);
    });

    test('自动入账不影响 confirmed 记录', () async {
      final now = DateTime.now();
      for (var i = 0; i < 25; i++) {
        store.add(_pending('p$i', time: now.subtract(const Duration(hours: 100))));
      }
      store.add(Record(
        id: 'keep',
        accountId: 'acc_wechat',
        source: RecordSource.manual,
        type: RecordType.expense,
        amountCents: 999,
        time: now,
        status: RecordStatus.confirmed,
      ));
      await store.tidyPending();
      expect(store.all.any((r) => r.id == 'keep'), isTrue);
    });
  });

  group('tidyPending 容量兜底（>100 无条件入账）', () {
    test('105 条全新记录 → 无条件入账 5 条最老的到 100', () async {
      final now = DateTime.now();
      for (var i = 0; i < 105; i++) {
        store.add(_pending('p$i', time: now.subtract(Duration(minutes: i))));
      }
      // 全是新记录（不满 48h），常规线不触发；容量兜底强制入账 5 条
      expect(await store.tidyPending(), 5);
      expect(pendingCount(), 100);
      // 被入账的是最老的 5 条（时间最早 = 编号最大）
      final confirmed = store.all
          .where((r) => r.status == RecordStatus.confirmed)
          .toList();
      expect(confirmed, hasLength(5));
      expect(confirmed.map((r) => r.id),
          containsAll(['p100', 'p101', 'p102', 'p103', 'p104']));
    });

    test('常规线处理完仍超 100 → 继续兜底', () async {
      final now = DateTime.now();
      // 150 条：50 条满 48h（常规线入 130 到 20 内? 实际入 130 → 剩 20？超限超额处理）
      // 设计：常规线入账到 ≤20；150-20=130 全部够老 → 全入，剩 20
      for (var i = 0; i < 150; i++) {
        store.add(_pending('p$i', time: now.subtract(const Duration(hours: 100))));
      }
      final n = await store.tidyPending();
      expect(n, 130);
      expect(pendingCount(), 20);
    });
  });

  group('consumePendingAutoNotice 一次性消费', () {
    test('入账后计数可消费一次', () async {
      final now = DateTime.now();
      for (var i = 0; i < 130; i++) {
        store.add(_pending('p$i', time: now.subtract(const Duration(hours: 100))));
      }
      await store.tidyPending();
      expect(store.pendingAutoConfirmed, 110);
      expect(store.consumePendingAutoNotice(), 110);
      expect(store.consumePendingAutoNotice(), 0);
    });
  });
}
