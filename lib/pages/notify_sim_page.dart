import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app_theme.dart';
import '../models/account.dart';
import '../models/record.dart';
import '../services/notify/notify_ingest.dart';
import '../services/notify/notify_log.dart';
import '../services/notify/notify_models.dart';
import '../services/notify/notify_samples.dart';
import '../utils/money.dart';
import '../utils/record_time.dart';
import '../widgets/account_badge.dart';
import 'pending_page.dart';

/// 模拟通知调试面板（kDebugMode 入口；我的页 → 通知自动记账）
///
/// Web 上没有系统通知，此面板等效替代"真机通知到达"：
/// 选账户 + 填标题/正文（或点样本快捷填充）→ 投递 → 走与真机监听
/// 完全相同的 NotifyIngest 链路，并展示结果与"无法解析日志"。
class NotifySimPage extends StatefulWidget {
  const NotifySimPage({super.key});

  @override
  State<NotifySimPage> createState() => _NotifySimPageState();
}

class _NotifySimPageState extends State<NotifySimPage> {
  String _accountId = Account.wechat.id;
  final _titleCtrl = TextEditingController();
  final _textCtrl = TextEditingController();

  NotifyIngestResult? _lastResult;

  @override
  void initState() {
    super.initState();
    NotifyLogStore.instance.addListener(_onLogChanged);
  }

  @override
  void dispose() {
    NotifyLogStore.instance.removeListener(_onLogChanged);
    _titleCtrl.dispose();
    _textCtrl.dispose();
    super.dispose();
  }

  void _onLogChanged() {
    if (mounted) setState(() {});
  }

  void _fillSample(NotifySample s) {
    setState(() {
      _accountId = s.accountId;
      _titleCtrl.text = s.title;
      _textCtrl.text = s.text;
    });
  }

  void _send() {
    final msg = NotifyMessage(
      accountId: _accountId,
      title: _titleCtrl.text.trim(),
      text: _textCtrl.text.trim(),
      arrival: DateTime.now(),
    );
    setState(() {
      _lastResult = NotifyIngest.ingest(msg);
    });
  }

