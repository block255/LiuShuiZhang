import 'package:bill_record_app/data/record_store.dart';
import 'package:bill_record_app/main.dart';
import 'package:bill_record_app/models/record.dart';
import 'package:bill_record_app/pages/pending_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Record _pending(String id,
        {String acc = 'acc_wechat',
        int cents = 370,
        RecordType type = RecordType.expense,
        String? counterpart}) =>
    Record(
      id: id,
      accountId: acc,
      source: RecordSource.notify,
      type: type,
      amountCents: cents,
      time: DateTime.now(),
      counterpart: counterpart,
      status: RecordStatus.pending,
    );

void main() {
  setUp(() {
    RecordStore.instance.clearForTest();
  });

  Future<void> pumpHome(WidgetTester tester) async {
    await tester.pumpWidget(const LiuShuiZhangApp());
    await tester.pump();
  }

  group('主页待确认横幅', () {
    testWidgets('有待确认时显示横幅，点击进入待确认页', (tester) async {
      RecordStore.instance.add(_pending('p1'));
      RecordStore.instance.add(Record(
        id: 'c1',
        accountId: 'acc_wechat',
        source: RecordSource.manual,
        type: RecordType.expense,
        amountCents: 1000,
        time: DateTime.now(),
        status: RecordStatus.confirmed,
      ));
      await pumpHome(tester);

      expect(find.byKey(const Key('pending_banner')), findsOneWidget);
      expect(find.text('有 1 条待确认的通知'), findsOneWidget);

      await tester.tap(find.byKey(const Key('pending_banner')));
      await tester.pumpAndSettle();
      expect(find.text('待确认 (1)'), findsOneWidget);
      expect(find.text('-¥3.70'), findsOneWidget);
    });

    testWidgets('无待确认时不显示横幅', (tester) async {
      RecordStore.instance.add(Record(
        id: 'c1',
        accountId: 'acc_wechat',
        source: RecordSource.manual,
        type: RecordType.expense,
        amountCents: 1000,
        time: DateTime.now(),
        status: RecordStatus.confirmed,
      ));
      await pumpHome(tester);
      expect(find.byKey(const Key('pending_banner')), findsNothing);
    });
  });

  group('待确认页动作', () {
    testWidgets('行尾✓单条确认：入账后从待确认消失', (tester) async {
      RecordStore.instance.add(_pending('p1'));
      RecordStore.instance.add(_pending('p2', cents: 5000, type: RecordType.income, acc: 'acc_alipay'));
      await tester.pumpWidget(const MaterialApp(home: PendingPage()));
      await tester.pump();

      expect(find.text('待确认 (2)'), findsOneWidget);
      await tester.tap(find.byKey(const Key('pending_confirm_p1')));
      await tester.pumpAndSettle();

      expect(RecordStore.instance.pending().records, hasLength(1));
      expect(RecordStore.instance.pending().records.single.id, 'p2');
      final confirmed = RecordStore.instance.all
          .where((r) => r.status == RecordStatus.confirmed)
          .single;
      expect(confirmed.id, 'p1');
      expect(find.text('待确认 (1)'), findsOneWidget);
    });

    testWidgets('全部确认：pending 全部入账，页面变空态', (tester) async {
      RecordStore.instance.add(_pending('p1'));
      RecordStore.instance.add(_pending('p2', cents: 5000, type: RecordType.income));
      await tester.pumpWidget(const MaterialApp(home: PendingPage()));
      await tester.pump();

      await tester.tap(find.byKey(const Key('pending_confirm_all')));
      await tester.pumpAndSettle();

      expect(RecordStore.instance.pending().records, isEmpty);
      expect(RecordStore.instance.all, hasLength(2));
      expect(RecordStore.instance.all.every(
          (r) => r.status == RecordStatus.confirmed),
          isTrue);
      expect(find.text('没有待确认的通知了'), findsOneWidget);
    });

    testWidgets('点击行 → 编辑页补对方 → 保存后仍待确认且对方更新', (tester) async {
      RecordStore.instance.add(_pending('p1'));
      await tester.pumpWidget(const MaterialApp(home: PendingPage()));
      await tester.pump();

      await tester.tap(find.byKey(const Key('pending_row_p1')));
      await tester.pumpAndSettle();

      expect(find.text('编辑账单'), findsOneWidget);
      await tester.enterText(
          find.byKey(const Key('counterpart_field')), '水果店');
      await tester.tap(find.text('保存'));
      await tester.pumpAndSettle();

      final r = RecordStore.instance.all.single;
      expect(r.counterpart, '水果店');
      expect(r.status, RecordStatus.pending); // 编辑不改变待确认状态
      expect(find.text('水果店'), findsOneWidget); // 列表行显示新对方
    });

    testWidgets('删除待确认：确认对话框后物理删除', (tester) async {
      RecordStore.instance.add(_pending('p1'));
      await tester.pumpWidget(const MaterialApp(home: PendingPage()));
      await tester.pump();

      await tester.longPress(find.byKey(const Key('pending_row_p1')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('pending_menu_delete')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('pending_delete_confirm')));
      await tester.pumpAndSettle();

      expect(RecordStore.instance.all, isEmpty);
      expect(find.text('没有待确认的通知了'), findsOneWidget);
    });

    testWidgets('批量模式：勾选后批量确认', (tester) async {
      RecordStore.instance.add(_pending('p1'));
      RecordStore.instance.add(_pending('p2', cents: 5000, type: RecordType.income));
      await tester.pumpWidget(const MaterialApp(home: PendingPage()));
      await tester.pump();

      await tester.tap(find.byKey(const Key('pending_bulk_enter')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('pending_bulk_select_all')));
      await tester.pump();
      await tester.tap(find.byKey(const Key('pending_bulk_confirm')));
      await tester.pumpAndSettle();

      expect(RecordStore.instance.pending().records, isEmpty);
      expect(RecordStore.instance.all, hasLength(2));
    });
  });
}
