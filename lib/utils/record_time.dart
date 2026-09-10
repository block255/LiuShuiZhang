/// 账单列表时间展示（相对化）
/// 今天 → "今天 12:30"；昨天 → "昨天 18:02"；今年 → "9月5日 14:00"；更早 → "2025年12月31日"
String formatRecordTime(DateTime t, {DateTime? now}) {
  final n = now ?? DateTime.now();
  final today = DateTime(n.year, n.month, n.day);
  final day = DateTime(t.year, t.month, t.day);
  final hm = '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
  final diff = today.difference(day).inDays;

  if (diff == 0) return '今天 $hm';
  if (diff == 1) return '昨天 $hm';
  if (t.year == n.year) return '${t.month}月${t.day}日 $hm';
  return '${t.year}年${t.month}月${t.day}日';
}
