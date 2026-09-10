import 'package:flutter_test/flutter_test.dart';

import 'package:bill_record_app/data/record_store.dart';
import 'package:bill_record_app/models/record.dart';
import 'package:bill_record_app/services/storage/record_storage_stub.dart';

Record _rec(String id, DateTime time,
    {int cents = 100, RecordType type = RecordType.expense}) {
  return Record(
    id: id,
    accountId: 'acc_wechat',
    source: RecordSource.manual,
    type: type,
    amountCents: cents,
    time: time,
    categoryId: 'food',
    counterpart: '测试$id',
    note: '备注$id',
    orderId: 'order_$id',
  );
}

void main() {
  late MemoryRecordStorage storage;
  late RecordStore store;

  setUp(() {
    storage = MemoryRecordStorage();
    store = RecordStore.replaceForTest(storage);
  });

  group('Record 序列化', () {
    test('toJson/fromJson 往返字段一致', () {
      final r = _rec('r1', DateTime(2026, 8, 20, 12, 30, 45),
          cents: 123456, type: RecordType.income);
      final back = Record.fromJson(r.toJson());
      expect(back.id, r.id);
      expect(back.accountId, r.accountId);
      expect(back.source, r.source);
      expect(back.type, RecordType.income);
      expect(back.amountCents, 123456);
      expect(back.time, r.time);
      expect(back.counterpart, r.counterpart);
      expect(back.note, r.note);
      expect(back.orderId, r.orderId);
      expect(back.categoryId, r.categoryId);
      expect(back.status, r.status);
    });

    test('fromJson 脏数据兜底不崩溃', () {
      final r = Record.fromJson(const {'id': 'x'});
      expect(r.amountCents, 0);
      expect(r.type, RecordType.expense);
      expect(r.status, RecordStatus.confirmed);
      expect(r.time, isNotNull);
    });
  });

  group('持久化恢复', () {
    test('init 从存储恢复数据', () async {
      storage.save([_rec('a', DateTime(2026, 1, 1)), _rec('b', DateTime(2026, 2, 2))]);
      await store.init();
      expect(store.all.length, 2);
      expect(store.all.any((r) => r.id == 'a'), isTrue);
    });

    test('增删改后存储内容同步', () async {
      store.add(_rec('a', DateTime(2026, 1, 1)));
      await Future<void>.delayed(Duration.zero);
      expect((await storage.load()).length, 1);

      store.remove('a');
      await Future<void>.delayed(Duration.zero);
      expect(await storage.load(), isEmpty);

      store.add(_rec('a', DateTime(2026, 1, 1)));
      await Future<void>.delayed(Duration.zero);
      store.update(_rec('a', DateTime(2026, 1, 1), cents: 999));
      await Future<void>.delayed(Duration.zero);
      final loaded = await storage.load();
      expect(loaded.single.amountCents, 999);
    });
  });

  group('定期清理（保留 3 年）', () {
    test('启动时删除 3 年前的记录并记录清理时间', () async {
      final now = DateTime.now();
      final old = _rec('old', DateTime(now.year - 4, now.month, now.day));
      final recent = _rec('recent', DateTime(now.year - 1, 5, 1));
      storage.save([old, recent]);

      await store.init();

      expect(store.all.map((r) => r.id), ['recent']);
      expect(store.consumeAutoCleanNotice(), 1);
      expect(await storage.loadLastClean(), isNotNull);
      // 持久化后的存储也不含旧记录
      expect((await storage.load()).map((r) => r.id), ['recent']);
    });

    test('间隔未到（30 天内已清理过）→ 不重复清理', () async {
      await storage.saveLastClean(DateTime.now());
      final now = DateTime.now();
      final old = _rec('old', DateTime(now.year - 4, now.month, now.day));
      storage.save([old]);

      await store.init();

      // 距上次清理不足 30 天 → 保留旧记录不删
      expect(store.all.length, 1);
      expect(store.consumeAutoCleanNotice(), 0);
    });
  });

  group('容量保护（紧急裁剪）', () {
    test('超软限时自动裁剪最老记录且不丢新数据', () async {
      store.softLimitBytes = 400; // 极小软限，便于测试
      final now = DateTime.now();
      for (var i = 0; i < 6; i++) {
        store.add(_rec('r$i', now.subtract(Duration(days: i))));
      }
      await Future<void>.delayed(Duration.zero);

      // 最新一条必须还在
      expect(store.all.any((r) => r.id == 'r0'), isTrue);
      // 旧记录被裁剪且有计数
      expect(store.consumeAutoCleanNotice(), greaterThan(0));
      // 存储可写且未置满
      expect(store.storageFull, isFalse);
      final saved = await storage.load();
      expect(saved, isNotEmpty);
      // 落盘内容体积回到软限内（粗验：条数 < 6）
      expect(saved.length, lessThan(6));
    });

    test('数据未超限时不做裁剪', () async {
      store.softLimitBytes = 10 * 1024 * 1024; // 10MB
      final now = DateTime.now();
      store.add(_rec('a', now));
      store.add(_rec('b', now.subtract(const Duration(days: 1))));
      await Future<void>.delayed(Duration.zero);

      expect(store.all.length, 2);
      expect(store.consumeAutoCleanNotice(), 0);
      expect((await storage.load()).length, 2);
    });
  });
}
