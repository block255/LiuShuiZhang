import 'package:flutter/material.dart';

import '../app_info.dart';
import '../app_theme.dart';
import '../data/record_store.dart';
import '../models/account.dart';
import '../services/export_service.dart';
import '../services/file_pick.dart';
import '../services/file_save.dart';
import '../services/restore_service.dart';
import '../utils/money.dart';
import '../utils/time_span.dart';
import 'import_page.dart';
import 'category_manage_page.dart';
import 'notify_setting_page.dart';
import 'tutorial_page.dart';

/// 「我的」页（S5：账户卡片 + 设置入口）
class ProfilePage extends StatefulWidget {
  const ProfilePage({super.key});

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  @override
  void initState() {
    super.initState();
    RecordStore.instance.addListener(_onStoreChanged);
  }

  @override
  void dispose() {
    RecordStore.instance.removeListener(_onStoreChanged);
    super.dispose();
  }

  void _onStoreChanged() {
    if (mounted) setState(() {});
  }

  void _placeholder(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), duration: const Duration(seconds: 1)),
    );
  }

  void _openImport(String accountId) {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => ImportPage(accountId: accountId)),
    );
  }

  /// 导出备份：选择格式（CSV 表格 / JSON 完整备份）
  Future<void> _exportData() async {
    final records = RecordStore.instance.all;
    if (records.isEmpty) {
      _placeholder('暂无数据可导出');
      return;
    }
    final fmt = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.all(14),
              child: Text('导出 ${records.length} 条账单',
                  style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textMain)),
            ),
            ListTile(
              key: const Key('export_csv'),
              leading: const Icon(Icons.table_chart_outlined),
              title: const Text('CSV 表格'),
              subtitle: const Text('Excel/WPS 可直接打开'),
              onTap: () => Navigator.of(ctx).pop('csv'),
            ),
            ListTile(
              key: const Key('export_json'),
              leading: const Icon(Icons.data_object),
              title: const Text('JSON 备份'),
              subtitle: const Text('完整数据备份，可用于未来恢复'),
              onTap: () => Navigator.of(ctx).pop('json'),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (fmt == null) return;

    final now = DateTime.now();
    String p(int n) => n.toString().padLeft(2, '0');
    final stamp = '${now.year}${p(now.month)}${p(now.day)}-${p(now.hour)}${p(now.minute)}';
    final fileName = fmt == 'csv'
        ? '流水账导出_$stamp.csv'
        : '流水账备份_$stamp.json';
    final content = fmt == 'csv'
        ? ExportService.buildCsv(records)
        : ExportService.buildJson(records);

    try {
      await saveTextFile(fileName, content);
      _placeholder('已导出：$fileName');
    } catch (e) {
      _placeholder('导出失败：$e');
    }
  }

  /// JSON 备份恢复：选文件 → 解析 → 选模式（合并去重 / 全量覆盖）→ 执行
  Future<void> _restoreBackup() async {
    final picked = await pickBillFile(accept: '.json');
    if (picked == null || !mounted) return;

    final parsed = RestoreService.parse(picked.bytes);
    if (parsed == null) {
      _placeholder('备份文件无效或已损坏');
      return;
    }
    if (parsed.records.isEmpty) {
      _placeholder('备份中没有有效记录');
      return;
    }

    final store = RecordStore.instance;
    final current = store.all.length;
    final mode = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('恢复备份（${parsed.records.length} 条）'),
        content: Text(
          '备份含 ${parsed.records.length} 条有效记录'
          '${parsed.skipped > 0 ? '（跳过损坏 ${parsed.skipped} 条）' : ''}。\n'
          '当前库有 $current 条记录。请选择恢复方式：',
          style: const TextStyle(fontSize: 13, height: 1.5),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop('merge'),
            child: const Text('合并去重'),
          ),
          TextButton(
            key: const Key('restore_overwrite'),
            onPressed: () => Navigator.of(ctx).pop('overwrite'),
            style: TextButton.styleFrom(foregroundColor: AppColors.expense),
            child: const Text('全量覆盖'),
          ),
        ],
      ),
    );
    if (mode == null || !mounted) return;

    if (mode == 'overwrite') {
      // 覆盖前二次确认
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('全量覆盖？'),
          content: Text(
            '将清空现有 $current 条记录，替换为备份中的 '
            '${parsed.records.length} 条。此操作不可撤销，建议先导出当前数据备份。',
            style: const TextStyle(fontSize: 13, height: 1.5),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('取消'),
            ),
            TextButton(
              key: const Key('restore_overwrite_confirm'),
              onPressed: () => Navigator.of(ctx).pop(true),
              style: TextButton.styleFrom(foregroundColor: AppColors.expense),
              child: const Text('确认覆盖'),
            ),
          ],
        ),
      );
      if (ok != true || !mounted) return;
      await store.restoreAll(parsed.records);
      _placeholder('已恢复 ${parsed.records.length} 条（全量覆盖）');
    } else {
      final r = await store.mergeBackup(parsed.records);
      _placeholder('合并完成：新增 ${r.added} 条，更新 ${r.updated} 条');
    }
  }

  /// 设置区"导入账单文件"：先选账户再进入导入页
  Future<void> _pickAccountThenImport() async {
    final picked = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.all(14),
              child: Text('导入到哪个账户？',
                  style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textMain)),
            ),
            for (final a in Account.builtin)
              ListTile(
                key: Key('pick_acc_${a.id}'),
                leading: Icon(
                  a.type == AccountType.wechat
                      ? Icons.wechat
                      : Icons.account_balance_wallet,
                  color: AppColors.primary,
                ),
                title: Text(a.name),
                onTap: () => Navigator.of(ctx).pop(a.id),
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (picked != null) _openImport(picked);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('我的')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // ── 账户卡片 ──
          for (final a in Account.builtin) ...[
            _AccountCard(account: a, onImport: () => _openImport(a.id)),
            const SizedBox(height: 12),
          ],
          // 「绑定手动账户」按钮：1.0 正式版暂不露出（功能转观察期，等真实需求确认后再上）
          // 恢复时把下面的 OutlinedButton 放回 ListView 即可（Key 仍为 add_manual_account）
          const SizedBox(height: 24),
          // ── 设置 ──
          const Padding(
            padding: EdgeInsets.only(left: 4, bottom: 8),
            child: Text('设置',
                style: TextStyle(
                    fontSize: 13,
                    color: AppColors.textSecondary,
                    fontWeight: FontWeight.w600)),
          ),
          _SettingRow(
            key: const Key('set_tutorial'),
            icon: Icons.menu_book_outlined,
            title: '使用教程',
            subtitle: '三条记账途径怎么配合、常见问题',
            onTap: () => Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => const TutorialPage())),
          ),
          _SettingRow(
            key: const Key('set_import'),
            icon: Icons.file_download_outlined,
            title: '导入账单文件',
            subtitle: '支持微信/支付宝导出的账单',
            onTap: _pickAccountThenImport,
          ),
          _SettingRow(
            key: const Key('set_notify'),
            icon: Icons.notifications_active_outlined,
            title: '通知自动记账',
            subtitle: '监听收付款通知，自动记录待确认',
            onTap: () => Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => const NotifySettingPage())),
          ),
          _SettingRow(
            key: const Key('set_category'),
            icon: Icons.category_outlined,
            title: '分类管理',
            subtitle: '新增自定义分类、停用内置分类',
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(
                  builder: (_) => const CategoryManagePage()),
            ),
          ),
          _SettingRow(
            key: const Key('set_export'),
            icon: Icons.file_upload_outlined,
            title: '导出备份',
            subtitle: '导出全部账单为 CSV / JSON 文件',
            onTap: _exportData,
          ),
          _SettingRow(
            key: const Key('set_restore'),
            icon: Icons.settings_backup_restore_outlined,
            title: '导入备份（JSON 恢复）',
            subtitle: '从 JSON 备份恢复：可全量覆盖或合并去重',
            onTap: _restoreBackup,
          ),
          const SizedBox(height: 32),
          // ── 版本 ──
          Center(
            child: Text(
              '流水账 ${AppInfo.display} · 数据仅存本机',
              style: TextStyle(
                  fontSize: 11,
                  color: AppColors.textSecondary.withValues(alpha: 0.6)),
            ),
          ),
        ],
      ),
    );
  }
}

