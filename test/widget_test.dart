// 「流水账」应用测试：冒烟 + 手动记账流程（S3）

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bill_record_app/data/record_store.dart';
import 'package:bill_record_app/main.dart';
import 'package:bill_record_app/models/record.dart';

void main() {
  setUp(() {
    RecordStore.instance.clearForTest();
  });

  testWidgets('应用启动冒烟测试', (WidgetTester tester) async {
    await tester.pumpWidget(const LiuShuiZhangApp());
    await tester.pump();

    expect(find.text('流水账'), findsOneWidget);
    expect(find.text('账单流水'), findsOneWidget);
    expect(find.text('我的'), findsOneWidget);
    expect(find.text('还没有账单，点右下角 ＋ 记一笔吧'), findsOneWidget);
  });

  testWidgets('底部导航可切换到「我的」页：账户卡片与设置入口就位', (WidgetTester tester) async {
    await tester.pumpWidget(const LiuShuiZhangApp());
    await tester.pump();

    await tester.tap(find.text('我的'));
    await tester.pumpAndSettle();

    // 账户卡片
    expect(find.text('微信支付'), findsOneWidget);
    expect(find.text('支付宝'), findsOneWidget);
    expect(find.text('已绑定'), findsNWidgets(2));
    // 设置入口
    expect(find.text('导入账单文件'), findsOneWidget);
    expect(find.text('通知自动记账'), findsOneWidget);
    // 旧空态文案应已消失
    expect(find.text('这里将显示绑定的账户'), findsNothing);
  });

  testWidgets('手动记账流程：记一笔支出 → 出现在列表与汇总', (WidgetTester tester) async {
    await tester.pumpWidget(const LiuShuiZhangApp());
    await tester.pump();

    // 打开记一笔页
    await tester.tap(find.byKey(const Key('fab_add')));
    await tester.pumpAndSettle();
    expect(find.text('记一笔'), findsOneWidget);

    // 输入金额 12.5
    await tester.enterText(find.byKey(const Key('amount_field')), '12.5');
    // 选中"餐饮"分类
    await tester.tap(find.byKey(const Key('cat_food')));
    // 保存
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();

    // 回到主页：列表 -¥12.50 一条；汇总：支出 ¥12.50、结余 -¥12.50（列表+结余同文本共2处）
    expect(find.text('-¥12.50'), findsNWidgets(2));
    expect(find.text('¥12.50'), findsOneWidget); // 汇总条支出
    expect(find.text('还没有账单，点右下角 ＋ 记一笔吧'), findsNothing);

    // 数据落库
    final q = RecordStore.instance.query(const RecordQuery());
    expect(q.records.length, 1);
    expect(q.records.first.amountCents, 1250);
    expect(q.records.first.type, RecordType.expense);
    expect(q.records.first.categoryId, 'food');
  });

  testWidgets('金额为空时点保存 → 提示不保存', (WidgetTester tester) async {
    await tester.pumpWidget(const LiuShuiZhangApp());
    await tester.pump();

    await tester.tap(find.byKey(const Key('fab_add')));
    await tester.pumpAndSettle();

    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();

    expect(find.text('请输入有效金额'), findsOneWidget);
    expect(RecordStore.instance.query(const RecordQuery()).records, isEmpty);
  });

  testWidgets('筛选联动：账户/收支 chips 过滤列表与汇总', (WidgetTester tester) async {
    // 预置三条"今天"的记录：微信支出12.5 / 微信收入100 / 支付宝支出30
    final today = DateTime.now();
    final store = RecordStore.instance;
    store.add(Record(
      id: 'r1', accountId: 'acc_wechat', source: RecordSource.manual,
      type: RecordType.expense, amountCents: 1250, time: today,
      categoryId: 'food', status: RecordStatus.confirmed,
    ));
    store.add(Record(
      id: 'r2', accountId: 'acc_wechat', source: RecordSource.manual,
      type: RecordType.income, amountCents: 10000, time: today,
      categoryId: 'salary', status: RecordStatus.confirmed,
    ));
    store.add(Record(
      id: 'r3', accountId: 'acc_alipay', source: RecordSource.manual,
      type: RecordType.expense, amountCents: 3000, time: today,
      categoryId: 'shopping', status: RecordStatus.confirmed,
    ));

    await tester.pumpWidget(const LiuShuiZhangApp());
    await tester.pump();

    // 默认（本月/全部账户/收支）：三条都在，汇总 支出42.50 收入100.00 结余57.50
    expect(find.text('-¥12.50'), findsOneWidget);
    expect(find.text('-¥30.00'), findsOneWidget);
    expect(find.text('+¥100.00'), findsOneWidget);
    expect(find.text('¥42.50'), findsOneWidget);
    expect(find.text('¥57.50'), findsOneWidget);

    // 仅支出 → 收入记录消失，结余 = -42.50
    await tester.tap(find.byKey(const Key('type_expense')));
    await tester.pumpAndSettle();
    expect(find.text('+¥100.00'), findsNothing);
    expect(find.text('-¥42.50'), findsOneWidget);

    // 加选微信账户 → 只剩微信支出 12.50（列表行与结余同文本，共 2 处）
    await tester.tap(find.byKey(const Key('acc_acc_wechat')));
    await tester.pumpAndSettle();
    expect(find.text('-¥12.50'), findsNWidgets(2));
    expect(find.text('-¥30.00'), findsNothing);

    // 恢复收支 → 微信两条回来
    await tester.tap(find.byKey(const Key('type_all')));
    await tester.pumpAndSettle();
    expect(find.text('+¥100.00'), findsOneWidget);
    expect(find.text('¥87.50'), findsOneWidget); // 结余 87.50
  });
}
