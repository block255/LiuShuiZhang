/// 金额格式化工具（单位：分）
///
/// 全 App 金额以整数"分"存储与计算，仅在展示层转字符串。
class Money {
  /// 分 → 显示字符串：123456 → "1,234.56"
  static String format(int cents) {
    final sign = cents < 0 ? '-' : '';
    final abs = cents.abs();
    final yuan = abs ~/ 100;
    final fen = abs % 100;
    final yuanStr = _thousands(yuan);
    return '$sign$yuanStr.${fen.toString().padLeft(2, '0')}';
  }

  /// 分 → 输入框回显用（无千分位）：123456 → "1234.56"、1250 → "12.5"
  static String toInput(int cents) {
    final abs = cents.abs();
    final yuan = abs ~/ 100;
    final fen = (abs % 100).toString().padLeft(2, '0');
    var s = '$yuan.$fen';
    if (s.endsWith('0')) s = s.substring(0, s.length - 1); // 12.50 → 12.5
    if (s.endsWith('.')) s = s.substring(0, s.length - 1); // 12.0 → 12
    return s;
  }

  /// 元 → 分（解析输入用）："12.5" → 1250
  static int? parseYuanToCents(String input) {
    final s = input.trim();
    if (s.isEmpty) return null;
    final v = double.tryParse(s);
    if (v == null || v < 0) return null;
    return (v * 100).round();
  }

  static String _thousands(int n) {
    final s = n.toString();
    final buf = StringBuffer();
    for (var i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) buf.write(',');
      buf.write(s[i]);
    }
    return buf.toString();
  }
}
