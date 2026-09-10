/// 时间跨度：筛选用预设（S4）
enum TimeSpanType { all, thisMonth, lastMonth, last3Months, thisYear, custom }

extension TimeSpanTypeInfo on TimeSpanType {
  String get label => switch (this) {
        TimeSpanType.all => '全部时间',
        TimeSpanType.thisMonth => '本月',
        TimeSpanType.lastMonth => '上月',
        TimeSpanType.last3Months => '近3个月',
        TimeSpanType.thisYear => '今年',
        TimeSpanType.custom => '自定义',
      };
}

/// 跨度起止计算：返回 (start, endExclusive)
/// - [all] 等全量：返回 (null, null)
/// - 语义：start <= t < end
({DateTime? start, DateTime? end}) timeSpanRange(
  TimeSpanType type, {
  DateTime? now,
  DateTime? customStart,
  DateTime? customEnd,
}) {
  final n = now ?? DateTime.now();
  final year = n.year;
  final month = n.month;

  switch (type) {
    case TimeSpanType.all:
      return (start: null, end: null);
    case TimeSpanType.thisMonth:
      return (
        start: DateTime(year, month, 1),
        end: DateTime(year, month + 1, 1),
      );
    case TimeSpanType.lastMonth:
      return (
        start: DateTime(year, month - 1, 1),
        end: DateTime(year, month, 1),
      );
    case TimeSpanType.last3Months:
      // 含本月的近 3 个自然月
      return (
        start: DateTime(year, month - 2, 1),
        end: DateTime(year, month + 1, 1),
      );
    case TimeSpanType.thisYear:
      return (start: DateTime(year, 1, 1), end: DateTime(year + 1, 1, 1));
    case TimeSpanType.custom:
      if (customStart == null || customEnd == null) return (start: null, end: null);
      // 自定义为"包含 end 当天"：end 取次日 0 点（exclusive）
      final endExclusive = DateTime(customEnd.year, customEnd.month, customEnd.day + 1);
      return (
        start: DateTime(customStart.year, customStart.month, customStart.day),
        end: endExclusive,
      );
  }
}
