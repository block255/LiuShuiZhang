import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app_theme.dart';
import '../data/category_store.dart';
import '../data/record_store.dart';
import '../models/account.dart';
import '../models/category.dart';
import '../models/record.dart';
import '../utils/money.dart';
import '../widgets/category_icon.dart';

/// 记一笔 / 编辑账单页（S3 + 编辑模式）
/// [editRecord] 非空 = 编辑模式（预填 + 保存更新 + 可删除）
class AddRecordPage extends StatefulWidget {
  final Record? editRecord;

  const AddRecordPage({super.key, this.editRecord});

  @override
  State<AddRecordPage> createState() => _AddRecordPageState();
}

class _AddRecordPageState extends State<AddRecordPage> {
  final _amountCtrl = TextEditingController();
  final _noteCtrl = TextEditingController();
  final _counterpartCtrl = TextEditingController();

  RecordType _type = RecordType.expense;
  String? _categoryId; // null = 保存时归"其他"
  String _accountId = Account.wechat.id;

  bool get _isEdit => widget.editRecord != null;

  @override
  void initState() {
    super.initState();
    final edit = widget.editRecord;
    if (edit != null) {
      // 编辑模式：预填原记录
      _type = edit.type;
      _categoryId = edit.categoryId;
      _accountId = edit.accountId;
      _amountCtrl.text = Money.toInput(edit.amountCents);
      if (edit.note != null) _noteCtrl.text = edit.note!;
      if (edit.counterpart != null) _counterpartCtrl.text = edit.counterpart!;
    } else {
      // 新增：默认选中"其他"类
      _categoryId = _defaultCategoryId(_type);
    }
  }

  @override
  void dispose() {
    _amountCtrl.dispose();
    _noteCtrl.dispose();
    _counterpartCtrl.dispose();
    super.dispose();
  }

  String _defaultCategoryId(RecordType type) {
    final others =
        allCategories.where((c) => c.type == type && c.id.contains('other'));
    if (others.isNotEmpty) return others.first.id;
    return categoriesOf(type).last.id;
  }

  void _switchType(RecordType t) {
    if (t == _type) return;
    setState(() {
      _type = t;
      // 当前分类不属于新类型时，切到新类型的默认分类
      final c =
          _categoryId == null ? null : CategoryStore.instance.categoryById(_categoryId!);
      if (c == null || c.type != t) _categoryId = _defaultCategoryId(t);
    });
  }

  Color get _amountColor =>
      _type == RecordType.expense ? AppColors.expense : AppColors.income;

  void _save() {
    final cents = Money.parseYuanToCents(_amountCtrl.text);
    if (cents == null || cents <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请输入有效金额')),
      );
      return;
    }
    final note =
        _noteCtrl.text.trim().isEmpty ? null : _noteCtrl.text.trim();
    final counterpart = _counterpartCtrl.text.trim().isEmpty
        ? null
        : _counterpartCtrl.text.trim();
    final store = RecordStore.instance;

