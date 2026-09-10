import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bill_record_app/data/record_store.dart';
import 'package:bill_record_app/main.dart';
import 'package:bill_record_app/models/record.dart';

Record _mk(String id, {int cents = 1250, String? note}) => Record(
      id: id,
      accountId: 'acc_wechat',
      source: RecordSource.manual,
      type: RecordType.expense,
      amountCents: cents,
      time: DateTime.now(),
      categoryId: 'food',
      counterpart: '沙县小吃',
      note: note,
      status: RecordStatus.confirmed,
    );

void main() {
  setUp(() {
    RecordStore.instance.clearForTest();
  });

  Future<void> pumpHome(WidgetTester tester) async {
    await tester.pumpWidget(const LiuShuiZhangApp());
    await tester.pump();
  }

  group('长按菜单', () {
    testWidgets('长按记录行弹出操作菜单', (tester) async {
      RecordStore.instance.add(_mk('r1'));
      await pumpHome(tester);

      await tester.longPress(find.byKey(const Key('record_r1')));
      await tester.pumpAndSettle();

      expect(find.text('编辑'), findsOneWidget);
      expect(find.text('删除'), findsOneWidget);
      expect(find.text('批量选择'), findsOneWidget);
    });

    testWidgets('菜单→编辑：预填原值，保存后更新入库', (tester) async {
      RecordStore.instance.add(_mk('r1'));
      await pumpHome(tester);

      await tester.longPress(find.byKey(const Key('record_r1')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('编辑'));
      await tester.pumpAndSettle();

      // 编辑页标题 + 预填金额 12.5
      expect(find.text('编辑账单'), findsOneWidget);
      expect(find.text('12.5'), findsOneWidget);

      // 改为 20 保存
      await tester.enterText(find.byKey(const Key('amount_field')), '20');
      await tester.tap(find.text('保存'));
      await tester.pumpAndSettle();

      final r = RecordStore.instance.all.single;
      expect(r.amountCents, 2000);
      expect(find.text('-¥20.00'), findsWidgets); // 列表与结余
    });

    testWidgets('菜单→删除：确认后记录消失', (tester) async {
      RecordStore.instance.add(_mk('r1'));
      await pumpHome(tester);

      await tester.longPress(find.byKey(const Key('record_r1')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('删除'));
      await tester.pumpAndSettle();

      // 确认对话框
      expect(find.text('删除这条记录？'), findsOneWidget);
      await tester.tap(find.byKey(const Key('bulk_confirm_delete')));
      await tester.pumpAndSettle();

      expect(RecordStore.instance.all, isEmpty);
      expect(find.byKey(const Key('record_r1')), findsNothing);
    });

    testWidgets('菜单→删除→取消：记录保留', (tester) async {
      RecordStore.instance.add(_mk('r1'));
      await pumpHome(tester);

      await tester.longPress(find.byKey(const Key('record_r1')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('删除'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();

      expect(RecordStore.instance.all.length, 1);
    });

    testWidgets('编辑页直接删除按钮也可删除', (tester) async {
      RecordStore.instance.add(_mk('r1', note: '备注A'));
      await pumpHome(tester);

      await tester.longPress(find.byKey(const Key('record_r1')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('编辑'));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('delete_record_btn')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('confirm_delete_btn')));
      await tester.pumpAndSettle();

      expect(RecordStore.instance.all, isEmpty);
    });
  });

  group('批量管理模式', () {
    testWidgets('批量入口 → 勾选 → 全选 → 批量删除', (tester) async {
      RecordStore.instance.add(_mk('r1'));
      RecordStore.instance.add(_mk('r2', cents: 3000));
      await pumpHome(tester);

      // 进入批量
      await tester.tap(find.byKey(const Key('bulk_enter')));
      await tester.pumpAndSettle();
      expect(find.text('已选 0 项'), findsOneWidget);

      // 点一行勾选
      await tester.tap(find.byKey(const Key('record_r1')));
      await tester.pumpAndSettle();
      expect(find.text('已选 1 项'), findsWidgets);

      // 全选 → 2 项
      await tester.tap(find.byKey(const Key('bulk_select_all')));
      await tester.pumpAndSettle();
      expect(find.text('已选 2 项'), findsWidgets);

      // 批量删除
      await tester.tap(find.text('删除 2'));
      await tester.pumpAndSettle();
      expect(find.text('删除选中的 2 条记录？'), findsOneWidget);
      await tester.tap(find.byKey(const Key('bulk_confirm_delete')));
      await tester.pumpAndSettle();

      expect(RecordStore.instance.all, isEmpty);
      expect(find.text('已删除 2 条记录'), findsOneWidget); // SnackBar
      // 退出批量模式
      expect(find.byKey(const Key('bulk_bar')), findsNothing);
    });

    testWidgets('批量删除取消：记录保留并退出可继续勾选', (tester) async {
      RecordStore.instance.add(_mk('r1'));
      RecordStore.instance.add(_mk('r2', cents: 3000));
      await pumpHome(tester);

      await tester.tap(find.byKey(const Key('bulk_enter')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('record_r1')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('删除 1'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();

      expect(RecordStore.instance.all.length, 2);
      expect(find.text('已选 1 项'), findsWidgets); // 仍在批量模式且保留选择

      // 关闭退出
      await tester.tap(find.byKey(const Key('bulk_exit')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('bulk_bar')), findsNothing);
      expect(find.text('流水账'), findsOneWidget);
    });

    testWidgets('无数据时无批量入口', (tester) async {
      await pumpHome(tester);
      expect(find.byKey(const Key('bulk_enter')), findsNothing);
    });
  });
}
