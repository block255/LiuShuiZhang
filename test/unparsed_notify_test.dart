// 方案 C「未识别通知」留痕（2026-09-29）：
//  - 留痕存储：原生文件经 lsz_notify 通道读写，Web/桌面退化为内存日志
//  - 页面：查看 + 单条复制 + 复制全部（发给开发者补规则）+ 清空
//
// 背景：12 天里漏了两类通知（支付宝被扫、支付宝退款），以前只能靠用户截图通知栏；
// 现在 App 自带清单，可直接复制上报。

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bill_record_app/pages/unparsed_notify_page.dart';
import 'package:bill_record_app/services/notify/notify_log.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('lsz_notify');
  final calls = <MethodCall>[];
  String fileContent = '[]';
  String? clipboard;

  void mockChannel({bool absent = false}) {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, absent
            ? null
            : (call) async {
                calls.add(call);
                switch (call.method) {
                  case 'readUnparsedLog':
                    return fileContent;
                  case 'appendUnparsedLog':
                  case 'clearUnparsedLog':
                    return true;
                  default:
                    return null;
                }
              });
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') {
        clipboard = (call.arguments as Map)['text'] as String?;
      }
      return null;
    });
  }

  setUp(() {
    calls.clear();
    fileContent = '[]';
    clipboard = null;
    NotifyLogStore.instance.resetForTest();
    mockChannel();
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
    NotifyLogStore.instance.resetForTest();
  });

  Map<String, dynamic> nativeEntry({
    required int ms,
    String title = '退款提醒',
    String text = '你收到一笔1231.80元退款，点此查看账单详情！',
    String pkg = 'com.eg.android.AlipayGphone',
  }) =>
      {
        'time': ms,
        'source': 'native',
        'pkg': pkg,
        'title': title,
        'text': text,
        'reason': '标题不含支付关键词，未自动记账',
      };

  group('NotifyLogStore 留痕存储', () {
    test('读取原生留痕：倒序展示 + 来源识别', () async {
      final old = DateTime(2026, 9, 27, 10, 0).millisecondsSinceEpoch;
      final now = DateTime(2026, 9, 28, 9, 59).millisecondsSinceEpoch;
      fileContent = jsonEncode([
        nativeEntry(ms: old, title: '支付成功通知'),
        nativeEntry(ms: now),
      ]);

      await NotifyLogStore.instance.load();

      final entries = NotifyLogStore.instance.entries;
      expect(entries, hasLength(2));
      expect(entries.first.time.millisecondsSinceEpoch, now); // 最新在前
      expect(entries.first.platformName, '支付宝');
      expect(entries.first.sourceName, '未放行');
      expect(NotifyLogStore.instance.persistent, isTrue);
    });

    test('通道不可用（Web/桌面）→ 退化为内存日志，不抛异常', () async {
      mockChannel(absent: true);
      await NotifyLogStore.instance.load();
      expect(NotifyLogStore.instance.count, 0);
      expect(NotifyLogStore.instance.persistent, isFalse);

      NotifyLogStore.instance
          .add(NotifyLogEntry(time: DateTime(2026, 9, 29), reason: '无法识别'));
      expect(NotifyLogStore.instance.count, 1); // 内存仍可用
    });

    test('追加一条 → 内存即时生效 + 原生落盘内容可解析', () async {
      await NotifyLogStore.instance.load(); // 建立持久化能力
      final entry = NotifyLogEntry(
        time: DateTime(2026, 9, 29, 10, 30),
        source: 'parser',
        pkg: 'com.tencent.mm',
        accountId: 'acc_wechat',
        title: '微信支付',
        text: '纯文本无方向无金额',
        reason: '无法识别收支方向，需人工补规则',
      );
      NotifyLogStore.instance.add(entry);
      expect(NotifyLogStore.instance.count, 1);

      await Future<void>.delayed(Duration.zero); // 等异步落盘
      final append = calls.firstWhere((c) => c.method == 'appendUnparsedLog');
      final payload =
          jsonDecode((append.arguments as Map)['entry'] as String) as Map;
      expect(payload['source'], 'parser');
      expect(payload['pkg'], 'com.tencent.mm');
      expect(payload['title'], '微信支付');
      expect(payload['reason'], contains('无法识别收支方向'));
    });

    test('环形上限：超过 100 条丢最旧', () async {
      await NotifyLogStore.instance.load();
      for (var i = 0; i < 105; i++) {
        NotifyLogStore.instance.add(NotifyLogEntry(
          time: DateTime(2026, 9, 29, 0, 0).add(Duration(minutes: i)),
          reason: '第 $i 条',
        ));
      }
      expect(NotifyLogStore.instance.count, NotifyLogStore.maxEntries);
      // 最新的一条（第 104 条）在最前，最旧的 5 条已被丢弃
      expect(NotifyLogStore.instance.entries.first.reason, '第 104 条');
      expect(
        NotifyLogStore.instance.entries.map((e) => e.reason),
        isNot(contains('第 0 条')),
      );
    });

    test('清空 → 内存清空并通知原生删除', () async {
      await NotifyLogStore.instance.load();
      NotifyLogStore.instance
          .add(NotifyLogEntry(time: DateTime(2026, 9, 29), reason: 'x'));
      NotifyLogStore.instance.clear();
      expect(NotifyLogStore.instance.count, 0);

      await Future<void>.delayed(Duration.zero);
      expect(calls.any((c) => c.method == 'clearUnparsedLog'), isTrue);
    });

    test('原生内容损坏 → 不崩溃（保持空列表）', () async {
      fileContent = '{broken json';
      await NotifyLogStore.instance.load();
      expect(NotifyLogStore.instance.count, 0);
    });
  });

  group('UnparsedNotifyPage 页面', () {
    Future<void> pumpPage(WidgetTester tester) async {
      tester.view.physicalSize = const Size(1000, 2000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(const MaterialApp(home: UnparsedNotifyPage()));
      await tester.pumpAndSettle();
    }

    testWidgets('无记录 → 空状态', (tester) async {
      await pumpPage(tester);
      expect(find.textContaining('暂无未识别通知'), findsOneWidget);
    });

    testWidgets('有记录 → 展示原文与来源，复制全部写入剪贴板', (tester) async {
      // 走真实路径：原生文件里已有留痕 → 页面 load() 后展示
      fileContent = jsonEncode([
        nativeEntry(ms: DateTime(2026, 9, 28, 9, 59).millisecondsSinceEpoch),
      ]);
      await pumpPage(tester);

      expect(find.text('退款提醒 ｜ 你收到一笔1231.80元退款，点此查看账单详情！'),
          findsOneWidget);
      expect(find.text('支付宝'), findsOneWidget);
      expect(find.text('未放行'), findsOneWidget);

      await tester.tap(find.byKey(const Key('unparsed_copy_all')));
      await tester.pumpAndSettle();
      expect(clipboard, isNotNull);
      expect(clipboard, contains('【流水账·未识别通知】共 1 条'));
      expect(clipboard, contains('退款提醒'));
      expect(clipboard, contains('1231.80'));
    });

    testWidgets('清空需确认，确认后列表为空', (tester) async {
      fileContent = jsonEncode([
        nativeEntry(
          ms: DateTime(2026, 9, 28, 9, 59).millisecondsSinceEpoch,
          title: '积分提醒',
          text: '你的会员积分即将过期',
        ),
      ]);
      await pumpPage(tester);
      expect(NotifyLogStore.instance.count, 1);

      await tester.tap(find.byKey(const Key('unparsed_clear')));
      await tester.pumpAndSettle();
      expect(find.textContaining('清空 1 条未识别记录'), findsOneWidget);

      await tester.tap(find.byKey(const Key('unparsed_clear_confirm')));
      await tester.pumpAndSettle();
      expect(NotifyLogStore.instance.count, 0);
      expect(find.textContaining('暂无未识别通知'), findsOneWidget);
    });
  });
}
