import '../../models/category_config.dart';
import '../../models/record.dart';
import 'record_storage.dart';

/// 内存占位实现（非 Web 且非 Android 的平台，如桌面调试/测试环境）
class MemoryRecordStorage implements RecordStorage {
  List<Record> _data = [];
  DateTime? _lastClean;
  CategoryConfig? _categoryConfig;

  @override
  Future<List<Record>> load() async => List.of(_data);

  @override
  Future<void> save(List<Record> records) async {
    _data = List.of(records);
  }

  @override
  Future<void> clear() async => _data = [];

  @override
  Future<DateTime?> loadLastClean() async => _lastClean;

  @override
  Future<void> saveLastClean(DateTime time) async => _lastClean = time;

  @override
  Future<CategoryConfig?> loadCategoryConfig() async => _categoryConfig;

  @override
  Future<void> saveCategoryConfig(CategoryConfig config) async {
    _categoryConfig = config;
  }
}
