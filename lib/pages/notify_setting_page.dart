import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../app_theme.dart';
import '../services/notify/notify_platform.dart';
import 'notify_sim_page.dart';

/// 通知自动记账 · 设置页（B3a）
///
/// - 主开关：真正控制原生监听是否采集（关闭 = 通知到达直接丢弃，省电）
/// - 授权/修复：跳系统"通知使用权"设置、失联自愈（荣耀杀进程后不自动重绑）
/// - 使用须知：划掉应用不影响记账（有前台保活）；提示「强行停止」会暂停监听
class NotifySettingPage extends StatefulWidget {
  const NotifySettingPage({super.key});

  @override
  State<NotifySettingPage> createState() => _NotifySettingPageState();
}

class _NotifySettingPageState extends State<NotifySettingPage> {
  bool _enabled = true;
  bool _platformSupported = true; // Android 真机才有原生通道

  /// 监听健康状态：null=检测中/未知 / 'ok' / 'dead' / 'no_access' / 'no_permission'
  String? _health;
  bool _checking = false;

  /// 方案 B：前台保活开关
  bool _keepAlive = false;

  @override
  void initState() {
    super.initState();
    _loadState();
  }

  Future<void> _loadState() async {
    try {
      final enabled = await NotifyPlatform.getListenerEnabled();
      if (mounted) setState(() => _enabled = enabled);
      try {
        final ka = await NotifyPlatform.getKeepAlive();
        if (mounted) setState(() => _keepAlive = ka);
      } catch (_) {}
      if (enabled) {
        await _checkHealth();
      }
    } catch (_) {
      if (mounted) setState(() => _platformSupported = false);
    }
  }

  /// 后台保活开关：启停前台服务（进程常驻 → 监听绑定不断）
  Future<void> _toggleKeepAlive(bool value) async {
    setState(() => _keepAlive = value);
    try {
      await NotifyPlatform.setKeepAlive(value);
      _snack(value
          ? '已开启后台保活（通知栏将常驻一条提示）'
          : '已关闭后台保活');
    } catch (_) {
      setState(() => _keepAlive = !value);
      _snack('设置失败（仅安卓真机可用）');
    }
  }

  /// 监听健康检测：原生发 probe 通知 → 回读队列确认监听活着。
  /// 状态字符串见 [NotifyPlatform.checkListenerHealth]。
  Future<void> _checkHealth() async {
    if (_checking) return;
    setState(() {
      _checking = true;
      _health = null;
    });
    try {
      final s = await NotifyPlatform.checkListenerHealth();
      if (!mounted) return;
      setState(() => _health = s);
      if (s == 'no_permission') {
        _snack('请允许本应用发送通知，然后点「重新检测」');
      }
    } catch (_) {
      if (mounted) setState(() => _health = 'dead');
    } finally {
      if (mounted) setState(() => _checking = false);
    }
  }

