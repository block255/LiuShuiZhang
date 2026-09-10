import 'package:flutter/material.dart';

import '../app_theme.dart';
import '../data/category_store.dart';
import '../data/record_store.dart';
import '../models/account.dart';
import '../models/record.dart';
import '../utils/money.dart';
import '../utils/record_time.dart';
import '../utils/time_span.dart';
import '../widgets/category_icon.dart';
import 'add_record_page.dart';
import 'pending_page.dart';

/// 主页「账单流水」（S4：筛选栏 + 汇总卡 + 列表）
class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  String? _accountFilter; // null = 全部账户
  TimeSpanType _span = TimeSpanType.thisMonth;
  DateTimeRange? _customRange;
  RecordType? _typeFilter; // null = 收支都查

  // 批量管理模式
  bool _bulkMode = false;
  final Set<String> _selectedIds = {};

  List<Record> _visibleRecords = const [];

  @override
  void initState() {
    super.initState();
    RecordStore.instance.addListener(_onStoreChanged);
    // 展示启动时自动清理 / 待确认自动入账的结果（一次性）
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final store = RecordStore.instance;
      final cleaned = store.consumeAutoCleanNotice();
      final autoIn = store.consumePendingAutoNotice();
      final messenger = ScaffoldMessenger.of(context);
      if (cleaned > 0 && mounted) {
        messenger.showSnackBar(SnackBar(
          content: Text(
              '已自动清理 $cleaned 条 ${store.retentionYears} 年前的记录'),
          duration: const Duration(seconds: 3),
        ));
      }
      if (autoIn > 0 && mounted) {
        messenger.showSnackBar(SnackBar(
          content: Text(
              '有 $autoIn 条待确认超时未处理，已自动入账（未分类），可长按编辑'),
          duration: const Duration(seconds: 4),
        ));
      }
    });
  }

  @override
  void dispose() {
    RecordStore.instance.removeListener(_onStoreChanged);
    super.dispose();
  }

  void _onStoreChanged() {
    if (mounted) setState(() {});
  }

  void _openAddPage() {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const AddRecordPage()),
    );
  }

  void _openPending() {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const PendingPage()),
    );
  }

  void _openEdit(Record r) {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => AddRecordPage(editRecord: r)),
    );
  }

  /// 长按/右键：单条操作菜单
  void _showRowMenu(Record r) {
    showModalBottomSheet<void>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.edit_outlined),
              title: const Text('编辑'),
              onTap: () {
                Navigator.of(ctx).pop();
                _openEdit(r);
              },
            ),
            ListTile(
              leading: const Icon(Icons.delete_outline,
                  color: AppColors.expense),
              title: const Text('删除',
                  style: TextStyle(color: AppColors.expense)),
              onTap: () {
                Navigator.of(ctx).pop();
                _confirmDeleteOne(r);
              },
            ),
            ListTile(
              leading: const Icon(Icons.library_add_check_outlined),
              title: const Text('批量选择'),
              onTap: () {
                Navigator.of(ctx).pop();
                _enterBulk();
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Future<void> _confirmDeleteOne(Record r) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除这条记录？'),
        content: Text('删除后不可恢复：${Money.format(r.amountCents)} 元'
            '（${r.counterpart ?? ''}）'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('取消'),
          ),
          TextButton(
            key: const Key('bulk_confirm_delete'),
            onPressed: () => Navigator.of(ctx).pop(true),
            style: TextButton.styleFrom(foregroundColor: AppColors.expense),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (ok == true) {
      RecordStore.instance.remove(r.id);
    }
  }

  void _enterBulk() {
    setState(() {
      _bulkMode = true;
      _selectedIds.clear();
    });
  }

  void _exitBulk() {
    setState(() {
      _bulkMode = false;
      _selectedIds.clear();
    });
  }

  void _toggleSelect(String id) {
    setState(() {
      if (!_selectedIds.remove(id)) _selectedIds.add(id);
    });
  }

  bool get _allVisibleSelected =>
      _visibleRecords.isNotEmpty &&
      _visibleRecords.every((r) => _selectedIds.contains(r.id));

  void _toggleSelectAll() {
    setState(() {
      if (_allVisibleSelected) {
        _selectedIds.clear();
      } else {
        _selectedIds
          ..clear()
          ..addAll(_visibleRecords.map((r) => r.id));
      }
    });
  }

  Future<void> _confirmBulkDelete() async {
    final n = _selectedIds.length;
    if (n == 0) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('删除选中的 $n 条记录？'),
        content: const Text('删除后不可恢复。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('取消'),
          ),
          TextButton(
            key: const Key('bulk_confirm_delete'),
            onPressed: () => Navigator.of(ctx).pop(true),
            style: TextButton.styleFrom(foregroundColor: AppColors.expense),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    final store = RecordStore.instance;
    for (final id in _selectedIds.toList()) {
      store.remove(id);
    }
    final deleted = _selectedIds.length;
    setState(() {
      _bulkMode = false;
      _selectedIds.clear();
    });
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text('已删除 $deleted 条记录'),
      duration: const Duration(seconds: 2),
    ));
  }

  RecordQuery get _query {
    final range = timeSpanRange(
      _span,
      customStart: _customRange?.start,
      customEnd: _customRange?.end,
    );
    return RecordQuery(
      accountId: _accountFilter,
      type: _typeFilter,
      start: range.start,
      end: range.end,
    );
  }

  Future<void> _pickCustomRange() async {
    final now = DateTime.now();
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2015),
      lastDate: DateTime(now.year, now.month, now.day),
      initialDateRange: _customRange,
      helpText: '选择时间跨度',
      saveText: '确定',
    );
    if (picked == null) return;
    setState(() {
      _customRange = picked;
      _span = TimeSpanType.custom;
    });
  }

  @override
  Widget build(BuildContext context) {
    final store = RecordStore.instance;
    final result = store.query(_query);
    _visibleRecords = result.records;
    final hasAny = store.all.isNotEmpty;
    final pendingN = store.pending().records.length;

    return Scaffold(
      appBar: _bulkMode
          ? AppBar(
              leading: IconButton(
                key: const Key('bulk_exit'),
                icon: const Icon(Icons.close),
                onPressed: _exitBulk,
              ),
              title: Text('已选 ${_selectedIds.length} 项'),
              actions: [
                TextButton(
                  key: const Key('bulk_select_all'),
                  onPressed: _visibleRecords.isEmpty ? null : _toggleSelectAll,
                  child: Text(_allVisibleSelected ? '取消全选' : '全选'),
                ),
                const SizedBox(width: 4),
              ],
            )
          : AppBar(
              title: const Text('流水账'),
              actions: [
                if (hasAny)
                  TextButton(
                    key: const Key('bulk_enter'),
                    onPressed: _enterBulk,
                    child: const Text('批量'),
                  ),
                const SizedBox(width: 4),
              ],
            ),
      body: Column(
        children: [
          if (!_bulkMode && pendingN > 0) ...[
            // 待确认通知横幅入口（阶段一点五）
            _PendingBanner(count: pendingN, onTap: _openPending),
          ],
          if (!_bulkMode) ...[
            _buildFilterBar(),
            _SummaryCard(
              incomeCents: result.incomeCents,
              expenseCents: result.expenseCents,
            ),
            const Divider(),
          ],
          Expanded(
            child: !hasAny
                ? const _EmptyPlaceholder(
                    icon: Icons.receipt_long_outlined,
                    text: '还没有账单，点右下角 ＋ 记一笔吧',
                  )
                : result.records.isEmpty
                    ? const _EmptyPlaceholder(
                        icon: Icons.search_off,
                        text: '没有符合条件的账单，换个筛选试试',
                      )
                    : ListView.separated(
                        padding: const EdgeInsets.only(bottom: 88),
                        itemCount: result.records.length,
                        separatorBuilder: (_, _) =>
                            const Divider(indent: 68, endIndent: 16),
                        itemBuilder: (_, i) {
                          final r = result.records[i];
                          return _RecordRow(
                            record: r,
                            selectMode: _bulkMode,
                            selected: _selectedIds.contains(r.id),
                            onLongPress: () => _showRowMenu(r),
                            onSecondaryTap: () => _showRowMenu(r),
                            onSelectToggle: () => _toggleSelect(r.id),
                          );
                        },
                      ),
          ),
        ],
      ),
      bottomNavigationBar: _bulkMode
          ? SafeArea(
              child: Container(
                key: const Key('bulk_bar'),
                padding: const EdgeInsets.symmetric(horizontal: 16),
                decoration: BoxDecoration(
                  color: AppColors.background,
                  border: const Border(
                      top: BorderSide(color: AppColors.divider)),
                ),
                child: Row(
                  children: [
                    TextButton.icon(
                      onPressed: _selectedIds.isEmpty
                          ? null
                          : _confirmBulkDelete,
                      icon: const Icon(Icons.delete_outline, size: 20),
                      label: Text('删除${_selectedIds.isEmpty ? '' : ' ${_selectedIds.length}'}'),
                      style: TextButton.styleFrom(
                          foregroundColor: AppColors.expense),
                    ),
                    const Spacer(),
                    if (_selectedIds.isNotEmpty)
                      Text(
                        '已选 ${_selectedIds.length} 项',
                        style: const TextStyle(
                            fontSize: 12, color: AppColors.textSecondary),
                      ),
                  ],
                ),
              ),
            )
          : null,
      floatingActionButton: _bulkMode
          ? null
          : FloatingActionButton(
              key: const Key('fab_add'),
              onPressed: _openAddPage,
              tooltip: '记一笔',
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
              child: const Icon(Icons.add),
            ),
    );
  }

  // ── 筛选栏 ──
  Widget _buildFilterBar() {
    return Container(
      color: AppColors.surfaceGroup,
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 账户
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _filterChip(
                key: const Key('acc_all'),
                label: '全部',
                selected: _accountFilter == null,
                onTap: () => setState(() => _accountFilter = null),
              ),
              for (final a in Account.builtin)
                _filterChip(
                  key: Key('acc_${a.id}'),
                  label: a.name,
                  selected: _accountFilter == a.id,
                  onTap: () => setState(() => _accountFilter = a.id),
                ),
            ],
          ),
          const SizedBox(height: 8),
          // 时间跨度
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                for (final t in TimeSpanType.values) ...[
                  if (t == TimeSpanType.custom)
                    _filterChip(
                      key: const Key('span_custom'),
                      label: t.label,
                      selected: _span == t,
                      onTap: _pickCustomRange,
                    )
                  else
                    _filterChip(
                      key: Key('span_${t.name}'),
                      label: t.label,
                      selected: _span == t,
                      onTap: () => setState(() => _span = t),
                    ),
                  const SizedBox(width: 8),
                ],
              ],
            ),
          ),
          const SizedBox(height: 8),
          // 收支
          Wrap(
            spacing: 8,
            children: [
              _filterChip(
                key: const Key('type_all'),
                label: '收支',
                selected: _typeFilter == null,
                onTap: () => setState(() => _typeFilter = null),
              ),
              _filterChip(
                key: const Key('type_expense'),
                label: '仅支出',
                selected: _typeFilter == RecordType.expense,
                onTap: () => setState(() => _typeFilter = RecordType.expense),
              ),
              _filterChip(
                key: const Key('type_income'),
                label: '仅收入',
                selected: _typeFilter == RecordType.income,
                onTap: () => setState(() => _typeFilter = RecordType.income),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// 自绘筛选按钮（不用 ChoiceChip：Chip 内部对文字强制
  /// maxLines:1 + fade 裁切，宽高计算异常时文字会显示不全）
  Widget _filterChip({
    required Key key,
    required String label,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return InkWell(
      key: key,
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: selected ? AppColors.primarySoft : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: selected ? AppColors.primary : AppColors.divider,
            width: selected ? 1.5 : 1,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 13,
            color: selected ? AppColors.primary : AppColors.textSecondary,
            fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
          ),
        ),
      ),
    );
  }
}

