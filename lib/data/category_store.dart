import 'package:flutter/material.dart';

import '../models/category.dart';
import '../models/category_config.dart';
import '../models/record.dart';
import '../services/storage/record_storage.dart';
import '../utils/app_log.dart';

/// 自定义分类可用图标库（key 持久化，value 展示）
const Map<String, IconData> categoryIconChoices = {
  'restaurant': Icons.restaurant,
  'fastfood': Icons.fastfood,
  'coffee': Icons.local_cafe,
  'bus': Icons.directions_bus,
  'subway': Icons.directions_subway,
  'car': Icons.directions_car,
  'shopping': Icons.shopping_bag,
  'cart': Icons.shopping_cart,
  'clothes': Icons.checkroom,
  'book': Icons.menu_book,
  'school': Icons.school,
  'movie': Icons.movie,
  'game': Icons.sports_esports,
  'pet': Icons.pets,
  'home': Icons.home,
  'medical': Icons.medical_services,
  'phone': Icons.phone_iphone,
  'sport': Icons.fitness_center,
  'gift': Icons.card_giftcard,
  'other': Icons.more_horiz,
};

IconData? iconByKey(String? key) =>
    key == null ? null : categoryIconChoices[key];

/// 图片类图标 key 前缀（如 "asset:deepseek" → assets/icons/deepseek.png）
const String kAssetIconPrefix = 'asset:';

/// 自定义分类规格 → 展示用 Category（含图片类图标解析）
Category customToCategory(CustomCategory c) {
  final key = c.iconKey;
  if (key.startsWith(kAssetIconPrefix)) {
    return Category(
      id: c.id,
      name: c.name,
      type: c.type,
      icon: Icons.more_horiz, // 占位（渲染层用 assetIcon）
      assetIcon: key.substring(kAssetIconPrefix.length),
    );
  }
  return Category(
    id: c.id,
    name: c.name,
    type: c.type,
    icon: iconByKey(key) ?? Icons.more_horiz,
  );
}

/// 分类仓库：内置分类（含停用状态） + 自定义分类 的动态视图。
/// 配置持久化复用 RecordStorage（web=localStorage 独立 key；android=categories.json）。
class CategoryStore extends ChangeNotifier {
  CategoryStore._(this._storage);

  static CategoryStore instance = CategoryStore._(createRecordStorage());

  /// 测试用：换掉全局实例
  @visibleForTesting
  static CategoryStore replaceForTest(RecordStorage storage) {
    instance = CategoryStore._(storage);
    return instance;
  }

  final RecordStorage _storage;
  bool _initialized = false;

  List<CustomCategory> _custom = [];
  Set<String> _disabled = {};

  bool get initialized => _initialized;

  /// 初始化：从存储恢复（幂等）
  Future<void> init() async {
    if (_initialized) return;
    _initialized = true;
    final cfg = await _storage.loadCategoryConfig();
    if (cfg != null) {
      _custom = List.of(cfg.customCategories);
      _disabled = Set.of(cfg.disabledBuiltinIds);
    }
  }

  // ── 查询 ──

  /// 某收支类型下的可见分类（内置未停用 + 自定义；"其他"固定排最末），记账/筛选用
  List<Category> categoriesOf(RecordType type) {
    final cats = [
      ...allCategories
          .where((c) => c.type == type && !_disabled.contains(c.id)),
      ..._custom
          .where((c) => c.type == type)
          .map(customToCategory),
    ];
    // "其他"（*_other）固定排最末，其余保持原顺序
    final others = cats.where((c) => c.id.endsWith('other')).toList();
    final rest = cats.where((c) => !c.id.endsWith('other')).toList();
    return [...rest, ...others];
  }

  /// 分类总量（含停用内置与自定义；管理页用）
  List<Category> categoriesOfAll(RecordType type) => [
        ...allCategories.where((c) => c.type == type),
        ..._custom
            .where((c) => c.type == type)
            .map(customToCategory),
      ];

  /// 按 id 查分类（内置 + 自定义），找不到返回 null
  Category? categoryById(String id) {
    for (final c in allCategories) {
      if (c.id == id) return c;
    }
    for (final c in _custom) {
      if (c.id == id) {
        return customToCategory(c);
      }
    }
    return null;
  }

  bool isBuiltinDisabled(String id) => _disabled.contains(id);

  /// 内置分类是否已停用（管理页开关状态）
  bool isCustom(String id) => _custom.any((c) => c.id == id);

  // ── 变更 ──

  /// 新增自定义分类（id 用 custom_ 前缀防冲突）
  Future<void> addCustom({
    required String name,
    required RecordType type,
    required String iconKey,
  }) async {
    _custom.add(CustomCategory(
      id: 'custom_${DateTime.now().microsecondsSinceEpoch}',
      name: name.trim(),
      type: type,
      iconKey: iconKey,
    ));
    notifyListeners();
    await _persist();
  }

  /// 删除自定义分类（历史记录引用自动回退"未分类"，categoryById 已安全）
  Future<void> removeCustom(String id) async {
    _custom.removeWhere((c) => c.id == id);
    notifyListeners();
    await _persist();
  }

  /// 停用 / 启用内置分类
  Future<void> setBuiltinDisabled(String id, bool disabled) async {
    if (disabled) {
      _disabled.add(id);
    } else {
      _disabled.remove(id);
    }
    notifyListeners();
    await _persist();
  }

  Future<void> _persist() async {
    try {
      await _storage.saveCategoryConfig(CategoryConfig(
        customCategories: _custom,
        disabledBuiltinIds: _disabled,
      ));
    } catch (e) {
      debugLog('[CategoryStore] 持久化失败: $e');
    }
  }
}