/// 单个账户卡片：图标 + 名称 + 状态/统计 + 操作
class _AccountCard extends StatelessWidget {
  final Account account;
  final VoidCallback onImport;

  const _AccountCard({required this.account, required this.onImport});

  Color get _brandColor => switch (account.type) {
        AccountType.wechat => const Color(0xFF07C160),
        AccountType.alipay => const Color(0xFF1677FF),
        AccountType.manual => AppColors.primary,
      };

  IconData get _icon => switch (account.type) {
        AccountType.wechat => Icons.wechat,
        AccountType.alipay => Icons.account_balance_wallet,
        AccountType.manual => Icons.account_balance,
      };

  @override
  Widget build(BuildContext context) {
    // 本月该账户收支统计（实时联动）
    final m = timeSpanRange(TimeSpanType.thisMonth);
    final q = RecordStore.instance.query(RecordQuery(
      accountId: account.id,
      start: m.start,
      end: m.end,
    ));
    final statParts = <String>[
      if (q.expenseCents > 0) '支出 ¥${Money.format(q.expenseCents)}',
      if (q.incomeCents > 0) '收入 ¥${Money.format(q.incomeCents)}',
      '${q.records.length} 笔',
    ];

    return Container(
      key: Key('account_card_${account.id}'),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.divider),
      ),
      child: Row(
        children: [
          // 平台图标圆底
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: _brandColor.withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            child: Icon(_icon, size: 24, color: _brandColor),
          ),
          const SizedBox(width: 12),
          // 名称 + 状态/统计
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(account.name,
                        style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                            color: AppColors.textMain)),
                    const SizedBox(width: 6),
                    const Text('已绑定',
                        style: TextStyle(
                            fontSize: 11, color: AppColors.income)),
                  ],
                ),
                const SizedBox(height: 3),
                Text(
                  statParts.isEmpty ? '本月暂无账单' : '本月 ${statParts.join(' · ')}',
                  style: const TextStyle(
                      fontSize: 12, color: AppColors.textSecondary),
                ),
              ],
            ),
          ),
          // 导入按钮
          TextButton(
            key: Key('import_${account.id}'),
            onPressed: onImport,
            style: TextButton.styleFrom(
              foregroundColor: AppColors.primary,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              minimumSize: const Size(0, 32),
              textStyle: const TextStyle(fontSize: 13),
            ),
            child: const Text('导入'),
          ),
        ],
      ),
    );
  }
}

/// 设置列表行
class _SettingRow extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _SettingRow({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    // 注意：key 只挂在本组件上（不再转发给 InkWell），否则同一 Key 会命中 2 个
    // widget，测试里 find.byKey/tap 会报 "ambiguously found multiple matching widgets"
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 10),
        child: Row(
          children: [
            Icon(icon, size: 22, color: AppColors.textSecondary),
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
