import 'package:bill_record_app/data/record_store.dart';
import 'package:bill_record_app/models/record.dart';
import 'package:bill_record_app/services/bill_importer.dart';
import 'package:bill_record_app/services/csv_bill_parser.dart';
import 'package:bill_record_app/services/storage/record_storage_stub.dart';
import 'package:flutter_test/flutter_test.dart';

/// 造一条解析后的账单条目
ParsedBill bill({
  required String orderId,
  required int cents,
  required DateTime time,
  String counterpart = '测试商户',
  bool expense = true,
}) =>
    ParsedBill(
      orderId: orderId,
      type: expense ? RecordType.expense : RecordType.income,
      amountCents: cents,
      time: time,
      counterpart: counterpart,
    );

void main() {
  late RecordStore store;

  setUp(() async {
    store = RecordStore.replaceForTest(MemoryRecordStorage());
    await store.init();
  });

  /// 造一条无单号的通知/手动记录
  Record bridgeSource(
    String id, {
    required int cents,
    required DateTime time,
    String? orderId,
    RecordSource source = RecordSource.notify,
  }) =>
      Record(
        id: id,
        accountId: 'acc_alipay',
        source: source,
        type: RecordType.expense,
        amountCents: cents,
        time: time,
        counterpart: '水果店',
        orderId: orderId,
        status: RecordStatus.confirmed,
      );

  group('指纹桥：导入时配对通知记录并回填 orderId', () {
    test('同账户同金额 ±5 分钟内 → 桥接：跳过导入 + 记录回填 orderId', () {
      final t = DateTime(2026, 9, 10, 12, 0);
      store.add(bridgeSource('n1', cents: 440, time: t));

      final summary = BillImporter.apply(
        accountId: 'acc_alipay',
        bills: [
          bill(orderId: 'alipay20260910-001', cents: 440, time: t),
          bill(orderId: 'alipay20260910-002', cents: 990, time: t),
        ],
      );

      expect(summary.imported, 1); // 只有 990 那条入库
      expect(summary.bridged, 1);
      expect(summary.duplicated, 1);
      // 通知记录被回填官方单号
      final n1 = store.all.firstWhere((r) => r.id == 'n1');
      expect(n1.orderId, 'alipay20260910-001');
      expect(n1.status, RecordStatus.confirmed); // 保持展示
    });

    test('时间差 4 分钟（窗内）→ 桥接；6 分钟（窗外）→ 正常导入', () {
      final notifyTime = DateTime(2026, 9, 10, 12, 0);
      store.add(bridgeSource('n1', cents: 440, time: notifyTime));

      // 4 分钟偏差：桥接
      final s1 = BillImporter.apply(
        accountId: 'acc_alipay',
        bills: [
          bill(
              orderId: 'in-window',
              cents: 440,
              time: notifyTime.add(const Duration(minutes: 4))),
        ],
      );
      expect(s1.bridged, 1);
      expect(store.all.firstWhere((r) => r.id == 'n1').orderId, 'in-window');

      // 6 分钟偏差：桥不上 → 正常导入（新记录）
      final s2 = BillImporter.apply(
        accountId: 'acc_alipay',
        bills: [
          bill(
              orderId: 'out-window',
              cents: 440,
              time: notifyTime.add(const Duration(minutes: 6))),
        ],
      );
      expect(s2.imported, 1);
      expect(s2.bridged, 0);
      expect(
          store.all.where((r) => r.orderId == 'out-window'), hasLength(1));
    });

    test('手动记录也能被桥接回填', () {
      final t = DateTime(2026, 9, 10, 18, 0);
      store.add(bridgeSource('m1',
          cents: 3900, time: t, source: RecordSource.manual));

      final summary = BillImporter.apply(
        accountId: 'acc_alipay',
        bills: [
          bill(orderId: 'manual-bridge', cents: 3900, time: t),
        ],
      );
      expect(summary.bridged, 1);
      expect(summary.imported, 0);
      expect(store.all.firstWhere((r) => r.id == 'm1').orderId,
          'manual-bridge');
    });

    test('已有 orderId 的记录不再被桥（走单号去重）', () {
      final t = DateTime(2026, 9, 10, 12, 0);
      store.add(bridgeSource('n1', cents: 440, time: t, orderId: 'existing'));
      store.add(bridgeSource('n2', cents: 440, time: t));

      final summary = BillImporter.apply(
        accountId: 'acc_alipay',
        bills: [
          bill(orderId: 'existing', cents: 440, time: t), // 单号命中
          bill(orderId: 'new-001', cents: 440, time: t), // 桥接 n2
        ],
      );
      expect(summary.imported, 0);
      expect(summary.bridged, 1);
      expect(store.all.firstWhere((r) => r.id == 'n1').orderId, 'existing');
      expect(store.all.firstWhere((r) => r.id == 'n2').orderId, 'new-001');
    });

    test('同额多笔逐条配对（时间最近的优先，不重复桥接）', () {
      final t1 = DateTime(2026, 9, 10, 12, 0);
      final t2 = DateTime(2026, 9, 10, 12, 2); // 相隔 2 分钟的两笔同额
      store.add(bridgeSource('n1', cents: 10000, time: t1));
      store.add(bridgeSource('n2', cents: 10000, time: t2));

      final summary = BillImporter.apply(
        accountId: 'acc_alipay',
        bills: [
          bill(orderId: 'a', cents: 10000, time: t1),
          bill(orderId: 'b', cents: 10000, time: t2),
        ],
      );
      expect(summary.imported, 0);
      expect(summary.bridged, 2);
      final n1 = store.all.firstWhere((r) => r.id == 'n1');
      final n2 = store.all.firstWhere((r) => r.id == 'n2');
      // 各自桥到时间最接近的账单条目
      expect({n1.orderId, n2.orderId}, {'a', 'b'});
    });

    test('桥接后再次导入同单号 → 单号去重命中（不重复）', () {
      final t = DateTime(2026, 9, 10, 12, 0);
      store.add(bridgeSource('n1', cents: 440, time: t));

      BillImporter.apply(
        accountId: 'acc_alipay',
        bills: [bill(orderId: 'wx001', cents: 440, time: t)],
      );
      // 再次导入同一账单（模拟对账/重复下载）
      final again = BillImporter.apply(
        accountId: 'acc_alipay',
        bills: [bill(orderId: 'wx001', cents: 440, time: t)],
      );
      expect(again.imported, 0);
      expect(again.bridged, 0);
      expect(again.duplicated, 1); // 纯单号命中
      expect(store.all, hasLength(1)); // 没有重复记录
    });
  });
}
