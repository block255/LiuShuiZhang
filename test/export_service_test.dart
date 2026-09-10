import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:bill_record_app/models/record.dart';
import 'package:bill_record_app/services/export_service.dart';

Record _rec(String id,
    {required int cents,
    DateTime? time,
    RecordType type = RecordType.expense,
    String? counterpart,
    String? note,
    String? categoryId,
    String accountId = 'acc_wechat'}) {
  return Record(
    id: id,
    accountId: accountId,
    source: RecordSource.import,
    type: type,
    amountCents: cents,
    time: time ?? DateTime(2026, 9, 5, 12, 30, 45),
    counterpart: counterpart,
    categoryId: categoryId,
    note: note,
    orderId: 'order_$id',
  );
}

void main() {
  group('ExportService CSV', () {
    test('表头与字段正确（中文列、账户名、分类名、元两位小数）', () {
      final records = [
        _rec('a', cents: 1250, counterpart: '沙县小吃', categoryId: 'food'),
        _rec('b', cents: 500000, type: RecordType.income,
            counterpart: '公司', categoryId: 'salary', accountId: 'acc_alipay'),
      ];
      final csv = ExportService.buildCsv(records);
      final lines = csv.trim().split('\n');

      expect(lines[0],
          '时间,账户,收支,金额(元),分类,对方,备注,交易单号,记录来源');
      expect(lines[1],
          '2026-09-05 12:30:45,微信支付,支出,12.50,餐饮,沙县小吃,,order_a,导入');
      expect(lines[2],
          '2026-09-05 12:30:45,支付宝,收入,5000.00,工资,公司,,order_b,导入');
    });

    test('含逗号/引号的字段被正确转义', () {
      final records = [
        _rec('a', cents: 100, counterpart: '张三, "外卖"店', note: '备注"含引号"'),
      ];
      final csv = ExportService.buildCsv(records);
      expect(csv, contains('"张三, ""外卖""店"'));
      expect(csv, contains('"备注""含引号"""'));
    });
  });

  group('ExportService JSON', () {
    test('全字段保真，可反序列化回 Record', () {
      final r = _rec('a', cents: 1250, counterpart: '沙县小吃', categoryId: 'food',
          note: '含,逗号', time: DateTime(2026, 8, 20, 9, 8, 7));
      final json = ExportService.buildJson([r]);
      final decoded =
          (jsonDecode(json) as List).map((e) => Record.fromJson((e as Map).cast<String, dynamic>())).toList();
      expect(decoded.single.id, 'a');
      expect(decoded.single.amountCents, 1250);
      expect(decoded.single.time, DateTime(2026, 8, 20, 9, 8, 7));
      expect(decoded.single.note, '含,逗号');
      expect(decoded.single.orderId, 'order_a');
    });

    test('空列表导出空数组', () {
      expect(ExportService.buildJson([]), '[]');
    });
  });
}
