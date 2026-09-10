import 'dart:convert';
import 'dart:io';

import 'package:bill_record_app/data/record_store.dart';
import 'package:bill_record_app/models/record.dart';
import 'package:bill_record_app/services/notify/notify_account_map.dart';
import 'package:bill_record_app/services/notify/notify_log.dart';
import 'package:bill_record_app/services/notify/notify_queue_io.dart';
import 'package:bill_record_app/services/storage/record_storage_stub.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory dir;
  late NotifyQueueDrainer drainer;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('lsz_queue_test');
    drainer = NotifyQueueDrainer(dirProvider: () async => dir);
    RecordStore.replaceForTest(MemoryRecordStorage());
    await RecordStore.instance.init();
    NotifyLogStore.instance.clear();
  });

  tearDown(() async {
    if (await dir.exists()) {
      await dir.delete(recursive: true);
    }
  });

  File queueFile() => File('${dir.path}/${NotifyQueueDrainer.fileName}');

  Map<String, dynamic> entry(String pkg,
          {String title = '微信支付',
          String text = '已支付¥3.7',
          int? time}) =>
      {
        'pkg': pkg,
        'title': title,
        'text': text,
        'time': time ?? DateTime(2026, 9, 7, 20, 0).millisecondsSinceEpoch,
      };

  group('NotifyAccountMap 包名映射', () {
    test('微信/支付宝真实包名 → 预置账户', () {
      expect(NotifyAccountMap.accountForPackage('com.tencent.mm'),
          'acc_wechat');
      expect(NotifyAccountMap.accountForPackage('com.eg.android.AlipayGphone'),
          'acc_alipay');
    });

    test('未知包名 → null / 不在关注列表', () {
      expect(NotifyAccountMap.accountForPackage('com.example.other'), isNull);
      expect(NotifyAccountMap.isWatched('com.tencent.mm'), isTrue);
      expect(NotifyAccountMap.isWatched('com.example.other'), isFalse);
    });
  });

  group('NotifyQueueDrainer 补拉', () {
    test('无队列文件 → 0 条，不抛异常', () async {
      final r = await drainer.drain();
      expect(r.added, 0);
      expect(r.processed, 0);
    });

    test('微信+支付宝 两条 → 各入待确认，队列文件删除', () async {
      await queueFile().writeAsString(jsonEncode([
        entry('com.tencent.mm', text: '已支付¥3.7'),
        entry('com.eg.android.AlipayGphone',
            title: '交易提醒', text: '你收到一个红包¥6.66'),
      ]));
      final r = await drainer.drain();
      expect(r.processed, 2);
      expect(r.added, 2);

      final pendings = RecordStore.instance.pending().records;
      expect(pendings, hasLength(2));
      final wechat =
          pendings.singleWhere((x) => x.accountId == 'acc_wechat');
      expect(wechat.amountCents, 370);
      expect(wechat.type, RecordType.expense);
      final alipay =
          pendings.singleWhere((x) => x.accountId == 'acc_alipay');
      expect(alipay.amountCents, 666);
      expect(alipay.type, RecordType.income);
      expect(await queueFile().exists(), isFalse); // 队列一次性消费
    });

    test('到达时间还原为通知时刻', () async {
      final t = DateTime(2026, 9, 7, 20, 30).millisecondsSinceEpoch;
      await queueFile().writeAsString(jsonEncode([
        entry('com.tencent.mm', text: '已支付¥1.00', time: t),
      ]));
      await drainer.drain();
      final rec = RecordStore.instance.pending().records.single;
      expect(rec.time, DateTime.fromMillisecondsSinceEpoch(t));
    });

    test('未知包名条目被跳过，不建档', () async {
      await queueFile().writeAsString(jsonEncode([
        entry('com.example.other', text: '未知来源通知¥1.00'),
        entry('com.tencent.mm', text: '已支付¥3.7'),
      ]));
      final r = await drainer.drain();
      expect(r.added, 1);
      expect(RecordStore.instance.pending().records, hasLength(1));
      expect(await queueFile().exists(), isFalse);
    });

    test('解析失败的通知 → 消费并进无法解析日志（不阻塞后续）', () async {
      await queueFile().writeAsString(jsonEncode([
        entry('com.tencent.mm', text: '纯文本无方向无金额'),
        entry('com.tencent.mm', text: '已支付¥2.00'),
      ]));
      final r = await drainer.drain();
      expect(r.processed, 2);
      expect(r.added, 1);
      expect(RecordStore.instance.pending().records, hasLength(1));
      expect(NotifyLogStore.instance.count, 1);
    });

    test('重复 drain（队列已删）→ 第二次 0 条且不重复入库', () async {
      await queueFile().writeAsString(jsonEncode([
        entry('com.tencent.mm', text: '已支付¥3.7'),
      ]));
      await drainer.drain();
      final r2 = await drainer.drain();
      expect(r2.added, 0);
      expect(r2.processed, 0);
      expect(RecordStore.instance.pending().records, hasLength(1));
    });

    test('损坏队列文件 → 丢弃文件不抛异常', () async {
      await queueFile().writeAsString('{broken json');
      final r = await drainer.drain();
      expect(r.added, 0);
      expect(r.processed, 0);
      expect(await queueFile().exists(), isFalse);
    });
  });
}
