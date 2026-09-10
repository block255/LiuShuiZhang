import 'dart:io' show Platform;

import 'record_storage.dart';
import 'record_storage_file.dart';
import 'record_storage_stub.dart';

/// 非 Web 平台选择（record_storage.dart 的默认分支）：
/// - Android → 文件持久化（真机数据落地，B1）
/// - 其它平台（桌面/测试环境）→ 内存占位
RecordStorage createRecordStorage() =>
    Platform.isAndroid ? FileRecordStorage() : MemoryRecordStorage();