  void _snack(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(msg), duration: const Duration(seconds: 3)));
  }

  Future<void> _toggle(bool value) async {
    setState(() => _enabled = value);
    try {
      await NotifyPlatform.setListenerEnabled(value);
      _snack(value ? '已开启：收付款通知将自动记录' : '已关闭：不再采集通知');
      if (value) {
        await _checkHealth(); // 打开后自检一次
      } else {
        setState(() => _health = null);
      }
    } catch (_) {
      setState(() => _enabled = !value);
      _snack('设置失败（仅安卓真机可用）');
    }
  }

  Future<void> _heal() async {
    try {
      await NotifyPlatform.selfHeal();
      _snack('已重新绑定监听服务');
      await _checkHealth(); // 修复后自检
    } catch (_) {
      _snack('修复失败（仅安卓真机可用）');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('通知自动记账')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // ── 主开关 ──
          // 注意：卡片背景色必须由 Material 提供——SwitchListTile 内部是 ListTile，
          // 若外层 Container 带背景色，框架会断言 "ListTile background color or ink
          // splashes may be invisible"（水波纹被遮）并让 test 失败。
          Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.divider),
            ),
            clipBehavior: Clip.antiAlias,
            child: Material(
              color: AppColors.background,
              child: SwitchListTile(
                key: const Key('notify_switch'),
                title: const Text('启用通知自动记账',
                    style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textMain)),
                subtitle: const Text(
                  '自动记录微信 / 支付宝的收付款通知，进入待确认后一键入账',
                  style:
                      TextStyle(fontSize: 12, color: AppColors.textSecondary),
                ),
                value: _enabled,
                onChanged: _platformSupported ? _toggle : null,
                activeTrackColor: AppColors.primary,
              ),
            ),
          ),
          if (!_platformSupported) ...[
            const SizedBox(height: 8),
            const Text('（此功能需要安卓真机）',
                style: TextStyle(
                    fontSize: 12, color: AppColors.textSecondary)),
          ],
          if (_platformSupported && _enabled) ...[
            const SizedBox(height: 10),
            _buildHealthBar(),
          ],
          const SizedBox(height: 12),
          // ── 方案 B：后台保活开关 ──
          if (_platformSupported && _enabled) ...[
            Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.divider),
              ),
              clipBehavior: Clip.antiAlias,
              child: Material(
                color: AppColors.background,
                child: SwitchListTile(
                  key: const Key('keepalive_switch'),
                  title: const Text('后台保活（推荐）',
                      style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: AppColors.textMain)),
                  subtitle: const Text(
                    '防止系统清理后台导致收不到通知；开启后通知栏常驻一条"监听中"提示',
                    style: TextStyle(
                        fontSize: 12, color: AppColors.textSecondary),
                  ),
                  value: _keepAlive,
                  onChanged: _toggleKeepAlive,
                  activeTrackColor: AppColors.primary,
                ),
              ),
            ),
            const SizedBox(height: 12),
          ],
          // ── 小贴士 ──
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.primarySoft,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Row(children: [
                  Icon(Icons.lightbulb_outline,
                      size: 16, color: AppColors.primary),
                  SizedBox(width: 6),
                  Text('使用小贴士',
                      style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: AppColors.primary)),
                ]),
                const SizedBox(height: 6),
                const Text(
                  '1. 从最近任务里划掉本应用不影响记账（已开启后台保活时）；'
                  '请不要在系统设置里「强行停止」本应用；\n'
                  '2. 万一收不到：点下方「立即修复」，或到系统设置里把通知使用权开关关掉再打开。',
                  style: TextStyle(
                      fontSize: 12,
                      color: AppColors.textSecondary,
                      height: 1.6),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          const Text('监听与修复',
              style: TextStyle(
                  fontSize: 13,
                  color: AppColors.textSecondary,
                  fontWeight: FontWeight.w600)),
          _actionTile(
            key: const Key('notify_setting_open_listener'),
            icon: Icons.verified_user_outlined,
            title: '通知使用权授权',
            subtitle: '系统级授权：允许本应用读取收付款通知',
            onTap: () async {
              try {
                await NotifyPlatform.openListenerSettings();
              } catch (_) {
                _snack('跳转失败（仅安卓真机可用）');
              }
            },
          ),
          _actionTile(
            key: const Key('notify_setting_heal'),
            icon: Icons.healing_outlined,
            title: '立即修复监听',
            subtitle: '重新绑定监听服务（收不到通知时使用）',
            onTap: _heal,
          ),
          if (kDebugMode) ...[
            const SizedBox(height: 20),
            const Text('调试（仅开发版可见）',
                style: TextStyle(
                    fontSize: 13,
                    color: AppColors.textSecondary,
                    fontWeight: FontWeight.w600)),
            _actionTile(
              key: const Key('notify_setting_sim'),
              icon: Icons.science_outlined,
              title: '模拟通知调试面板',
              subtitle: '样本投递 / 模拟系统通知 / 自愈验证',
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const NotifySimPage()),
              ),
            ),
          ],
          const SizedBox(height: 24),
          Center(
            child: Text(
              '通知内容仅在本机解析，不上传任何数据',
              style: TextStyle(
                  fontSize: 11,
                  color:
                      AppColors.textSecondary.withValues(alpha: 0.7)),
            ),
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }

  /// 监听健康状态条（绿=正常 / 红=失联 / 橙=需授权 / 灰=检测中）
  Widget _buildHealthBar() {
    final (icon, color, text) = switch (_health) {
      'ok' => (
          Icons.check_circle,
          AppColors.income,
          '监听正常：收付款通知到达时自动记录'
        ),
      'no_access' => (
          Icons.lock_outline,
          AppColors.warn,
          '未授权「通知使用权」：点下方第一项去打开系统开关'
        ),
      'no_permission' => (
          Icons.notifications_off_outlined,
          AppColors.warn,
          '缺少通知权限：自检要发一条测试通知，请允许后点「重新检测」'
        ),
      'dead' => (
          Icons.error_outline,
          AppColors.expense,
          '监听未响应：服务可能被系统断开 → 点下方「立即修复监听」'
        ),
      _ => (
          Icons.sync,
          AppColors.textSecondary,
          _checking ? '正在检测监听状态…' : '监听状态未知'
        ),
    };
    return Container(
      key: const Key('notify_health_bar'),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Row(
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(width: 8),
          Expanded(
            child: Text(text,
                style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: color)),
          ),
          TextButton(
            key: const Key('notify_health_retest'),
            onPressed: _checking ? null : _checkHealth,
            style: TextButton.styleFrom(
                foregroundColor: AppColors.primary,
                padding: const EdgeInsets.symmetric(horizontal: 8),
                minimumSize: const Size(0, 32)),
            child: Text(_checking ? '检测中' : '重新检测',
                style: const TextStyle(fontSize: 12)),
          ),
        ],
      ),
    );
  }

  Widget _actionTile({
    required Key key,
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return InkWell(
      key: key,
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        margin: const EdgeInsets.only(top: 6),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: AppColors.background,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: AppColors.divider),
        ),
        child: Row(
          children: [
            Icon(icon, size: 22, color: AppColors.primary),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: const TextStyle(
                          fontSize: 14, color: AppColors.textMain)),
                  const SizedBox(height: 2),
                  Text(subtitle,
                      style: const TextStyle(
                          fontSize: 11, color: AppColors.textSecondary)),
                ],
              ),
            ),
            const Icon(Icons.chevron_right,
                size: 20, color: AppColors.textSecondary),
          ],
        ),
      ),
    );
  }
}