/// 汇总卡：收入 / 支出 / 结余（随筛选联动）
class _SummaryCard extends StatelessWidget {
  final int incomeCents;
  final int expenseCents;

  const _SummaryCard({required this.incomeCents, required this.expenseCents});

  @override
  Widget build(BuildContext context) {
    final balance = incomeCents - expenseCents;
    final balanceColor =
        balance >= 0 ? AppColors.income : AppColors.expense;
    final balanceText =
        balance >= 0 ? '¥${Money.format(balance)}' : '-¥${Money.format(-balance)}';

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(12, 10, 12, 4),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.surfaceGroup,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: _SumColumn(
                  label: '支出',
                  text: '¥${Money.format(expenseCents)}',
                  color: AppColors.expense,
                ),
              ),
              Expanded(
                child: _SumColumn(
                  label: '收入',
                  text: '¥${Money.format(incomeCents)}',
                  color: AppColors.income,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              const Text('结余',
                  style:
                      TextStyle(fontSize: 12, color: AppColors.textSecondary)),
              const SizedBox(width: 10),
              Text(
                balanceText,
                style: TextStyle(
                  fontSize: 26,
                  fontWeight: FontWeight.w700,
                  color: balanceColor,
                  height: 1.0,
                ),
              ),
              const Spacer(),
              Text(
                '筛选结果合计',
                style: TextStyle(
                  fontSize: 11,
                  color: AppColors.textSecondary.withValues(alpha: 0.7),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _SumColumn extends StatelessWidget {
  final String label;
  final String text;
  final Color color;

  const _SumColumn({
    required this.label,
    required this.text,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Text(label,
            style:
                const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
        const SizedBox(width: 8),
        Text(
          text,
          style: TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.w700,
            color: color,
            height: 1.0,
          ),
        ),
      ],
    );
  }
}

/// 账单行：左分类图标 | 中 对方/分类+时间 | 右金额
class _RecordRow extends StatelessWidget {
  final Record record;
  final bool selectMode;
  final bool selected;
  final VoidCallback onLongPress;
  final VoidCallback onSecondaryTap;
  final VoidCallback onSelectToggle;

  const _RecordRow({
    required this.record,
    required this.selectMode,
    required this.selected,
    required this.onLongPress,
    required this.onSecondaryTap,
    required this.onSelectToggle,
  });

  @override
  Widget build(BuildContext context) {
    final cat = record.categoryId == null
        ? null
        : CategoryStore.instance.categoryById(record.categoryId!);
    final isExpense = record.type == RecordType.expense;
    final color = isExpense ? AppColors.expense : AppColors.income;
    final mainText = record.counterpart?.isNotEmpty == true
        ? record.counterpart!
        : (cat?.name ?? '未分类');

    return InkWell(
      key: Key('record_${record.id}'),
      // 单击不响应（编辑走长按/右键，符合手机端习惯）
      onTap: selectMode ? onSelectToggle : null,
      onLongPress: selectMode ? onSelectToggle : onLongPress,
      onSecondaryTapDown: selectMode ? null : (_) => onSecondaryTap(),
      child: Container(
        color: selectMode && selected
            ? AppColors.primarySoft.withValues(alpha: 0.5)
            : Colors.transparent,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Row(
            children: [
              if (selectMode) ...[
                // 多选框
                SizedBox(
                  width: 24,
                  child: Icon(
                    selected
                        ? Icons.check_circle
                        : Icons.radio_button_unchecked,
                    size: 20,
                    color:
                        selected ? AppColors.primary : AppColors.textSecondary,
                  ),
                ),
                const SizedBox(width: 8),
              ],
              Container(
                width: 40,
                height: 40,
                decoration: const BoxDecoration(
                  color: AppColors.primarySoft,
                  shape: BoxShape.circle,
                ),
                child: CategoryIcon(
                    category: cat,
                    fallbackIcon: Icons.receipt_long,
                    size: 20,
                    color: AppColors.primary),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      mainText,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontSize: 15, color: AppColors.textMain),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      formatRecordTime(record.time),
                      style: const TextStyle(
                          fontSize: 12, color: AppColors.textSecondary),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Text(
                '${isExpense ? '-' : '+'}¥${Money.format(record.amountCents)}',
                style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: color),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _EmptyPlaceholder extends StatelessWidget {
  final IconData icon;
  final String text;

  const _EmptyPlaceholder({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon,
              size: 64,
              color: AppColors.textSecondary.withValues(alpha: 0.4)),
          const SizedBox(height: 16),
          Text(text,
              style: const TextStyle(
                  fontSize: 14, color: AppColors.textSecondary)),
        ],
      ),
    );
  }
}

/// 待确认通知横幅（主页顶部，仅存在 pending 时显示）
class _PendingBanner extends StatelessWidget {
  final int count;
  final VoidCallback onTap;

  const _PendingBanner({required this.count, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 0),
      child: Material(
        key: const Key('pending_banner'),
        color: AppColors.primarySoft,
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(10),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Row(
              children: [
                const Icon(Icons.notifications_active,
                    size: 18, color: AppColors.primary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '有 $count 条待确认的通知',
                    style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: AppColors.primary),
                  ),
                ),
                Text('查看',
                    style: TextStyle(
                        fontSize: 13,
                        color: AppColors.primary.withValues(alpha: 0.8))),
                const Icon(Icons.chevron_right,
                    size: 18, color: AppColors.primary),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
