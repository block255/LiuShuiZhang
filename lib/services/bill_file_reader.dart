import 'dart:convert';
import 'dart:typed_data';

import 'package:excel/excel.dart';
import 'package:fast_gbk/fast_gbk.dart';

import 'csv_bill_parser.dart';

/// 账单文件读取：把用户选择的 .csv / .xlsx 统一转为"行列表"，交给解析器。
/// - CSV：编码自动检测（先按 UTF-8 严格解码，失败按 GBK——支付宝导出的 CSV 为 GBK）
/// - XLSX：Excel 表格转行（微信新版导出为 xlsx，表头前带导出信息行，由解析器跳过）
class BillFileReader {
  static Future<List<List<String>>> readRows(
      String fileName, Uint8List bytes) async {
    final lower = fileName.toLowerCase();
    if (lower.endsWith('.xlsx')) {
      return _readXlsx(bytes);
    }
    // csv / txt / 其他：按文本处理
    return _readCsv(bytes);
  }

  static List<List<String>> _readCsv(Uint8List bytes) {
    String text;
    try {
      text = utf8.decode(bytes); // 严格模式：GBK 内容会抛异常
    } on FormatException {
      text = gbk.decode(bytes); // 支付宝导出的 CSV 为 GBK 编码
    }
    // 去 BOM
    if (text.startsWith('\uFEFF')) text = text.substring(1);
    return CsvBillParser
        .splitCsvLines(text)
        .map(CsvBillParser.parseCsvRowCell)
        .toList();
  }

  static List<List<String>> _readXlsx(Uint8List bytes) {
    final excel = Excel.decodeBytes(bytes);
    if (excel.tables.isEmpty) return [];
    // 选行数最多的 sheet（跳过创建工具自带的空表/说明表）
    final sheet = excel.tables.values.reduce(
        (a, b) => a.rows.length >= b.rows.length ? a : b);
    return sheet.rows
        .map((row) => row
            .map((cell) => cell?.value?.toString() ?? '')
            .toList())
        .toList();
  }
}
