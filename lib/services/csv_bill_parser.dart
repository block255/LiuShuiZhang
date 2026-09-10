import '../models/record.dart';

/// 一条解析出的账单条目（导入预览用，尚未分配 id/入库）
class ParsedBill {
  final DateTime time;
  final RecordType type;
  final int amountCents;
  final String counterpart;
  final String? orderId;
  final String rawStatus; // 原始状态文本（如"支付成功"/"已退款"）

  const ParsedBill({
    required this.time,
    required this.type,
    required this.amountCents,
    required this.counterpart,
    this.orderId,
    this.rawStatus = '',
  });
}

/// 解析结果：有效条目 + 被跳过的原因统计
class ParseResult {
  final List<ParsedBill> bills;
  final int skippedRows; // 跳过的行数（退款/失败/无法识别等）

  const ParseResult({required this.bills, required this.skippedRows});

  bool get isEmpty => bills.isEmpty && skippedRows == 0;
}

/// 微信/支付宝账单 CSV 解析器
///
/// 兼容策略：按"表头关键词"定位列，不依赖固定列序，因此同时支持
/// 微信（下载账单）与支付宝（交易流水证明）两种导出格式。
class CsvBillParser {
  /// 平台特征：用于解析后提示/测试
  static const wechatHints = ['交易单号', '商户单号', '支付方式', '零钱'];
  static const alipayHints = ['交易号', '商家订单号', '收/付款方式', '交易来源地'];

  /// 解析整段 CSV 文本（行内无表头扫描，假定首行即表头——兼容旧测试/手写 CSV）。
  /// 真实导出文件请用 [parseRows]（自动跳过文件头信息行）。
  static ParseResult parse(String csv, {DateTime? now}) {
    final lines = splitCsvLines(csv);
    if (lines.isEmpty) return const ParseResult(bills: [], skippedRows: 0);
    final rows = lines.map(parseCsvRowCell).toList();
    return parseRows(rows);
  }

  /// 解析任意来源的行列表（CSV 行或 xlsx 行）。
  /// 自动扫描包含"交易时间"+“收/支”的表头行，跳过其前的导出信息/提示行。
  static ParseResult parseRows(List<List<String>> rows) {
    if (rows.isEmpty) return const ParseResult(bills: [], skippedRows: 0);

    // 找表头行：含"交易时间"与"收/支"关键列
    var headerIdx = -1;
    for (var i = 0; i < rows.length; i++) {
      final row = rows[i];
      final joined = row.join(',');
      if (joined.contains('交易时间') &&
          (joined.contains('收/支') || joined.contains('金额'))) {
        headerIdx = i;
        break;
      }
    }
    if (headerIdx < 0) return const ParseResult(bills: [], skippedRows: 0);

    // 去掉 BOM（首个单元格可能残留）
    final header = rows[headerIdx].map((c) => c.replaceFirst('\uFEFF', '')).toList();
    final col = _ColumnMap.fromHeaders(header);
    if (!col.valid) return const ParseResult(bills: [], skippedRows: 0);

    final bills = <ParsedBill>[];
    var skipped = 0;
    for (final row in rows.skip(headerIdx + 1)) {
      // 跳过完全空行
      if (row.every((c) => c.trim().isEmpty)) continue;
      if (row.length < 3) {
        skipped++;
        continue;
      }
      final parsed = _parseRow(row, col);
      if (parsed == null) {
        skipped++;
        continue;
      }
      bills.add(parsed);
    }
    return ParseResult(bills: bills, skippedRows: skipped);
  }

