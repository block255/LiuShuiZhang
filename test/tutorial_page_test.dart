// 「使用教程」页测试（2026-09-10）
//
// 覆盖：设置区入口（第一行）→ 跳转 → 页面结构（总览卡 + 8 折叠分区）
// → 折叠交互（① 默认展开 / 其余需点击）→ 快捷按钮跳「通知自动记账」

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bill_record_app/data/record_store.dart';
import 'package:bill_record_app/main.dart';

/// 教程内容较长：加高测试视口，避免折叠分区因未进入可见范围而未构建
void _tallView(WidgetTester tester) {
  tester.view.physicalSize = const Size(1000, 3200);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
}

/// 启动应用 → 切到「我的」→ 点开使用教程
Future<void> _openTutorial(WidgetTester tester) async {
  _tallView(tester);
  await tester.pumpWidget(const LiuShuiZhangApp());
  await tester.pump();
  await tester.tap(find.text('我的'));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const Key('set_tutorial')));
  await tester.pumpAndSettle();
}

void main() {
  setUp(() {
    RecordStore.instance.clearForTest();
  });

  testWidgets('「我的」设置区含使用教程入口（第一项）', (WidgetTester tester) async {
    _tallView(tester);
    await tester.pumpWidget(const LiuShuiZhangApp());
    await tester.pump();
    await tester.tap(find.text('我的'));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('set_tutorial')), findsOneWidget);
    expect(find.text('使用教程'), findsOneWidget);
    expect(find.text('三条记账途径怎么配合、常见问题'), findsOneWidget);
  });

  testWidgets('教程页：总览卡 + 8 个分区标题就位', (WidgetTester tester) async {
    await _openTutorial(tester);

    // 顶部总览卡（常显）
    expect(find.text('三条途径怎么配合'), findsOneWidget);
    expect(find.text('自动监听（日常主力）'), findsOneWidget);
    expect(find.text('导入账单（每月兜底）'), findsOneWidget);
    expect(find.text('手动记录（随手补）'), findsOneWidget);

    // 8 个分区
    expect(find.text('① 三条途径怎么配合'), findsOneWidget);
    expect(find.text('② 第一次使用（三步）'), findsOneWidget);
    expect(find.text('③ 自动监听怎么用'), findsOneWidget);
    expect(find.text('④ 导入账单'), findsOneWidget);
    expect(find.text('⑤ 手动记录与查看账单'), findsOneWidget);
    expect(find.text('⑥ 分类管理'), findsOneWidget);
    expect(find.text('⑦ 备份与恢复'), findsOneWidget);
    expect(find.text('⑧ 常见问题'), findsOneWidget);
  });

  testWidgets('第①节默认展开（含盲区提醒）；其余折叠，点击可展开',
      (WidgetTester tester) async {
    await _openTutorial(tester);

    // ① 展开：三条途径说明 + 盲区提醒可见
    expect(find.textContaining('覆盖微信支付、微信收款到账'), findsOneWidget);
    expect(find.textContaining('支付宝「被扫」付款'), findsOneWidget);
    expect(find.textContaining('微信群里收发红包'), findsOneWidget);

    // ④ 折叠：其内容不可见
    expect(find.textContaining('开具交易流水证明'), findsNothing);

    // 点击 ④ 标题 → 展开
    await tester.tap(find.text('④ 导入账单'));
    await tester.pumpAndSettle();
    expect(find.textContaining('开具交易流水证明'), findsOneWidget);
  });

  testWidgets('第②节快捷按钮：跳到「通知自动记账」页', (WidgetTester tester) async {
    await _openTutorial(tester);

    expect(find.byKey(const Key('tutorial_go_notify')), findsNothing);

    await tester.tap(find.text('② 第一次使用（三步）'));
    await tester.pumpAndSettle();

    // 划掉不影响记账的新文案（2026-09-10 实测结论）
    expect(find.textContaining('从最近任务里划掉软件不影响记账'), findsOneWidget);

    await tester.tap(find.byKey(const Key('tutorial_go_notify')));
    await tester.pumpAndSettle();
    expect(find.text('通知自动记账'), findsWidgets); // 目标页 AppBar
  });

  testWidgets('常见问题区可展开并含关键问答', (WidgetTester tester) async {
    await _openTutorial(tester);

    await tester.tap(find.text('⑧ 常见问题'));
    await tester.pumpAndSettle();

    expect(find.text('Q：会不会重复记账？'), findsOneWidget);
    expect(find.text('Q：数据会上传吗？'), findsOneWidget);
    expect(find.textContaining('全部数据只存在你自己手机里'), findsOneWidget);
  });
}
