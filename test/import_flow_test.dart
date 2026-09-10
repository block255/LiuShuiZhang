import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bill_record_app/data/record_store.dart';
import 'package:bill_record_app/models/record.dart';
import 'package:bill_record_app/pages/import_page.dart';

import 'fixtures/samples.dart';

/// 测试壳：提供可 push 的导航上下文
class _Host extends StatelessWidget {
  final String accountId;
  final String? csv;

  const _Host({required this.accountId, this.csv});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (ctx) => Center(
            child: TextButton(
              key: const Key('go_import'),
              onPressed: () {
                Navigator.of(ctx).push(MaterialPageRoute(
                  builder: (_) => ImportPage(
                      accountId: accountId, initialCsv: csv),
                ));
              },
              child: const Text('打开导入页'),
            ),
          ),
        ),
      ),
    );
  }
}

void main() {
  setUp(() {
    RecordStore.instance.clearForTest();
  });

  testWidgets('微信账单导入：预览统计 → 确认入库 → 记录带来源与分类', (tester) async {
    await tester.pumpWidget(const _Host(accountId: 'acc_wechat', csv: wechatBillCsv));
    await tester.tap(find.byKey(const Key('go_import')));
    await tester.pumpAndSettle();

    // 预览：识别 5 条
    expect(find.text('识别'), findsOneWidget);
    expect(find.text('5'), findsOneWidget);
    expect(find.text('确认导入 5 条'), findsOneWidget);
    // 预览含沙县小吃
    expect(find.text('沙县小吃'), findsOneWidget);

    await tester.tap(find.byKey(const Key('confirm_import_btn')));
    await tester.pumpAndSettle();

    final q = RecordStore.instance.query(const RecordQuery());
    expect(q.records.length, 5);
    // 分类映射生效：沙县小吃 → food
    final shaXian = q.records.firstWhere((r) => r.counterpart == '沙县小吃');
    expect(shaXian.categoryId, 'food');
    expect(shaXian.source, RecordSource.import);
    expect(shaXian.accountId, 'acc_wechat');
    expect(shaXian.orderId, isNotNull);
  });

  testWidgets('重复导入同一文件：全部按单号去重跳过', (tester) async {
    await tester.pumpWidget(const _Host(accountId: 'acc_wechat', csv: wechatBillCsv));
    await tester.tap(find.byKey(const Key('go_import')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('confirm_import_btn')));
    await tester.pumpAndSettle();
    expect(RecordStore.instance.query(const RecordQuery()).records.length, 5);

    // 再次导入同一文件 → 预览显示重复 5
    await tester.tap(find.byKey(const Key('go_import')));
    await tester.pumpAndSettle();
    expect(find.text('确认导入 5 条'), findsOneWidget);
    await tester.tap(find.byKey(const Key('confirm_import_btn')));
    await tester.pumpAndSettle();

    // 库仍 5 条（重复被跳过）
    expect(RecordStore.instance.query(const RecordQuery()).records.length, 5);
  });

  testWidgets('支付宝账单导入到支付宝账户', (tester) async {
    await tester.pumpWidget(const _Host(accountId: 'acc_alipay', csv: alipayBillCsv));
    await tester.tap(find.byKey(const Key('go_import')));
    await tester.pumpAndSettle();

    expect(find.text('确认导入 4 条'), findsOneWidget);
    await tester.tap(find.byKey(const Key('confirm_import_btn')));
    await tester.pumpAndSettle();

    final q = RecordStore.instance.query(const RecordQuery());
    expect(q.records.length, 4);
    expect(q.records.every((r) => r.accountId == 'acc_alipay'), isTrue);
    // 工资 5000 收入
    final salary = q.records.firstWhere((r) => r.counterpart == '公司');
    expect(salary.type, RecordType.income);
    expect(salary.amountCents, 500000);
  });
}
