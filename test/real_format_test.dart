import 'dart:convert';
import 'dart:typed_data';

import 'package:excel/excel.dart';
import 'package:fast_gbk/fast_gbk.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bill_record_app/models/record.dart';
import 'package:bill_record_app/services/bill_file_reader.dart';
import 'package:bill_record_app/services/csv_bill_parser.dart';

/// 真实格式校准测试：以"参考用样例文件"的结构为基准（**数据已脱敏**）。
/// 覆盖：支付宝 GBK CSV（信息头+表头扫描）、微信 XLSX（信息行+表头）。
/// 脱敏原则：只替换"是谁"（商户/卡号/手机号/单号），**不改"长什么样"**
/// （列数、分隔符、时间与金额格式、掩码位数、单号长度与字符类型全部保留），
/// 因此格式回归能力不受影响。未脱敏原件见 `参考用样例文件\真实样本备份\`。
void main() {
  group('真实支付宝 CSV（GBK 编码 + 导出信息头）', () {
    // 真实文件前部为导出信息/特别提示，数据从"电子客户回单"分隔行后的表头开始
    String buildAlipayGbkCsv() {
      return [
        '------------------------------------------------------------------------------------',
        '导出信息：',
        '姓名：测试用户',
        '支付宝账户：138****0000',
        '起始时间：[2026-08-06 00:00:00]    终止时间：[2026-09-06 23:59:59]',
        '共2笔记录',
        '收入：0笔 0.00元',
        '支出：2笔 20.80元',
        '',
        '特别提示：',
        '1.本回单内容可表明支付宝受理了相应支付交易申请',
        '',
        '------------------------支付宝支付科技有限公司  电子客户回单------------------------',
        '交易时间,交易分类,交易对方,对方账号,商品说明,收/支,金额,收/付款方式,交易状态,交易订单号,商家订单号,备注,',
        '2026-09-05 20:32:19,商业服务,某某科技服务,/,某API服务(138******00),支出,10.00,某某银行储蓄卡(0000),交易成功,2026090523001440000000000000,11P0000000000000000W00,',
        '2026-09-05 18:29:41,餐饮美食,某某水果店,139******00,收钱码收款,支出,10.80,某某银行储蓄卡(0000),交易成功,2026090523001440111111111111,17886041810542759740000,',
      ].join('\n');
    }

    test('GBK 字节流 → 读取 → 解析成功（跳过信息头）', () async {
      final gbkText = buildAlipayGbkCsv();
      final bytes = Uint8List.fromList(gbk.encode(gbkText)); // GBK 编码字节

      final rows = await BillFileReader.readRows('支付宝交易明细.csv', bytes);
      expect(rows.length, greaterThan(3)); // 信息行+表头+2数据

      final r = CsvBillParser.parseRows(rows);
      expect(r.bills.length, 2);
      expect(r.skippedRows, 0);

      final first = r.bills[0];
      expect(first.type, RecordType.expense);
      expect(first.amountCents, 1000);
      expect(first.counterpart, '某某科技服务');
      expect(first.time, DateTime(2026, 9, 5, 20, 32, 19));
      expect(first.orderId, '2026090523001440000000000000');

      final second = r.bills[1];
      expect(second.amountCents, 1080);
      expect(second.counterpart, '某某水果店');
    });

    test('UTF-8 CSV 读取不受影响', () async {
      const csv = '交易时间,交易对方,收/支,金额,交易单号\n'
          '2026-09-01 10:00:00,测试店,支出,5.00,order1\n';
      final rows = await BillFileReader.readRows(
          'a.csv', Uint8List.fromList(utf8.encode(csv)));
      final r = CsvBillParser.parseRows(rows);
      expect(r.bills.single.amountCents, 500);
    });
  });

  group('真实微信 XLSX（导出信息行 + 表头）', () {
    // 用 excel 包动态生成与真实文件同构的 xlsx：信息行（单列）+ 分隔行 + 表头 + 数据
    Uint8List buildWechatXlsx() {
      final excel = Excel.createExcel();
      final sheet = excel['账单'];
      List<CellValue?> row(List<String> cells) =>
          cells.map((c) => TextCellValue(c)).toList();

      // 信息行（模拟真实文件前置信息）
      sheet.appendRow(row(['微信支付账单明细']));
      sheet.appendRow(row(['起始时间：[2026-08-05] 共2笔记录']));
      sheet.appendRow(
          row(['----------------------微信支付账单明细列表--------------------']));
      // 表头
      sheet.appendRow(row([
        '交易时间', '交易类型', '交易对方', '商品', '收/支', '金额(元)',
        '支付方式', '当前状态', '交易单号', '商户单号', '备注',
      ]));
      // 数据行
      sheet.appendRow(row([
        '2026-09-05 09:30:00', '商户消费', '沙县小吃', '餐饮', '支出', '¥15.00',
        '零钱', '支付成功', 'wx_order_001', '', '',
      ]));
      sheet.appendRow(row([
        '2026-09-05 20:00:00', '微信红包', '李四', '红包', '收入', '¥66.00',
        '零钱', '已存入零钱', 'wx_order_002', '', '',
      ]));

      return Uint8List.fromList(excel.save()!);
    }

    test('xlsx 字节 → 读取 → 解析（自动定位表头）', () async {
      final bytes = buildWechatXlsx();
      final rows = await BillFileReader.readRows('微信账单.xlsx', bytes);
      expect(rows.length, greaterThan(4));

      final r = CsvBillParser.parseRows(rows);
      expect(r.bills.length, 2);

      final first = r.bills[0];
      expect(first.type, RecordType.expense);
      expect(first.amountCents, 1500);
      expect(first.counterpart, '沙县小吃');
      expect(first.time, DateTime(2026, 9, 5, 9, 30));

      final second = r.bills[1];
      expect(second.type, RecordType.income);
      expect(second.amountCents, 6600);
    });
  });
}
