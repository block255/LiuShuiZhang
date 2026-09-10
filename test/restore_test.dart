import 'dart:convert';
import 'dart:typed_data';

import 'package:bill_record_app/data/record_store.dart';
import 'package:bill_record_app/models/record.dart';
import 'package:bill_record_app/services/restore_service.dart';
import 'package:bill_record_app/services/storage/record_storage_stub.dart';
import 'package:flutter_test/flutter_test.dart';

Record _mk(String id, {int cents = 100, String? orderId}) => Record(
      id: id,
      accountId: 'acc_wechat',
      source: RecordSource.notify,
      type: RecordType.expense,
      amountCents: cents,
      time: DateTime(2026, 9, 9, 12, 0),
      orderId: orderId,
      status: RecordStatus.confirmed,
    );

void main() {
  late RecordStore store;

  setUp(() async {
    store = RecordStore.replaceForTest(MemoryRecordStorage());
    await store.init();
  });

  group('RestoreService 备份解析', () {
    test('合法备份列表 → 全部解析', () {
      final bytes = Uint8List.fromList(
          utf8.encode(jsonEncode([_mk('a', cents: 100).toJson()])));
      final r = RestoreService.parse(bytes)!;
      expect(r.records, hasLength(1));
      expect(r.records.single.id, 'a');
      expect(r.records.single.amountCents, 100);
      expect(r.skipped, 0);
    });

    test('含损坏条目 → 容错跳过不拖垮整体', () {
      final bytes = Uint8List.fromList(utf8.encode(jsonEncode([
        _mk('a').toJson(),
        {'id': 'bad-time', 'time': 12345}, // time 类型错 → fromJson 抛 → 跳过
        'not-a-map', // 非 map → 跳过
      ])));
      final r = RestoreService.parse(bytes)!;
      expect(r.records, hasLength(1));
      expect(r.skipped, 2);
    });

    test('非列表 JSON / 非 JSON → null', () {
      expect(RestoreService.parse(
          Uint8List.fromList(utf8.encode('{"a":1}'))), isNull);
      expect(RestoreService.parse(Uint8List.fromList(utf8.encode('abc'))),
          isNull);
      expect(RestoreService.parse(Uint8List(0)), isNull);
    });

    test('pending 状态记录可解析保留', () {
      final rec = _mk('p1').copyWith(status: RecordStatus.pending);
      final bytes =
          Uint8List.fromList(utf8.encode(jsonEncode([rec.toJson()])));
      final r = RestoreService.parse(bytes)!;
      expect(r.records.single.status, RecordStatus.pending);
    });
  });

  group('store.restoreAll 全量覆盖', () {
    test('清空现有并载入备份', () async {
      store.add(_mk('old1'));
      store.add(_mk('old2'));
      await store.restoreAll([_mk('backup1', cents: 50)]);
      expect(store.all, hasLength(1));
      expect(store.all.single.id, 'backup1');
    });
  });

  group('store.mergeBackup 合并去重', () {
    test('备份新增 + 同 id 覆盖 + 库独有保留', () async {
      store.add(_mk('same', cents: 100));
      store.add(_mk('only-lib', cents: 200));

      final r = await store.mergeBackup([
        _mk('same', cents: 999), // 同 id：备份版覆盖
        _mk('only-backup', cents: 300), // 新增
      ]);

      expect(r.added, 1);
      expect(r.updated, 1);
      expect(store.all, hasLength(3));
      expect(store.all.firstWhere((x) => x.id == 'same').amountCents, 999);
      expect(store.all.any((x) => x.id == 'only-lib'), isTrue);
      expect(store.all.any((x) => x.id == 'only-backup'), isTrue);
    });
  });
}
