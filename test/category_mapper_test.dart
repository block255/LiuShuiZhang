import 'package:flutter_test/flutter_test.dart';

import 'package:bill_record_app/models/record.dart';
import 'package:bill_record_app/services/category_mapper.dart';

void main() {
  group('支出关键词映射', () {
    test('常见商户命中分类', () {
      expect(mapCategoryId(RecordType.expense, '沙县小吃'), 'food');
      expect(mapCategoryId(RecordType.expense, '美团外卖-午餐'), 'food');
      expect(mapCategoryId(RecordType.expense, '滴滴出行'), 'transport');
      expect(mapCategoryId(RecordType.expense, '淘宝-天猫订单'), 'shopping');
      expect(mapCategoryId(RecordType.expense, 'XX医院挂号'), 'medical');
      expect(mapCategoryId(RecordType.expense, '房租'), 'housing');
      expect(mapCategoryId(RecordType.expense, '转账-张三'), 'transfer_out');
    });

    test('未命中返回 null', () {
      expect(mapCategoryId(RecordType.expense, '奇奇怪怪的店铺xyz'), isNull);
      expect(mapCategoryId(RecordType.expense, ''), isNull);
    });
  });

  group('收入关键词映射', () {
    test('工资/退款/红包', () {
      expect(mapCategoryId(RecordType.income, '公司-工资'), 'salary');
      expect(mapCategoryId(RecordType.income, '退款-某某网店'), 'refund');
      expect(mapCategoryId(RecordType.income, '微信红包'), 'redpacket');
    });
  });

  test('兜底分类', () {
    expect(fallbackCategoryId(RecordType.expense), 'expense_other');
    expect(fallbackCategoryId(RecordType.income), 'income_other');
  });
}