  static ParsedBill? _parseRow(List<String> row, _ColumnMap col) {
    String cell(_ColKey k) => col.get(row, k);

    // 状态过滤：仅跳过"退款/失败/关闭"等非成功终态。
    // 注意："对方已收钱"是微信转账的【正常完成状态】（不是异常），必须保留！
    final status = cell(_ColKey.status);
    if (status.isNotEmpty) {
      if (status.contains('退款') || status.contains('失败') ||
          status.contains('关闭')) {
        return null;
      }
    }

    // 收/支方向
    final dir = cell(_ColKey.direction).trim();
    final RecordType? type = switch (dir) {
      '支出' || 'pay' => RecordType.expense,
      '收入' || 'receive' => RecordType.income,
      _ => null, // "中奖""其他""不计收支"等不记
    };
    if (type == null) return null;

    // 时间
    final time = _parseTime(cell(_ColKey.time));
    if (time == null) return null;

    // 金额（去 ¥/, 空格；可能带负号）
    final cents = _parseAmount(cell(_ColKey.amount));
    if (cents == null || cents <= 0) return null;

    // 对方/商品（对方为空用商品兜底）
    var counterpart = cell(_ColKey.counterpart).trim();
    if (counterpart.isEmpty) counterpart = cell(_ColKey.item).trim();

    final orderId = cell(_ColKey.orderId).trim();
    return ParsedBill(
      time: time,
      type: type,
      amountCents: cents,
      counterpart: counterpart,
      orderId: orderId.isEmpty ? null : orderId,
      rawStatus: status,
    );
  }

  // ── 工具（公开给文件读取层复用）──

  /// 文本按行拆分（兼容 \r\n / \n，去空行）
  static List<String> splitCsvLines(String text) {
    final norm = text.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
    return norm.split('\n').where((l) => l.trim().isNotEmpty).toList();
  }

  /// 标准 CSV 行解析：支持引号包裹（含逗号/引号转义）
  static List<String> parseCsvRowCell(String line) {
    final result = <String>[];
    final buf = StringBuffer();
    var inQuotes = false;
    for (var i = 0; i < line.length; i++) {
      final ch = line[i];
      if (inQuotes) {
        if (ch == '"') {
          if (i + 1 < line.length && line[i + 1] == '"') {
            buf.write('"');
            i++;
          } else {
            inQuotes = false;
          }
        } else {
          buf.write(ch);
        }
      } else {
        if (ch == '"') {
          inQuotes = true;
        } else if (ch == ',') {
          result.add(buf.toString());
          buf.clear();
        } else {
          buf.write(ch);
        }
      }
    }
    result.add(buf.toString());
    return result;
  }

  static DateTime? _parseTime(String s) {
    final t = s.trim();
    if (t.isEmpty) return null;
    // "yyyy-MM-dd HH:mm:ss" 或 "yyyy/MM/dd HH:mm:ss"
    final m = RegExp(r'^(\d{4})[-/](\d{1,2})[-/](\d{1,2})[ T](\d{1,2}):(\d{1,2})(?::(\d{1,2}))?')
        .firstMatch(t);
    if (m == null) return null;
    return DateTime(
      int.parse(m.group(1)!),
      int.parse(m.group(2)!),
      int.parse(m.group(3)!),
      int.parse(m.group(4)!),
      int.parse(m.group(5)!),
      m.group(6) == null ? 0 : int.parse(m.group(6)!),
    );
  }

  static int? _parseAmount(String s) {
    final t = s.trim().replaceAll(',', '').replaceAll('¥', '').replaceAll('￥', '');
    if (t.isEmpty) return null;
    // 负号（如退款行金额为负）→ 解析后可能 <=0 由上层丢弃
    final v = double.tryParse(t);
    if (v == null) return null;
    return (v * 100).round();
  }
}

enum _ColKey { time, direction, amount, counterpart, item, orderId, status }

class _ColumnMap {
  final Map<_ColKey, int> _index = {};

  _ColumnMap.fromHeaders(List<String> headers) {
    for (var i = 0; i < headers.length; i++) {
      final h = headers[i].trim();
      final key = _match(h);
      if (key != null && !_index.containsKey(key)) {
        _index[key] = i;
      }
    }
  }

  bool get valid =>
      _index.containsKey(_ColKey.time) &&
      _index.containsKey(_ColKey.direction) &&
      _index.containsKey(_ColKey.amount);

  String get(List<String> row, _ColKey key) {
    final i = _index[key];
    if (i == null || i >= row.length) return '';
    return row[i];
  }

  static _ColKey? _match(String h) {
    if (h.contains('时间')) return _ColKey.time;
    if (h == '收/支' || h.contains('收支')) return _ColKey.direction;
    if (h.contains('金额')) return _ColKey.amount;
    if (h.contains('对方')) return _ColKey.counterpart;
    if (h.contains('商品') || h.contains('说明')) return _ColKey.item;
    if (h.contains('单号')) return _ColKey.orderId;
    if (h.contains('状态')) return _ColKey.status;
    return null;
  }
}
