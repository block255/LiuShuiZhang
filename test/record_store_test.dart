import 'package:flutter_test/flutter_test.dart';

import 'package:bill_record_app/data/record_store.dart';
import 'package:bill_record_app/models/record.dart';
import 'package:bill_record_app/utils/money.dart';

Record _rec({
  required String id,
  required RecordType type,
  required int cents,
  required DateTime time,
  String accountId = 'acc_wechat',
  RecordSource source = RecordSource.manual,
  RecordStatus status = RecordStatus.confirmed,
}) {
  return Record(
    id: id,
    accountId: accountId,
    source: source,
    type: type,
    amountCents: cents,
    time: time,
    status: status,
  );
}

void main() {
  const wechat = 'acc_wechat';
  const alipay = 'acc_alipay';

  // 基准时间：2026-09-05 12:00 本地
  DateTime at(int day, int hour) => DateTime(2026, 9, day, hour);

  RecordStore newStore() {
    // 仓库是单例，测试间需要重置：直接清空内部数据
    final store = RecordStore.instance;
    // ignore: invalid_use_of_visible_for_testing_member
    store.clearForTest();
    return store;
  }

  group('RecordStore 基本操作', () {
    test('add/query：记录可查、时间倒序', () {
      final s = newStore();
      s.add(_rec(id: 'a', type: RecordType.expense, cents: 100, time: at(1, 9)));
      s.add(_rec(id: 'b', type: RecordType.income, cents: 5000, time: at(3, 9)));
      s.add(_rec(id: 'c', type: RecordType.expense, cents: 200, time: at(2, 9)));
      final q = s.query(const RecordQuery());
      expect(q.records.map((r) => r.id).toList(), ['b', 'c', 'a']);
    });

    test('remove/update', () {
      final s = newStore();
      s.add(_rec(id: 'a', type: RecordType.expense, cents: 100, time: at(1, 9)));
      s.remove('a');
      expect(s.query(const RecordQuery()).records, isEmpty);

      s.add(_rec(id: 'b', type: RecordType.expense, cents: 100, time: at(1, 9)));
      s.update(_rec(
        id: 'b',
        type: RecordType.income,
        cents: 999,
        time: at(1, 9),
      ));
      final q = s.query(const RecordQuery(type: RecordType.income));
      expect(q.incomeCents, 999);
    });
  });

  group('筛选逻辑', () {
    test('按账户筛选', () {
      final s = newStore();
      s.add(_rec(id: 'a', type: RecordType.expense, cents: 100, time: at(1, 9), accountId: wechat));
      s.add(_rec(id: 'b', type: RecordType.expense, cents: 200, time: at(1, 9), accountId: alipay));
      final q = s.query(const RecordQuery(accountId: wechat));
      expect(q.records.length, 1);
      expect(q.records.first.id, 'a');
    });

    test('按收支类型筛选', () {
      final s = newStore();
      s.add(_rec(id: 'a', type: RecordType.expense, cents: 100, time: at(1, 9)));
      s.add(_rec(id: 'b', type: RecordType.income, cents: 200, time: at(1, 9)));
      final q = s.query(const RecordQuery(type: RecordType.income));
      expect(q.records.length, 1);
      expect(q.records.first.id, 'b');
    });

    test('时间范围：start 含、end 不含', () {
      final s = newStore();
      // 9/1 9:00 与 9/5 12:00 在界内，9/10 在界外
      s.add(_rec(id: 'a', type: RecordType.expense, cents: 1, time: at(1, 9)));
      s.add(_rec(id: 'b', type: RecordType.expense, cents: 2, time: at(5, 12)));
      s.add(_rec(id: 'c', type: RecordType.expense, cents: 3, time: at(10, 9)));
      final q = s.query(RecordQuery(start: DateTime(2026, 9, 1), end: DateTime(2026, 9, 6)));
      expect(q.records.map((r) => r.id).toSet(), {'a', 'b'});
    });

    test('汇总：income/expense 各自合计', () {
      final s = newStore();
      s.add(_rec(id: 'a', type: RecordType.expense, cents: 1234, time: at(1, 9)));
      s.add(_rec(id: 'b', type: RecordType.expense, cents: 66, time: at(2, 9)));
      s.add(_rec(id: 'c', type: RecordType.income, cents: 500000, time: at(3, 9)));
      final q = s.query(const RecordQuery());
      expect(q.expenseCents, 1300);
      expect(q.incomeCents, 500000);
    });

    test('默认只查已入账，pending 不出现', () {
      final s = newStore();
      s.add(_rec(id: 'ok', type: RecordType.expense, cents: 100, time: at(1, 9)));
      s.add(_rec(
        id: 'pending',
        type: RecordType.expense,
        cents: 100,
        time: at(1, 9),
        status: RecordStatus.pending,
      ));
      final q = s.query(const RecordQuery());
      expect(q.records.length, 1);
      expect(q.records.first.id, 'ok');

      final p = s.pending();
      expect(p.records.length, 1);
      expect(p.records.first.id, 'pending');
    });

    test('组合筛选：账户+类型+时间', () {
      final s = newStore();
      s.add(_rec(id: 'a', type: RecordType.expense, cents: 100, time: at(1, 9), accountId: wechat));
      s.add(_rec(id: 'b', type: RecordType.income, cents: 200, time: at(1, 9), accountId: wechat));
      s.add(_rec(id: 'c', type: RecordType.expense, cents: 300, time: at(20, 9), accountId: wechat));
      s.add(_rec(id: 'd', type: RecordType.expense, cents: 400, time: at(1, 9), accountId: alipay));
      final q = s.query(RecordQuery(
        accountId: wechat,
        type: RecordType.expense,
        start: DateTime(2026, 9, 1),
        end: DateTime(2026, 9, 6),
      ));
      expect(q.records.map((r) => r.id).toList(), ['a']);
      expect(q.expenseCents, 100);
    });
  });

  group('Money 工具', () {
    test('format 分→元字符串（千分位）', () {
      expect(Money.format(123456), '1,234.56');
      expect(Money.format(5), '0.05');
      expect(Money.format(100), '1.00');
      expect(Money.format(123456789), '1,234,567.89');
      expect(Money.format(0), '0.00');
    });

    test('parseYuanToCents 元→分', () {
      expect(Money.parseYuanToCents('12.5'), 1250);
      expect(Money.parseYuanToCents('0.01'), 1);
      expect(Money.parseYuanToCents(' 8 '), 800);
      expect(Money.parseYuanToCents('abc'), isNull);
      expect(Money.parseYuanToCents(''), isNull);
      expect(Money.parseYuanToCents('-1'), isNull);
    });
  });
}
