import 'dart:convert';
import 'dart:io';

import 'package:bill_record_app/models/record.dart';
import 'package:bill_record_app/services/storage/record_storage_file.dart';
import 'package:flutter_test/flutter_test.dart';

Record _mk(String id,
        {int cents = 1250,
        RecordType type = RecordType.expense,
        RecordStatus status = RecordStatus.confirmed,
        String? counterpart,
        String? orderId}) =>
    Record(
      id: id,
      accountId: 'acc_wechat',
      source: RecordSource.import,
      type: type,
      amountCents: cents,
      time: DateTime(2026, 9, 1, 12, 30),
      counterpart: counterpart,
      orderId: orderId,
      status: status,
    );

void main() {
  late Directory dir;
  late FileRecordStorage storage;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('lsz_file_test');
    storage = FileRecordStorage(directoryProvider: () async => dir);
  });

  tearDown(() async {
    if (await dir.exists()) {
      await dir.delete(recursive: true);
    }
  });

  test('空目录 load → 空列表，lastClean → null', () async {
    expect(await storage.load(), isEmpty);
    expect(await storage.loadLastClean(), isNull);
  });

  test('save → load 往返一致（含 pending 通知记录与全字段）', () async {
    final records = [
      _mk('r1',
          cents: 370,
          status: RecordStatus.pending,
          counterpart: null,
          orderId: null),
      _mk('r2',
          cents: 6666,
          type: RecordType.income,
          status: RecordStatus.confirmed,
          counterpart: '张三',
          orderId: 'wx20260901001'),
    ];
    await storage.save(records);

    final loaded = await storage.load();
    expect(loaded, hasLength(2));
    final r1 = loaded.firstWhere((r) => r.id == 'r1');
    expect(r1.amountCents, 370);
    expect(r1.source, RecordSource.import);
    expect(r1.status, RecordStatus.pending);
    expect(r1.counterpart, isNull);
    final r2 = loaded.firstWhere((r) => r.id == 'r2');
    expect(r2.type, RecordType.income);
    expect(r2.counterpart, '张三');
    expect(r2.orderId, 'wx20260901001');
    expect(r2.time, DateTime(2026, 9, 1, 12, 30));
  });

  test('连续 save 两次（覆盖写入不报错、不损坏）', () async {
    await storage.save([_mk('a')]);
    await storage.save([_mk('a'), _mk('b', cents: 200)]);
    final loaded = await storage.load();
    expect(loaded, hasLength(2));
    // 无 .tmp 残留
    final tmp = File('${dir.path}/records.json.tmp');
    expect(await tmp.exists(), isFalse);
  });

  test('clear 清空数据与清理标记', () async {
    await storage.save([_mk('a')]);
    await storage.saveLastClean(DateTime(2026, 9, 6));
    await storage.clear();
    expect(await storage.load(), isEmpty);
    expect(await storage.loadLastClean(), isNull);
  });

  test('lastClean 往返', () async {
    final t = DateTime(2026, 9, 6, 8, 30);
    await storage.saveLastClean(t);
    expect(await storage.loadLastClean(), t);
  });

  test('损坏的 records.json → load 返回空列表（不抛异常）', () async {
    await File('${dir.path}/records.json')
        .writeAsString('{"broken": [');
    expect(await storage.load(), isEmpty);
  });

  test('records.json 内容非列表 → load 返回空列表', () async {
    await File('${dir.path}/records.json')
        .writeAsString(jsonEncode({'not': 'a list'}));
    expect(await storage.load(), isEmpty);
  });

  test('单条记录字段缺失 → fromJson 兜底不拖垮整体', () async {
    await File('${dir.path}/records.json').writeAsString(jsonEncode([
      {'id': 'ok1'},
      'bad-entry',
    ]));
    final loaded = await storage.load();
    // 非对象元素会抛 → 整体兜底为空（宁可空库不崩）
    expect(loaded, isEmpty);
  });
}
