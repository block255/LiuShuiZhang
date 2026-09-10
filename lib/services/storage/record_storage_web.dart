// Web 平台实现：浏览器 localStorage（JSON 全量序列化）
// ignore_for_file: avoid_web_libraries_in_flutter, deprecated_member_use
import 'dart:convert';
import 'dart:html' as html;

import '../../models/category_config.dart';
import '../../models/record.dart';
import 'record_storage.dart';

/// localStorage 键名（带版本号，数据结构升级时迁移）
const String kRecordsKey = 'lsz_records_v1';
const String kLastCleanKey = 'lsz_last_clean_v1';
const String kCategoryConfigKey = 'lsz_categories_v1';

class LocalStorageRecordStorage implements RecordStorage {
  final html.Storage _storage;

  LocalStorageRecordStorage([html.Storage? storage])
      : _storage = storage ?? html.window.localStorage;

  @override
  Future<List<Record>> load() async {
    final raw = _storage[kRecordsKey];
    if (raw == null || raw.isEmpty) return [];
    try {
      final list = jsonDecode(raw) as List<dynamic>;
      return list
          .map((e) => Record.fromJson((e as Map).cast<String, dynamic>()))
          .toList();
    } catch (e) {
      // 数据损坏时宁可返回空也不崩溃；原数据保留待排查
      return [];
    }
  }

  @override
  Future<void> save(List<Record> records) async {
    final json = jsonEncode(records.map((r) => r.toJson()).toList());
    try {
      _storage[kRecordsKey] = json;
    } catch (e) {
      // 配额超限等：抛给上层处理（触发紧急裁剪）
      throw StorageWriteException('存储写入失败：$e');
    }
  }

  @override
  Future<void> clear() async {
    _storage.remove(kRecordsKey);
  }

  @override
  Future<DateTime?> loadLastClean() async {
    final raw = _storage[kLastCleanKey];
    if (raw == null || raw.isEmpty) return null;
    return DateTime.tryParse(raw);
  }

  @override
  Future<void> saveLastClean(DateTime time) async {
    _storage[kLastCleanKey] = time.toIso8601String();
  }

  @override
  Future<CategoryConfig?> loadCategoryConfig() async {
    final raw = _storage[kCategoryConfigKey];
    if (raw == null || raw.isEmpty) return null;
    try {
      return CategoryConfig.fromJson(
          (jsonDecode(raw) as Map).cast<String, dynamic>());
    } catch (_) {
      return null;
    }
  }

  @override
  Future<void> saveCategoryConfig(CategoryConfig config) async {
    _storage[kCategoryConfigKey] = jsonEncode(config.toJson());
  }
}

/// 存储写入失败（通常为配额超限）
class StorageWriteException implements Exception {
  final String message;
  StorageWriteException(this.message);
  @override
  String toString() => message;
}

RecordStorage createRecordStorage() => LocalStorageRecordStorage();
