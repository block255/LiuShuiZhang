import 'package:flutter/material.dart';

import '../app_theme.dart';
import '../data/record_store.dart';
import '../models/account.dart';
import '../models/record.dart';
import '../utils/money.dart';
import '../utils/record_time.dart';
import '../widgets/account_badge.dart';
import 'add_record_page.dart';

/// 待确认管理页（通知解析出的 pending 记录在这里确认入账/编辑/删除）
///
/// - 行点击 = 编辑（复用 AddRecordPage：补对方/分类/金额/方向等）
/// - 行尾 ✓ = 单条确认；长按/右键 = 菜单
/// - 右上「全部确认」一键入账；顶部「批量」进入批量模式（确认/删除）
class PendingPage extends StatefulWidget {
  const PendingPage({super.key});

  @override
  State<PendingPage> createState() => _PendingPageState();
}

class _PendingPageState extends State<PendingPage> {
  bool _bulkMode = false;
  final Set<String> _selectedIds = {};

  List<Record> get _pending => RecordStore.instance.pending().records;

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

  void _snack(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), duration: const Duration(seconds: 2)),
    );
  }

  // ── 单条动作 ──

  void _confirmOne(Record r) {
    RecordStore.instance
        .update(r.copyWith(status: RecordStatus.confirmed));
    _snack('已确认入账：${Money.format(r.amountCents)} 元');
  }

  Future<void> _deleteOne(Record r) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除这条待确认通知？'),
        content: Text('删除后不可恢复：${Money.format(r.amountCents)} 元'
            '（${r.counterpart ?? '未知对方'}）'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('取消'),
          ),
          TextButton(
            key: const Key('pending_delete_confirm'),
            onPressed: () => Navigator.of(ctx).pop(true),
            style: TextButton.styleFrom(foregroundColor: AppColors.expense),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (ok == true) {
      RecordStore.instance.remove(r.id);
      _snack('已删除');
    }
  }

  void _openEdit(Record r) {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => AddRecordPage(editRecord: r)),
    );
  }

  void _showRowMenu(Record r) {
    showModalBottomSheet<void>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              key: const Key('pending_menu_confirm'),
              leading: Icon(Icons.check_circle_outline,
                  color: AppColors.income),
              title: const Text('确认入账'),
              onTap: () {
                Navigator.of(ctx).pop();
                _confirmOne(r);
              },
            ),
            ListTile(
              key: const Key('pending_menu_edit'),
              leading: const Icon(Icons.edit_outlined),
              title: const Text('编辑（补对方/分类等）'),
              onTap: () {
                Navigator.of(ctx).pop();
                _openEdit(r);
              },
            ),
            ListTile(
              key: const Key('pending_menu_delete'),
              leading: const Icon(Icons.delete_outline,
                  color: AppColors.expense),
              title: const Text('删除',
                  style: TextStyle(color: AppColors.expense)),
              onTap: () {
                Navigator.of(ctx).pop();
                _deleteOne(r);
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  // ── 全部确认 ──

  void _confirmAll() {
    final list = _pending;
    if (list.isEmpty) return;
    final store = RecordStore.instance;
    for (final r in list) {
      store.update(r.copyWith(status: RecordStatus.confirmed));
    }
    _snack('已确认 ${list.length} 条入账');
  }

  // ── 批量模式 ──

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

  bool get _allSelected =>
      _pending.isNotEmpty && _pending.every((r) => _selectedIds.contains(r.id));

  void _toggleSelectAll() {
    setState(() {
      if (_allSelected) {
        _selectedIds.clear();
      } else {
        _selectedIds
          ..clear()
          ..addAll(_pending.map((r) => r.id));
      }
    });
  }

  /// 批量确认：仅处理仍处于 pending 的选中记录（防重复）
  void _confirmSelected() {
    final store = RecordStore.instance;
    final targets = store.pending().records
        .where((r) => _selectedIds.contains(r.id))
        .toList();
    for (final r in targets) {
      store.update(r.copyWith(status: RecordStatus.confirmed));
    }
    setState(() {
      _bulkMode = false;
      _selectedIds.clear();
    });
    _snack('已确认 ${targets.length} 条入账');
  }

  Future<void> _confirmDeleteSelected() async {
    final n = _selectedIds.length;
    if (n == 0) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('删除选中的 $n 条待确认通知？'),
        content: const Text('删除后不可恢复。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('取消'),
          ),
          TextButton(
            key: const Key('pending_bulk_delete_confirm'),
            onPressed: () => Navigator.of(ctx).pop(true),
            style: TextButton.styleFrom(foregroundColor: AppColors.expense),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    final store = RecordStore.instance;
    for (final id in _selectedIds.toList()) {
      store.remove(id);
    }
    setState(() {
      _bulkMode = false;
      _selectedIds.clear();
    });
    _snack('已删除 $n 条');
  }

  // ── UI ──

  @override
  Widget build(BuildContext context) {
    final pendings = _pending;
    final n = pendings.length;

    return Scaffold(
      appBar: AppBar(
        leading: _bulkMode
            ? IconButton(
                key: const Key('pending_bulk_exit'),
                icon: const Icon(Icons.close),
                onPressed: _exitBulk,
              )
            : null,
        title: Text(_bulkMode ? '已选 ${_selectedIds.length} 项' : '待确认 ($n)'),
        actions: [
          if (_bulkMode)
            TextButton(
              key: const Key('pending_bulk_select_all'),
              onPressed: pendings.isEmpty ? null : _toggleSelectAll,
              child: Text(_allSelected ? '取消全选' : '全选'),
            )
          else ...[
            TextButton(
              key: const Key('pending_bulk_enter'),
              onPressed: n == 0 ? null : _enterBulk,
              child: const Text('批量'),
            ),
            if (n > 0)
              TextButton(
                key: const Key('pending_confirm_all'),
                onPressed: _confirmAll,
                style: TextButton.styleFrom(
                    foregroundColor: AppColors.income),
                child: const Text('全部确认',
                    style: TextStyle(fontWeight: FontWeight.w600)),
              ),
            const SizedBox(width: 4),
          ],
        ],
      ),
      body: n == 0
          ? const _EmptyState()
          : ListView.separated(
              padding: const EdgeInsets.only(bottom: 88),
              itemCount: n,
              separatorBuilder: (_, _) =>
                  const Divider(indent: 72, endIndent: 16),
              itemBuilder: (_, i) {
                final r = pendings[i];
                return _PendingRow(
                  record: r,
                  selectMode: _bulkMode,
                  selected: _selectedIds.contains(r.id),
                  onTap: () {
                    if (_bulkMode) {
                      _toggleSelect(r.id);
                    } else {
                      _openEdit(r);
                    }
                  },
                  onLongPress: () {
                    if (_bulkMode) {
                      _toggleSelect(r.id);
                    } else {
                      _showRowMenu(r);
                    }
                  },
                  onConfirm: () => _confirmOne(r),
                );
              },
            ),
      bottomNavigationBar: _bulkMode
          ? SafeArea(
              child: Container(
                key: const Key('pending_bulk_bar'),
                padding: const EdgeInsets.symmetric(horizontal: 16),
                decoration: BoxDecoration(
                  color: AppColors.background,
                  border:
                      const Border(top: BorderSide(color: AppColors.divider)),
                ),
                child: Row(
                  children: [
                    TextButton.icon(
                      key: const Key('pending_bulk_confirm'),
                      onPressed: _selectedIds.isEmpty
                          ? null
                          : _confirmSelected,
                      icon: const Icon(Icons.check_circle_outline, size: 20),
                      label: Text(
                          '确认${_selectedIds.isEmpty ? '' : ' ${_selectedIds.length}'}'),
                      style: TextButton.styleFrom(
                          foregroundColor: AppColors.income),
                    ),
                    const Spacer(),
                    TextButton.icon(
                      key: const Key('pending_bulk_delete'),
                      onPressed: _selectedIds.isEmpty
                          ? null
                          : _confirmDeleteSelected,
                      icon: const Icon(Icons.delete_outline, size: 20),
                      label: Text(
                          '删除${_selectedIds.isEmpty ? '' : ' ${_selectedIds.length}'}'),
                      style: TextButton.styleFrom(
                          foregroundColor: AppColors.expense),
                    ),
                  ],
                ),
              ),
            )
          : null,
    );
  }
}

/// 待确认行：账户徽标 | 对方/未知 + 时间 | ±金额 + ✓确认
class _PendingRow extends StatelessWidget {
  final Record record;
  final bool selectMode;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback onLongPress;
  final VoidCallback onConfirm;

  const _PendingRow({
    required this.record,
    required this.selectMode,
    required this.selected,
    required this.onTap,
    required this.onLongPress,
    required this.onConfirm,
  });

  @override
  Widget build(BuildContext context) {
    final isExpense = record.type == RecordType.expense;
    final color = isExpense ? AppColors.expense : AppColors.income;
    final mainText = record.counterpart?.isNotEmpty == true
        ? record.counterpart!
        : '未知对方';
    String? accountName;
    for (final a in Account.builtin) {
      if (a.id == record.accountId) {
        accountName = a.name;
        break;
      }
    }
    final dirLabel = isExpense ? '支出' : '收入';
    final unknown = mainText == '未知对方';

    return InkWell(
      key: Key('pending_row_${record.id}'),
      onTap: onTap,
      onLongPress: onLongPress,
      child: Container(
        color: selectMode && selected
            ? AppColors.primarySoft.withValues(alpha: 0.5)
            : Colors.transparent,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Row(
            children: [
              if (selectMode) ...[
                SizedBox(
                  width: 24,
                  child: Icon(
                    selected
                        ? Icons.check_circle
                        : Icons.radio_button_unchecked,
                    size: 20,
                    color: selected
                        ? AppColors.primary
                        : AppColors.textSecondary,
                  ),
                ),
                const SizedBox(width: 8),
              ],
              AccountBadge(accountId: record.accountId, size: 40, iconSize: 20),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      mainText,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          fontSize: 15,
                          color: unknown
                              ? AppColors.textSecondary
                              : AppColors.textMain),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '$dirLabel · $accountName · ${formatRecordTime(record.time)}',
                      style: const TextStyle(
                          fontSize: 12, color: AppColors.textSecondary),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              if (selectMode)
                const SizedBox(width: 36)
              else
                IconButton(
                  key: Key('pending_confirm_${record.id}'),
                  tooltip: '确认入账',
                  visualDensity: VisualDensity.compact,
                  onPressed: onConfirm,
                  icon: const Icon(Icons.check_circle_outline,
                      size: 26, color: AppColors.income),
                ),
              SizedBox(
                width: 84,
                child: Text(
                  '${isExpense ? '-' : '+'}¥${Money.format(record.amountCents)}',
                  textAlign: TextAlign.right,
                  style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: color),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.notifications_off_outlined,
              size: 64, color: AppColors.textSecondary),
          SizedBox(height: 16),
          Text('没有待确认的通知了',
              style:
                  TextStyle(fontSize: 14, color: AppColors.textSecondary)),
        ],
      ),
    );
  }
}