    final edit = widget.editRecord;
    if (edit != null) {
      // 编辑：整体替换可变字段（id/时间/单号/来源保持不变）
      store.update(edit.copyWith(
        accountId: _accountId,
        type: _type,
        amountCents: cents,
        categoryId: _categoryId,
        counterpart: counterpart,
        note: note,
      ));
    } else {
      store.add(Record(
        id: Record.newId(),
        accountId: _accountId,
        source: RecordSource.manual,
        type: _type,
        amountCents: cents,
        time: DateTime.now(),
        counterpart: counterpart,
        categoryId: _categoryId,
        note: note,
        status: RecordStatus.confirmed,
      ));
    }
    Navigator.of(context).pop();
  }

  Future<void> _delete() async {
    final edit = widget.editRecord;
    if (edit == null) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除这条记录？'),
        content: Text(
            '删除后不可恢复：${Money.format(edit.amountCents)} 元'
            '（${edit.counterpart ?? ''}）'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('取消'),
          ),
          TextButton(
            key: const Key('confirm_delete_btn'),
            onPressed: () => Navigator.of(ctx).pop(true),
            style: TextButton.styleFrom(foregroundColor: AppColors.expense),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    RecordStore.instance.remove(edit.id);
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_isEdit ? '编辑账单' : '记一笔'),
        actions: [
          if (_isEdit)
            IconButton(
              key: const Key('delete_record_btn'),
              onPressed: _delete,
              tooltip: '删除',
              icon: const Icon(Icons.delete_outline,
                  color: AppColors.expense),
            ),
          TextButton(
            onPressed: _save,
            child: const Text('保存',
                style: TextStyle(
                    color: AppColors.primary,
                    fontSize: 16,
                    fontWeight: FontWeight.w600)),
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // ── 收支类型切换 ──
          SegmentedButton<RecordType>(
            segments: const [
              ButtonSegment(
                value: RecordType.expense,
                label: Text('支出'),
                icon: Icon(Icons.arrow_upward, size: 16),
              ),
              ButtonSegment(
                value: RecordType.income,
                label: Text('收入'),
                icon: Icon(Icons.arrow_downward, size: 16),
              ),
            ],
            selected: {_type},
            onSelectionChanged: (s) => _switchType(s.first),
            style: SegmentedButton.styleFrom(
              selectedBackgroundColor: AppColors.primarySoft,
              selectedForegroundColor: AppColors.primary,
              foregroundColor: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: 20),
          // ── 金额输入（主角：大字号）──
          TextField(
            key: const Key('amount_field'),
            controller: _amountCtrl,
            autofocus: true,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
            ],
            style: TextStyle(
              fontSize: 36,
              fontWeight: FontWeight.w700,
              color: _amountColor,
            ),
            decoration: InputDecoration(
              prefixText: '¥ ',
              prefixStyle: TextStyle(
                fontSize: 30,
                fontWeight: FontWeight.w700,
                color: _amountColor,
              ),
              hintText: '0.00',
              hintStyle: TextStyle(
                fontSize: 36,
                fontWeight: FontWeight.w700,
                color: AppColors.textSecondary.withValues(alpha: 0.3),
              ),
              border: InputBorder.none,
            ),
          ),
          const Divider(),
          const SizedBox(height: 12),
          // ── 分类选择 ──
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              for (final c in CategoryStore.instance.categoriesOf(_type))
                _CategoryChip(
                  category: c,
                  selected: c.id == _categoryId,
                  onTap: () => setState(() => _categoryId = c.id),
                ),
            ],
          ),
          const SizedBox(height: 20),
          // ── 账户选择 ──
          Row(
            children: [
              Text('账户',
                  style: TextStyle(
                      color: AppColors.textSecondary, fontSize: 14)),
              const SizedBox(width: 16),
              for (final a in Account.builtin) ...[
                ChoiceChip(
                  label: Text(a.name),
                  selected: _accountId == a.id,
                  onSelected: (_) => setState(() => _accountId = a.id),
                  selectedColor: AppColors.primarySoft,
                  labelStyle: TextStyle(
                    color: _accountId == a.id
                        ? AppColors.primary
                        : AppColors.textSecondary,
                    fontSize: 13,
                  ),
                  side: BorderSide(
                      color: _accountId == a.id
                          ? AppColors.primary
                          : AppColors.divider),
                ),
                const SizedBox(width: 8),
              ],
            ],
          ),
          const SizedBox(height: 20),
          // ── 对方/商户（可选；通知待确认补对方也走这里）──
          TextField(
            key: const Key('counterpart_field'),
            controller: _counterpartCtrl,
            decoration: const InputDecoration(
              hintText: '对方/商户（可选）',
              hintStyle: TextStyle(color: AppColors.textSecondary),
              enabledBorder: UnderlineInputBorder(
                borderSide: BorderSide(color: AppColors.divider),
              ),
              focusedBorder: UnderlineInputBorder(
                borderSide: BorderSide(color: AppColors.primary),
              ),
            ),
          ),
          const SizedBox(height: 12),
          // ── 备注 ──
          TextField(
            key: const Key('note_field'),
            controller: _noteCtrl,
            decoration: const InputDecoration(
              hintText: '备注（可选）',
              hintStyle: TextStyle(color: AppColors.textSecondary),
              enabledBorder: UnderlineInputBorder(
                borderSide: BorderSide(color: AppColors.divider),
              ),
              focusedBorder: UnderlineInputBorder(
                borderSide: BorderSide(color: AppColors.primary),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            '记录时间：刚刚',
            style: TextStyle(
                color: AppColors.textSecondary.withValues(alpha: 0.6),
                fontSize: 12),
          ),
        ],
      ),
    );
  }
}

/// 分类图标选择项
class _CategoryChip extends StatelessWidget {
  final Category category;
  final bool selected;
  final VoidCallback onTap;

  const _CategoryChip({
    required this.category,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      key: Key('cat_${category.id}'),
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? AppColors.primarySoft : AppColors.surfaceGroup,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: selected ? AppColors.primary : AppColors.divider,
            width: selected ? 1.5 : 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            CategoryIcon(
                category: category,
                size: 18,
                color: selected ? AppColors.primary : AppColors.textSecondary),
            const SizedBox(width: 6),
            Text(
              category.name,
              style: TextStyle(
                fontSize: 13,
                fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                color: selected ? AppColors.primary : AppColors.textMain,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
