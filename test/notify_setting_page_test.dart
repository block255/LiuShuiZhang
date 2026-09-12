// 「通知自动记账」设置页：后台运行权限（电池优化白名单）自检（2026-09-12）
//
// 背景：荣耀上 ROM 的「应用启动管理」与 AOSP 的「电池优化白名单」是两套独立机制，
// 只开前者时后台仍可能收不到通知（真机实测）。这里保证 UI 能正确反映状态并一键引导。

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bill_record_app/data/record_store.dart';
import 'package:bill_record_app/main.dart';

void main() {
  const channel = MethodChannel('lsz_notify');
  final calls = <String>[];
  var batteryOk = false;

  setUp(() {
    RecordStore.instance.clearForTest();
    calls.clear();
    batteryOk = false;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      calls.add(call.method);
      switch (call.method) {
        case 'getListenerEnabled':
          return true;
        case 'getKeepAlive':
          return true;
        case 'isIgnoringBatteryOptimizations':
          return batteryOk;
        case 'checkListenerHealth':
          return 'ok';
        case 'selfHealListener':
          return 'healed';
        default:
          return null;
      }
    });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  Future<void> openPage(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1000, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(const LiuShuiZhangApp());
    await tester.pump();
    await tester.tap(find.text('我的'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('set_notify')));
    await tester.pumpAndSettle();
  }

  testWidgets('未允许后台运行：显示警告文案，点击后请求系统授权', (WidgetTester tester) async {
    await openPage(tester);

    expect(find.byKey(const Key('notify_setting_battery')), findsOneWidget);
    expect(find.text('后台运行权限'), findsOneWidget);
    expect(find.textContaining('未允许'), findsOneWidget);
    expect(calls.contains('isIgnoringBatteryOptimizations'), isTrue);

    await tester.tap(find.byKey(const Key('notify_setting_battery')));
    await tester.pumpAndSettle();
    expect(calls.contains('requestIgnoreBatteryOptimizations'), isTrue);
  });

  testWidgets('已允许后台运行：显示已允许，不再请求授权', (WidgetTester tester) async {
    batteryOk = true;
    await openPage(tester);

    expect(find.textContaining('已允许'), findsOneWidget);
    expect(find.textContaining('未允许'), findsNothing);

    await tester.tap(find.byKey(const Key('notify_setting_battery')));
    await tester.pumpAndSettle();
    expect(calls.contains('requestIgnoreBatteryOptimizations'), isFalse);
  });

  testWidgets('非安卓（通道报错）时不崩溃', (WidgetTester tester) async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      throw MissingPluginException('no android');
    });
    await openPage(tester);
    // 页面仍应渲染，且不出现异常
    expect(find.text('通知自动记账'), findsWidgets);
  });
}