  void _openPending() {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const PendingPage()),
    );
  }

  void _snack(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(msg), duration: const Duration(seconds: 3)));
  }

  /// 真机监听链路：发一条本 App 的系统通知（原生 NotificationManager），
  /// 走 系统→监听服务→暂存队列→回前台补拉 的完整链路。
  Future<void> _postSystemNotify() async {
    const ch = MethodChannel('lsz_notify');
    var title = _titleCtrl.text.trim();
    final text = _textCtrl.text.trim();
    if (text.isEmpty) {
      _snack('请先填写正文或点击样本填充');
      return;
    }
    final isWechat = _accountId == Account.wechat.id;
    if (title.isEmpty) title = isWechat ? '微信支付' : '交易提醒';
    final targetPkg = isWechat
        ? 'com.tencent.mm'
        : 'com.eg.android.AlipayGphone';
    try {
      final r = await ch.invokeMethod<String>('postTestNotification', {
        'title': title,
        'text': text,
        'targetPkg': targetPkg,
      });
      if (r == 'permission_requested') {
        _snack('已请求通知权限：请在系统弹窗点"允许"，然后再次点击③');
      } else {
        _snack('系统通知已发送 → 切到后台再回到本 App，触发补拉入库');
      }
    } on PlatformException catch (e) {
      _snack('发送失败：${e.message}（仅安卓真机可用）');
    } catch (_) {
      _snack('发送失败（仅安卓真机可用）');
    }
  }

  Future<void> _openListenerSettings() async {
    try {
      await const MethodChannel('lsz_notify')
          .invokeMethod('openListenerSettings');
    } catch (_) {
      _snack('跳转失败（仅安卓真机可用）');
    }
  }

  Future<void> _openAppNotificationSettings() async {
    try {
      await const MethodChannel('lsz_notify')
          .invokeMethod('openAppNotificationSettings');
    } catch (_) {
      _snack('跳转失败（仅安卓真机可用）');
    }
  }

  /// 自愈修复：原生侧禁用再启用监听服务组件 → 触发系统重新绑定。
  /// 用于荣耀等 ROM"杀进程后不自动重绑"的失联场景。
  Future<void> _selfHealListener() async {
    try {
      await const MethodChannel('lsz_notify').invokeMethod('selfHealListener');
      _snack('自愈完成：已重新绑定监听服务，可点③发一条测试通知验证');
    } on PlatformException catch (e) {
      _snack('自愈失败：${e.message}');
    } catch (_) {
      _snack('自愈失败（仅安卓真机可用）');
    }
  }

  Future<void> _copyLog(NotifyLogEntry e) async {
    await Clipboard.setData(ClipboardData(
        text: '[${e.accountId}] ${e.title} ${e.text}\n（${e.reason}）'));
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('已复制原文'), duration: Duration(seconds: 1)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final logs = NotifyLogStore.instance.entries;
    return Scaffold(
      appBar: AppBar(title: const Text('模拟通知（开发调试）')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // ── 说明 ──
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.surfaceGroup,
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Text(
              '把一条收付款通知送入解析链路，等效验证真机通知监听。\n'
              '投递结果：可入待确认 / 指纹重复 / 无法解析 / 无效忽略。',
              style: TextStyle(
                  fontSize: 12, color: AppColors.textSecondary, height: 1.5),
            ),
          ),
          const SizedBox(height: 16),
          // ── 账户 ──
          Row(
            children: [
              const Text('来源账户',
                  style:
                      TextStyle(fontSize: 13, color: AppColors.textSecondary)),
              const SizedBox(width: 12),
              Expanded(
                child: SegmentedButton<String>(
                  segments: [
                    for (final a in Account.builtin)
                      ButtonSegment(
                        value: a.id,
                        label: Text(a.name),
                        icon: Icon(a.type == AccountType.wechat
                            ? Icons.wechat
                            : Icons.account_balance_wallet),
                      ),
                  ],
                  selected: {_accountId},
                  onSelectionChanged: (s) =>
                      setState(() => _accountId = s.first),
                  style: SegmentedButton.styleFrom(
                    selectedBackgroundColor: AppColors.primarySoft,
                    selectedForegroundColor: AppColors.primary,
                    foregroundColor: AppColors.textSecondary,
                    visualDensity: VisualDensity.compact,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          // ── 标题 / 正文 ──
          TextField(
            key: const Key('notify_title'),
            controller: _titleCtrl,
            decoration: const InputDecoration(
              labelText: '通知标题（如 微信支付 / 交易提醒）',
              labelStyle:
                  TextStyle(fontSize: 13, color: AppColors.textSecondary),
              isDense: true,
            ),
          ),
          const SizedBox(height: 8),
          TextField(
            key: const Key('notify_text'),
            controller: _textCtrl,
            maxLines: 3,
            decoration: const InputDecoration(
              labelText: '通知正文',
              alignLabelWithHint: true,
              labelStyle:
                  TextStyle(fontSize: 13, color: AppColors.textSecondary),
              hintText: '如：已支付¥3.7',
              hintStyle:
                  TextStyle(fontSize: 13, color: AppColors.textSecondary),
            ),
          ),
          const SizedBox(height: 12),
          // ── 样本快捷填充 ──
          const Text('样本（点击填充）',
              style:
                  TextStyle(fontSize: 12, color: AppColors.textSecondary)),
          const SizedBox(height: 6),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final s in notifySamples)
                ActionChip(
                  key: Key('sample_${s.label}'),
                  label: Text(s.label, style: const TextStyle(fontSize: 11)),
                  visualDensity: VisualDensity.compact,
                  onPressed: () => _fillSample(s),
                ),
            ],
          ),
          const SizedBox(height: 16),
          // ── 投递 ──
          FilledButton.icon(
            key: const Key('notify_send'),
            onPressed: _send,
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.primary,
              minimumSize: const Size.fromHeight(44),
            ),
            icon: const Icon(Icons.send, size: 18),
            label: const Text('投递这条通知',
                style: TextStyle(
                    fontSize: 15, fontWeight: FontWeight.w600)),
          ),
          const SizedBox(height: 12),
          // ── 最近一次结果 ──
          if (_lastResult != null) _buildResultCard(_lastResult!),
          const SizedBox(height: 20),
          // ── 真机监听链路（安卓 debug）──
          const Text('真机监听链路（安卓调试）',
              style: TextStyle(
                  fontSize: 13,
                  color: AppColors.textSecondary,
                  fontWeight: FontWeight.w600)),
          const SizedBox(height: 4),
          const Text(
            '在真机走完整系统链路：App 发一条系统通知 → 通知使用权服务捕获 → '
            '暂存队列 → 回前台补拉入库。首次使用需先完成两步授权。',
            style: TextStyle(fontSize: 11, color: AppColors.textSecondary),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              OutlinedButton(
                key: const Key('notify_open_listener'),
                onPressed: _openListenerSettings,
                child: const Text('① 授权：通知使用权',
                    style: TextStyle(fontSize: 12)),
              ),
              OutlinedButton(
                key: const Key('notify_open_app_notify'),
                onPressed: _openAppNotificationSettings,
                child: const Text('② 授权：允许通知',
                    style: TextStyle(fontSize: 12)),
              ),
              FilledButton.tonal(
                key: const Key('notify_post_system'),
                onPressed: _postSystemNotify,
                style: FilledButton.styleFrom(
                    foregroundColor: AppColors.primary),
                child: const Text('③ 发送模拟系统通知',
                    style: TextStyle(fontSize: 12)),
              ),
              OutlinedButton(
                key: const Key('notify_self_heal'),
                onPressed: _selfHealListener,
                style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.expense),
                child: const Text('④ 自愈修复（重绑监听）',
                    style: TextStyle(fontSize: 12)),
              ),
            ],
          ),
          const SizedBox(height: 20),
          const Divider(),
          // ── 无法解析日志 ──
          Row(
            children: [
              Expanded(
                child: Text('无法解析 / 无效通知日志 (${logs.length})',
                    style: const TextStyle(
                        fontSize: 13,
                        color: AppColors.textSecondary,
                        fontWeight: FontWeight.w600)),
              ),
              if (logs.isNotEmpty)
                TextButton(
                  key: const Key('notify_log_clear'),
                  onPressed: () => NotifyLogStore.instance.clear(),
                  child: const Text('清空',
                      style: TextStyle(fontSize: 12)),
                ),
            ],
          ),
          if (logs.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: Text('暂无。解析失败/无效的通知原文会留在这里，'
                  '便于真机后精调规则。',
                  style: TextStyle(
                      fontSize: 12, color: AppColors.textSecondary)),
            )
          else
            for (final e in logs) _buildLogEntry(e),
          const SizedBox(height: 32),
        ],
      ),
    );
  }

  Widget _buildResultCard(NotifyIngestResult r) {
    final (icon, color, title) = switch (r.outcome) {
      NotifyIngestOutcome.pendingAdded => (
          Icons.check_circle_outline,
          AppColors.income,
          '已进入待确认'
        ),
      NotifyIngestOutcome.duplicate => (
          Icons.content_copy,
          Colors.orange,
          '指纹重复，已跳过'
        ),
      NotifyIngestOutcome.failed => (
          Icons.error_outline,
          AppColors.expense,
          '无法解析'
        ),
      NotifyIngestOutcome.ignored => (
          Icons.block,
          AppColors.textSecondary,
          '无效通知，已忽略'
        ),
    };
    final rec = r.record;
    final isExpense = rec?.type == RecordType.expense;
    return Container(
      key: const Key('notify_result'),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 18, color: color),
              const SizedBox(width: 6),
              Text(title,
                  style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: color)),
              const Spacer(),
              if (rec != null)
                Text(
                  '${isExpense ? '-' : '+'}¥${Money.format(rec.amountCents)} '
                  '${isExpense ? '支出' : '收入'}',
                  style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: isExpense
                          ? AppColors.expense
                          : AppColors.income),
                ),
            ],
          ),
          const SizedBox(height: 4),
          Text(r.detail,
              style: const TextStyle(
                  fontSize: 12, color: AppColors.textSecondary)),
          if (r.outcome == NotifyIngestOutcome.pendingAdded) ...[
            const SizedBox(height: 6),
            Text(
              '时间：${formatRecordTime(rec!.time)}'
              '${rec.counterpart == null ? ' · 对方未知（可点"去处理"补充）' : ' · 对方：${rec.counterpart}'}',
              style: const TextStyle(
                  fontSize: 12, color: AppColors.textSecondary),
            ),
            const SizedBox(height: 4),
            TextButton.icon(
              key: const Key('sim_go_pending'),
              onPressed: _openPending,
              style: TextButton.styleFrom(
                  foregroundColor: AppColors.primary,
                  padding: EdgeInsets.zero),
              icon: const Icon(Icons.arrow_forward, size: 16),
              label: const Text('去待确认页处理',
                  style: TextStyle(fontSize: 13)),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildLogEntry(NotifyLogEntry e) {
    return Container(
      key: Key('notify_log_${e.time.microsecondsSinceEpoch}'),
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: AppColors.surfaceGroup,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AccountBadge(accountId: e.accountId, size: 28, iconSize: 15),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SelectableText(
                  e.text.isEmpty ? e.title : e.text,
                  style: const TextStyle(
                      fontSize: 13, color: AppColors.textMain),
                ),
                const SizedBox(height: 2),
                Text(e.reason,
                    style: const TextStyle(
                        fontSize: 11, color: AppColors.expense)),
                Text(formatRecordTime(e.time),
                    style: TextStyle(
                        fontSize: 11,
                        color: AppColors.textSecondary.withValues(
                            alpha: 0.7))),
              ],
            ),
          ),
          IconButton(
            key: Key('notify_log_copy_${e.time.microsecondsSinceEpoch}'),
            tooltip: '复制原文',
            visualDensity: VisualDensity.compact,
            onPressed: () => _copyLog(e),
            icon: const Icon(Icons.copy, size: 16),
          ),
        ],
      ),
    );
  }
}
