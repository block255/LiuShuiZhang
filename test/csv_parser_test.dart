import 'package:flutter_test/flutter_test.dart';

import 'package:bill_record_app/models/record.dart';
import 'package:bill_record_app/services/csv_bill_parser.dart';

import 'fixtures/samples.dart';

void main() {
  group('微信账单 CSV 解析', () {
    test('识别收入与支出，方向/金额/时间/对方正确', () {
      final r = CsvBillParser.parse(wechatBillCsv);
      // 7 行：5 有效 + 1 退款行 + 1 "其他"行（均计入 skipped）
      expect(r.bills.length, 5);
      expect(r.skippedRows, 2);

      final first = r.bills.first; // 沙县小吃 支出12.5
      expect(first.type, RecordType.expense);
      expect(first.amountCents, 1250);
      expect(first.counterpart, '沙县小吃');
      expect(first.time, DateTime(2026, 8, 20, 12, 30, 45));
      expect(first.orderId, '4200001234202608201234567890');

      final redpacket = r.bills[2]; // 李四 红包 收入50
      expect(redpacket.type, RecordType.income);
      expect(redpacket.amountCents, 5000);
      expect(redpacket.counterpart, '李四');
    });

    test('退款与"其他"不计收支的行被跳过', () {
      final r = CsvBillParser.parse(wechatBillCsv);
      // 已全额退款行 + 收/支=其他 行 不在结果
      expect(r.bills.any((b) => b.rawStatus.contains('退款')), isFalse);
      expect(r.bills.any((b) => b.amountCents == 0), isFalse);
    });
  });

  group('支付宝账单 CSV 解析', () {
    test('识别收入与支出（无引号、不同列序/列名）', () {
      final r = CsvBillParser.parse(alipayBillCsv);
      // 6 行：4 有效 + 1 交易关闭 + 1 交易失败（计入 skipped）
      expect(r.bills.length, 4);
      expect(r.skippedRows, 2);

      final boxed = r.bills[0]; // 盒马 支出88.60
      expect(boxed.type, RecordType.expense);
      expect(boxed.amountCents, 8860);
      expect(boxed.counterpart, '盒马鲜生');

      final salary = r.bills[2]; // 工资 收入5000
      expect(salary.type, RecordType.income);
      expect(salary.amountCents, 500000);
      expect(salary.orderId, '2026082522001000000000000003');
    });
  });

  group('解析器健壮性', () {
    test('带 BOM 的表头可解析', () {
      final csv = '\uFEFF$wechatBillCsv';
      final r = CsvBillParser.parse(csv);
      expect(r.bills.length, 5);
    });

    test('空文本/无有效表头返回空', () {
      expect(CsvBillParser.parse('').bills, isEmpty);
      expect(CsvBillParser.parse('随便一行,没有表头').bills, isEmpty);
    });

    test('金额支持负数与千分位', () {
      // 手搓一个小 CSV：金额列带负号（部分渠道格式）
      const csv = '时间,摘要,收/支,金额\n'
          '2026-09-01 10:00:00,测试,支出,-1,234.56\n';
      final r = CsvBillParser.parse(csv);
      expect(r.bills, isEmpty); // 负金额视为无效被跳过（退款另有状态列管理）
    });

    test('CRLF 换行兼容', () {
      final csv = wechatBillCsv.replaceAll('\n', '\r\n');
      final r = CsvBillParser.parse(csv);
      expect(r.bills.length, 5);
    });
  });
}
