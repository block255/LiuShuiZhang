import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';

import '../../models/category_config.dart';
import '../../models/record.dart';
import 'record_storage.dart';

/// 目录提供者（异步：Android 需经 MethodChannel 取路径）
typedef DirectoryProvider = Future<Directory> Function();

/// 默认目录提供者：原生通道 `lsz_storage` → `getFilesDir`（Android 应用私有目录）
Future<Directory> defaultFilesDirProvider() async {
  const channel = MethodChannel('lsz_storage');
  final path = await channel.invokeMethod<String>('getFilesDir');
  if (path == null || path.isEmpty) {
    throw StateError('lsz_storage/getFilesDir 返回空路径');
  }
  return Directory(path);
}

/// 文件实现（纯 dart:io；Web 不可用）。
///
/// - 目录默认走 [defaultFilesDirProvider]，测试可注入临时目录
/// - 数据格式与 Web 版完全一致（同一套 Record JSON），将来换 SQLite 只换本实现
/// - 原子写：先写 .tmp 再改名，防写一半崩溃损坏文件；load 遇损坏文件兜底为空
class FileRecordStorage implements RecordStorage {
  FileRecordStorage({DirectoryProvider? directoryProvider})
      : _dirProvider = directoryProvider ?? defaultFilesDirProvider;

  final DirectoryProvider _dirProvider;
  Directory? _dir;

  static const _recordsFile = 'records.json';
  static const _lastCleanFile = 'last_clean.json';
  static const _categoryConfigFile = 'categories.json';

  Future<Directory> _ensureDir() async {
    final dir = _dir ??= await _dirProvider();
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  @override
  Future<List<Record>> load() async {
    final dir = await _ensureDir();
    final f = File('${dir.path}/$_recordsFile');    if (!await f.exists()) return [];
    try {
      final raw = await f.readAsString();
      if (raw.trim().isEmpty) return [];
      final list = jsonDecode(raw) as List<dynamic>;
      return list
          .map((e) => Record.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (_) {
      return []; // 损坏文件兜底：宁可空库，不让单条脏数据拖垮启动
    }
  }

  @override
  Future<void> save(List<Record> records) async {
    final dir = await _ensureDir();
    final f = File('${dir.path}/$_recordsFile');
    final tmp = File('${f.path}.tmp');
    await tmp.writeAsString(
      jsonEncode(records.map((r) => r.toJson()).toList()),
      flush: true,
    );
    // 原子替换（Windows rename 不覆盖已存在目标，先删旧的）
    if (await f.exists()) {
      await f.delete();
    }
    await tmp.rename(f.path);
  }

  @override
  Future<void> clear() async {
    final dir = await _ensureDir();
    for (final name in [_recordsFile, _lastCleanFile, '$_recordsFile.tmp']) {
      final f = File('${dir.path}/$name');
      if (await f.exists()) {
        await f.delete();
      }
    }
  }

  @override
  Future<DateTime?> loadLastClean() async {
    final dir = await _ensureDir();
    final f = File('${dir.path}/$_lastCleanFile');
    if (!await f.exists()) return null;
    try {
      final raw = await f.readAsString();
      final t = (jsonDecode(raw) as Map<String, dynamic>)['lastClean'];
      return t is String ? DateTime.tryParse(t) : null;
    } catch (_) {
      return null;
    }
  }

  @override
  Future<void> saveLastClean(DateTime time) async {
    final dir = await _ensureDir();
    await File('${dir.path}/$_lastCleanFile')
        .writeAsString(jsonEncode({'lastClean': time.toIso8601String()}));
  }

  @override
  Future<CategoryConfig?> loadCategoryConfig() async {
    final dir = await _ensureDir();
    final f = File('${dir.path}/$_categoryConfigFile');
    if (!await f.exists()) return null;
    try {
      final raw = await f.readAsString();
      if (raw.trim().isEmpty) return null;
      return CategoryConfig.fromJson(
          (jsonDecode(raw) as Map).cast<String, dynamic>());
    } catch (_) {
      return null;
    }
  }

  @override
  Future<void> saveCategoryConfig(CategoryConfig config) async {
    final dir = await _ensureDir();
    await File('${dir.path}/$_categoryConfigFile')
        .writeAsString(jsonEncode(config.toJson()));
  }
}
