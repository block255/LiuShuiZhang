import 'package:flutter/material.dart';

import '../app_theme.dart';
import '../data/category_store.dart';
import '../models/record.dart';
import '../widgets/category_icon.dart';

/// 分类管理页：新增自定义分类（名称+图标）、删除自定义、停用/启用内置。
/// 历史记录引用删除/停用的分类时自动回退"未分类"（categoryById 兜底已安全）。
class CategoryManagePage extends StatefulWidget {
  const CategoryManagePage({super.key});

  @override
  State<CategoryManagePage> createState() => _CategoryManagePageState();
}

class _CategoryManagePageState extends State<CategoryManagePage> {
  RecordType _type = RecordType.expense;

  @override
  void initState() {
    super.initState();
    CategoryStore.instance.addListener(_onStoreChanged);
  }

  @override
  void dispose() {
    CategoryStore.instance.removeListener(_onStoreChanged);
    super.dispose();
  }

  void _onStoreChanged() {
    if (mounted) setState(() {});
  }

  void _snack(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(msg), duration: const Duration(seconds: 2)));
  }

  Future<void> _openAdd() async {
    final nameCtrl = TextEditingController();
    var iconKey = 'other';
    final created = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: Text(_type == RecordType.expense ? '新增支出分类' : '新增收入分类'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  key: const Key('custom_cat_name'),
                  controller: nameCtrl,
                  autofocus: true,
                  decoration: const InputDecoration(
                    hintText: '分类名称（如 学习、宠物）',
                    hintStyle: TextStyle(fontSize: 13),
                    isDense: true,
                  ),
                ),
                const SizedBox(height: 16),
                // 图标宫格
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final e in categoryIconChoices.entries)
                      InkWell(
                        key: Key('icon_${e.key}'),
                        onTap: () => setDialogState(() => iconKey = e.key),
                        borderRadius: BorderRadius.circular(10),
                        child: Container(
                          width: 38,
                          height: 38,
                          decoration: BoxDecoration(
                            color: iconKey == e.key
                                ? AppColors.primarySoft
                                : AppColors.surfaceGroup,
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                              color: iconKey == e.key
                                  ? AppColors.primary
                                  : AppColors.divider,
                              width: iconKey == e.key ? 1.5 : 1,
                            ),
                          ),
                          child: Icon(e.value,
                              size: 19,
                              color: iconKey == e.key
                                  ? AppColors.primary
                                  : AppColors.textSecondary),
                        ),
                      ),
                    // 彩蛋：DeepSeek 鲸鱼 logo（图片类图标）
                    InkWell(
                      key: const Key('icon_asset_deepseek'),
                      onTap: () => setDialogState(
                          () => iconKey = '${kAssetIconPrefix}deepseek'),
                      borderRadius: BorderRadius.circular(10),
                      child: Container(
                        width: 38,
                        height: 38,
                        decoration: BoxDecoration(
                          color:
                              iconKey == '${kAssetIconPrefix}deepseek'
                                  ? AppColors.primarySoft
                                  : AppColors.surfaceGroup,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: iconKey == '${kAssetIconPrefix}deepseek'
                                ? AppColors.primary
                                : AppColors.divider,
                            width:
                                iconKey == '${kAssetIconPrefix}deepseek'
                                    ? 1.5
                                    : 1,
                          ),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.all(8),
                          child: Image.asset('assets/icons/deepseek.png',
                              fit: BoxFit.contain),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('取消'),
            ),
            TextButton(
              key: const Key('custom_cat_save'),
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('添加',
                  style: TextStyle(
                      color: AppColors.primary,
                      fontWeight: FontWeight.w600)),
            ),
          ],
        ),
      ),
    );
    if (created != true || !mounted) return;
    final name = nameCtrl.text.trim();
    if (name.isEmpty) {
      _snack('请输入分类名称');
      return;
    }
    await CategoryStore.instance
        .addCustom(name: name, type: _type, iconKey: iconKey);
    _snack('已添加分类「$name」');
  }

  Future<void> _confirmRemove(String id, String name) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('删除分类「$name」？'),
        content: const Text('历史记录不受影响（将显示为未分类）。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('取消'),
          ),
          TextButton(
            key: const Key('custom_cat_delete_confirm'),
            onPressed: () => Navigator.of(ctx).pop(true),
            style: TextButton.styleFrom(foregroundColor: AppColors.expense),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (ok == true) {
      await CategoryStore.instance.removeCustom(id);
    }
  }

  @override
  Widget build(BuildContext context) {
    final store = CategoryStore.instance;
    final all = store.categoriesOfAll(_type);
    return Scaffold(
      appBar: AppBar(
        title: const Text('分类管理'),
        actions: [
          TextButton.icon(
            key: const Key('cat_add'),
            onPressed: _openAdd,
            icon: const Icon(Icons.add, size: 18),
            label: const Text('添加'),
            style: TextButton.styleFrom(
                foregroundColor: AppColors.primary),
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: Column(
        children: [
          // 收支类型切换
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
            child: SegmentedButton<RecordType>(
              segments: const [
                ButtonSegment(
                    value: RecordType.expense,
                    label: Text('支出分类'),
                    icon: Icon(Icons.arrow_upward, size: 15)),
                ButtonSegment(
                    value: RecordType.income,
                    label: Text('收入分类'),
                    icon: Icon(Icons.arrow_downward, size: 15)),
              ],
              selected: {_type},
              onSelectionChanged: (s) => setState(() => _type = s.first),
              style: SegmentedButton.styleFrom(
                selectedBackgroundColor: AppColors.primarySoft,
                selectedForegroundColor: AppColors.primary,
                foregroundColor: AppColors.textSecondary,
                visualDensity: VisualDensity.compact,
              ),
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: ListView.separated(
              itemCount: all.length,
              separatorBuilder: (_, _) =>
                  const Divider(indent: 60, endIndent: 16, height: 1),
              itemBuilder: (_, i) {
                final c = all[i];
                final isBuiltin = !store.isCustom(c.id);
                return ListTile(
                  key: Key('cat_row_${c.id}'),
                  dense: true,
                  leading: Container(
                    width: 36,
                    height: 36,
                    decoration: const BoxDecoration(
                      color: AppColors.primarySoft,
                      shape: BoxShape.circle,
                    ),
                    child: CategoryIcon(
                        category: c, size: 18, color: AppColors.primary),
                  ),
                  title: Text(c.name,
                      style: const TextStyle(
                          fontSize: 14, color: AppColors.textMain)),
                  subtitle: isBuiltin
                      ? const Text('内置',
                          style: TextStyle(
                              fontSize: 11,
                              color: AppColors.textSecondary))
                      : null,
                  trailing: isBuiltin
                      ? Switch(
                          key: Key('cat_toggle_${c.id}'),
                          value: !store.isBuiltinDisabled(c.id),
                          onChanged: (v) => store
                              .setBuiltinDisabled(c.id, !v),
                          activeTrackColor: AppColors.primary,
                        )
                      : IconButton(
                          key: Key('cat_delete_${c.id}'),
                          icon: const Icon(Icons.delete_outline,
                              size: 20, color: AppColors.expense),
                          onPressed: () => _confirmRemove(c.id, c.name),
                        ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
