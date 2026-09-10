import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app_theme.dart';
import 'data/category_store.dart';
import 'data/record_store.dart';
import 'pages/root_shell.dart';
import 'services/notify/notify_platform.dart';
import 'services/notify/notify_queue.dart';
import 'utils/app_log.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // 启动时恢复本地数据（含定期清理检查）
  await RecordStore.instance.init();
  // 分类配置（自定义分类 + 内置停用）
  await CategoryStore.instance.init();
  // 真机：自愈监听绑定（荣耀等 ROM 杀进程后不会自动重绑 NotificationListenerService，
  // 启动时 toggle 服务组件触发系统重新绑定；Web/其它平台自动跳过）
  await _ensureListenerBound();
  // 方案 B：保活开关开着则拉起前台保活服务（进程常驻 → 监听绑定不断）
  await NotifyPlatform.startKeepAliveIfEnabled();
  // 真机：补拉原生"通知暂存队列"（通知到达时 App 未运行，先落盘，此处补拉入库）
  await _drainQueueOnce();
  runApp(const LiuShuiZhangApp());
}

/// 自愈：Android 上禁用再启用监听服务组件 → 系统重新绑定。
/// 绑定正常时无害（仅重连一次）；失联时恢复监听。
Future<void> _ensureListenerBound() async {
  try {
    await const MethodChannel('lsz_notify').invokeMethod('selfHealListener');
  } catch (_) {
    // 非 Android（无该通道）或调用失败：忽略，不影响启动
  }
}

Future<void> _drainQueueOnce() async {
  try {
    final added = await drainNotifyQueue();
    if (added > 0) {
      debugLog('[notify] 补拉通知队列：$added 条进入待确认');
    }
  } catch (e) {
    debugLog('[notify] 队列补拉失败（非致命）: $e');
  }
  // 待确认治理：防无限堆积（超时自动入账 + 容量兜底）
  try {
    final n = await RecordStore.instance.tidyPending();
    if (n > 0) {
      debugLog('[notify] 待确认自动入账：$n 条（未分类，可稍后编辑）');
    }
  } catch (e) {
    debugLog('[notify] 待确认治理失败（非致命）: $e');
  }
}

/// 「流水账」入口
class LiuShuiZhangApp extends StatefulWidget {
  const LiuShuiZhangApp({super.key});

  @override
  State<LiuShuiZhangApp> createState() => _LiuShuiZhangAppState();
}

class _LiuShuiZhangAppState extends State<LiuShuiZhangApp>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // 回前台时补拉：用户在微信/支付宝完成交易后切回本 App 即触发入库
    if (state == AppLifecycleState.resumed) {
      _drainQueueOnce();
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '流水账',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      home: const RootShell(),
    );
  }
}
