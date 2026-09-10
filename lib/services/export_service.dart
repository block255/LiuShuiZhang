import 'dart:convert';

import '../models/account.dart';
import '../models/category.dart';
import '../models/record.dart';

/// 数据导出：生成 CSV / JSON 文本（全量账单）
class ExportService {
  /// JSON 格式：完整保真（与 localStorage 同构，未来可做导入恢复）
  static String buildJson(List<Record> records) {
    return const JsonEncoder.withIndent('  ')
        .convert(records.map((r) => r.toJson()).toList());
  }

  /// CSV 格式：人类可读（Excel/WPS 可直接打开）
  static String buildCsv(List<Record> records) {
    final buf = StringBuffer()
      ..writeln('时间,账户,收支,金额(元),分类,对方,备注,交易单号,记录来源');
    for (final r in records) {
      final accountName = _accountName(r.accountId);
      final catName = r.categoryId == null
          ? ''
          : (categoryById(r.categoryId!)?.name ?? '');
      final fields = [
        _fmtTime(r.time),
        accountName,
        r.type == RecordType.expense ? '支出' : '收入',
        (r.amountCents / 100).toStringAsFixed(2),
        catName,
        r.counterpart ?? '',
        r.note ?? '',
        r.orderId ?? '',
        _sourceName(r.source),
      ];
      buf.writeln(fields.map(_escapeCsv).join(','));
    }
    return buf.toString();
  }

  static String _accountName(String id) {
    for (final a in Account.builtin) {
      if (a.id == id) return a.name;
    }
    return '未知账户';
  }

  static String _sourceName(RecordSource s) => switch (s) {
        RecordSource.manual => '手动',
        RecordSource.import => '导入',
        RecordSource.notify => '通知',
      };

  static String _fmtTime(DateTime t) {
    String p(int n) => n.toString().padLeft(2, '0');
    return '${t.year}-${p(t.month)}-${p(t.day)} ${p(t.hour)}:${p(t.minute)}:${p(t.second)}';
  }

  /// CSV 字段转义：含逗号/引号/换行时用引号包裹
  static String _escapeCsv(String s) {
    if (s.contains(',') || s.contains('"') || s.contains('\n')) {
      return '"${s.replaceAll('"', '""')}"';
    }
    return s;
  }
}
