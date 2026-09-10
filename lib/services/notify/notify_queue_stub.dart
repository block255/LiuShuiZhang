/// 非 Android 平台：无原生通知队列，恒为空操作。
Future<int> drainNotifyQueue() async => 0;
