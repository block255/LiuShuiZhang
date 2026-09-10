import '../../models/category_config.dart';
import '../../models/record.dart';
import 'record_storage_io.dart'
    if (dart.library.html) 'record_storage_web.dart' as impl;

/// 账单存储接口：加载 / 全量保存 / 清空 / 清理时间标记 / 分类配置
/// Web 实现：浏览器 localStorage；Android：应用私有目录 JSON 文件；其它：内存占位
abstract class RecordStorage {
  Future<List<Record>> load();
  Future<void> save(List<Record> records);
  Future<void> clear();

  /// 上次自动清理时间（无记录返回 null）
  Future<DateTime?> loadLastClean();
  Future<void> saveLastClean(DateTime time);

  /// 分类配置（自定义分类 + 内置停用集合；无记录返回 null）
  Future<CategoryConfig?> loadCategoryConfig();
  Future<void> saveCategoryConfig(CategoryConfig config);
}

/// 平台选择入口
RecordStorage createRecordStorage() => impl.createRecordStorage();
