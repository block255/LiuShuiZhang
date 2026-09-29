import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app_info.dart';
import '../app_theme.dart';
import '../services/notify/notify_log.dart';

/// 「未识别通知」（方案 C，2026-09-29）
///
/// 把"疑似收付款、但没被自动记账"的通知原文摊开给用户看，解决长期存在的
/// **静默漏记**问题：以前通知被拦只会悄无声息地消失（用户只能靠截图通知栏才察觉）。
///
/// 两个来源：
/// - 未放行：原生标题闸门拦下（标题不含支付关键词）
/// - 未解析：放行了但解析器认不出（无方向词 / 无锚定金额 / 含"失败"等无效词）
///
/// 页面提供「复制全部」：导出成可读清单 —— 用户自己留档核对，或在反馈问题时附上。
class UnparsedNotifyPage extends StatefulWidget {
  const UnparsedNotifyPage({super.key});

  @override
  State<UnparsedNotifyPage> createState() => _UnparsedNotifyPageState();
}

class _UnparsedNotifyPageState extends State<UnparsedNotifyPage> {
  @override
  void initState() {
    super.initState();
    // 留痕变化（原生刷新 / 新条目到达）→ 重建列表
    NotifyLogStore.instance.addListener(_onLogChanged);
    // 进页面刷新一次（原生文件可能在本页停留期间新增条目）
    NotifyLogStore.instance.load();
  }

  @override
  void dispose() {
    NotifyLogStore.instance.removeListener(_onLogChanged);
    super.dispose();
  }

  void _onLogChanged() {
    if (mounted) setState(() {});
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(msg), duration: const Duration(seconds: 2)));
  }

  Future<void> _copyOne(NotifyLogEntry e) async {
    await Clipboard.setData(ClipboardData(text: e.toReportLine()));
    _snack('已复制这一条');
  }

  Future<void> _copyAll(List<NotifyLogEntry> list) async {
    if (list.isEmpty) {
      _snack('暂无可复制的内容');
      return;
    }
    final buf = StringBuffer()
      ..writeln('【流水账·未识别通知】共 ${list.length} 条（App ${AppInfo.display}）');
    for (var i = 0; i < list.length; i++) {
      buf.writeln('${i + 1}. ${list[i].toReportLine()}');
    }
    await Clipboard.setData(ClipboardData(text: buf.toString().trimRight()));
    _snack('已复制 ${list.length} 条到剪贴板');
  }

  Future<void> _clearAll() async {
    final n = NotifyLogStore.instance.count;
    if (n == 0) {
      _snack('当前没有记录');
      return;
    }
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('清空 $n 条未识别记录？'),
        content: const Text('清空后不可恢复；建议先「复制全部」留一份。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('取消'),
          ),
          TextButton(
            key: const Key('unparsed_clear_confirm'),
            onPressed: () => Navigator.of(ctx).pop(true),
            style: TextButton.styleFrom(foregroundColor: AppColors.expense),
            child: const Text('清空'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    NotifyLogStore.instance.clear();
    _snack('已清空');
  }

  @override
  Widget build(BuildContext context) {
    final store = NotifyLogStore.instance;
    final list = store.entries;
    return Scaffold(
      appBar: AppBar(
        title: const Text('未识别通知'),
        actions: [
          IconButton(
            key: const Key('unparsed_copy_all'),
            tooltip: '复制全部',
            icon: const Icon(Icons.copy_all_outlined),
            onPressed: () => _copyAll(list),
          ),
          IconButton(
            key: const Key('unparsed_clear'),
            tooltip: '清空',
            icon: const Icon(Icons.delete_outline),
            onPressed: _clearAll,
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // ── 说明 ──
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.primarySoft,
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  Icon(Icons.help_outline, size: 16, color: AppColors.primary),
                  SizedBox(width: 6),
                  Text('这里是什么',
                      style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: AppColors.primary)),
                ]),
                SizedBox(height: 6),
                Text(
                  '记录"看起来像收付款、但没有自动记账"的通知原文，只存本机。\n'
                  '· 未放行：通知标题不在支付关键词里（先拦下来，避免聊天消息打扰）\n'
                  '· 未解析：放行了但认不出金额或收支方向（宁缺毋滥，不乱记账）\n'
                  '用法：对照清单用手动记账补上；需要留档或反馈问题时，'
                  '点右上角「复制全部」导出成文字。',
                  style: TextStyle(
                      fontSize: 12,
                      color: AppColors.textSecondary,
                      height: 1.6),
                ),
              ],
            ),
          ),
          if (!store.persistent) ...[
            const SizedBox(height: 8),
            const Text('（当前平台不保存历史留痕，仅本次会话可见；安卓真机可长期保留 100 条）',
                style: TextStyle(fontSize: 11, color: AppColors.textSecondary)),
          ],
          const SizedBox(height: 16),
          if (list.isEmpty)
            _buildEmpty()
          else ...[
            Text('共 ${list.length} 条（最新在前）',
                style: const TextStyle(
                    fontSize: 13,
                    color: AppColors.textSecondary,
                    fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            for (final e in list) _buildEntry(e),
          ],
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Widget _buildEmpty() {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 40),
      alignment: Alignment.center,
      child: const Column(
        children: [
          Icon(Icons.inbox_outlined, size: 40, color: AppColors.divider),
          SizedBox(height: 10),
          Text('暂无未识别通知 🎉',
              style: TextStyle(fontSize: 13, color: AppColors.textSecondary)),
          SizedBox(height: 4),
          Text('说明收付款通知都被正常处理了',
              style: TextStyle(fontSize: 11, color: AppColors.textSecondary)),
        ],
      ),
    );
  }

  Widget _buildEntry(NotifyLogEntry e) {
    final t = '${e.time.month.toString().padLeft(2, '0')}-'
        '${e.time.day.toString().padLeft(2, '0')} '
        '${e.time.hour.toString().padLeft(2, '0')}:'
        '${e.time.minute.toString().padLeft(2, '0')}';
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.fromLTRB(12, 10, 4, 10),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.divider),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  Text(t,
                      style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: AppColors.textMain)),
                  const SizedBox(width: 8),
                  _tag(e.platformName),
                  const SizedBox(width: 4),
                  _tag(e.sourceName, warn: true),
                ]),
                const SizedBox(height: 4),
                Text(
                  [e.title, e.text].where((s) => s.trim().isNotEmpty).join(' ｜ '),
                  style: const TextStyle(
                      fontSize: 13, color: AppColors.textMain, height: 1.4),
                ),
                const SizedBox(height: 2),
                Text(e.reason,
                    style: const TextStyle(
                        fontSize: 11, color: AppColors.textSecondary)),
              ],
            ),
          ),
          IconButton(
            key: Key('unparsed_copy_${e.time.millisecondsSinceEpoch}'),
            tooltip: '复制这一条',
            icon: const Icon(Icons.copy_outlined,
                size: 18, color: AppColors.textSecondary),
            onPressed: () => _copyOne(e),
          ),
        ],
      ),
    );
  }

  Widget _tag(String text, {bool warn = false}) {
    final color = warn ? AppColors.warn : AppColors.primary;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Text(text,
          style: TextStyle(fontSize: 10, color: color, height: 1.4)),
    );
  }
}
