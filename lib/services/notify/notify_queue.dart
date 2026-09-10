import 'notify_queue_stub.dart'
    if (dart.library.io) 'notify_queue_io.dart' as impl;

/// 从原生"通知暂存队列"补拉通知并入库（App 启动/回前台时调用）。
///
/// 通知到达时 App 可能不在运行：原生 NotificationListenerService 先把
/// 通知字段落盘（notify_queue.json），App 起来后在此补拉 → NotifyIngest
/// 逐条解析入库（与模拟面板同一条链路）。
///
/// 返回本次新增进入待确认(pending)的条数（Web/其它平台恒为 0）。
Future<int> drainNotifyQueue() => impl.drainNotifyQueue();
