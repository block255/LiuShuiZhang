import 'dart:convert';
import 'dart:typed_data';

import '../models/record.dart';

/// 备份解析结果
class BackupParseResult {
  final List<Record> records; // 有效记录
  final int skipped; // 损坏/非对象条目跳过数

  const BackupParseResult({required this.records, required this.skipped});
}

/// JSON 备份解析（导出备份的恢复闭环）
class RestoreService {
  RestoreService._();

  /// 解析备份 JSON（Record 列表）。文件损坏/非预期结构返回 null。
  /// 单条记录损坏容错跳过（Record.fromJson 兜底 + 类型防御）。
  static BackupParseResult? parse(Uint8List bytes) {
    try {
      final text = utf8.decode(bytes, allowMalformed: true);
      final decoded = jsonDecode(text);
      if (decoded is! List) return null;
      var skipped = 0;
      final records = <Record>[];
      for (final e in decoded) {
        if (e is! Map<String, dynamic>) {
          skipped++;
          continue;
        }
        try {
          records.add(Record.fromJson(e));
        } catch (_) {
          skipped++; // 单条结构损坏：跳过不拖垮整体
        }
      }
      return BackupParseResult(records: records, skipped: skipped);
    } catch (_) {
      return null; // 整体不是合法 JSON / 不是列表
    }
  }
}
