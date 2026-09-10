import 'record.dart';

/// 自定义分类规格（可持久化；图标存 key，UI 层映射 IconData）
class CustomCategory {
  final String id;
  final String name;
  final RecordType type;
  final String iconKey;

  const CustomCategory({
    required this.id,
    required this.name,
    required this.type,
    required this.iconKey,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'type': type.name,
        'iconKey': iconKey,
      };

  factory CustomCategory.fromJson(Map<String, dynamic> j) => CustomCategory(
        id: (j['id'] as String?) ?? '',
        name: (j['name'] as String?) ?? '未命名',
        type: RecordType.values.asNameMap()[j['type']] ??
            RecordType.expense,
        iconKey: (j['iconKey'] as String?) ?? 'other',
      );
}

/// 分类配置（自定义分类 + 内置停用集合）
class CategoryConfig {
  final List<CustomCategory> customCategories;
  final Set<String> disabledBuiltinIds;

  const CategoryConfig({
    this.customCategories = const [],
    this.disabledBuiltinIds = const {},
  });

  Map<String, dynamic> toJson() => {
        'custom': customCategories.map((c) => c.toJson()).toList(),
        'disabled': disabledBuiltinIds.toList(),
      };

  factory CategoryConfig.fromJson(Map<String, dynamic> j) => CategoryConfig(
        customCategories: ((j['custom'] as List?) ?? const [])
            .whereType<Map<String, dynamic>>()
            .map(CustomCategory.fromJson)
            .toList(),
        disabledBuiltinIds: ((j['disabled'] as List?) ?? const [])
            .whereType<String>()
            .toSet(),
      );
}
