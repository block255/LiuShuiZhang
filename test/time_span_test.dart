import 'package:flutter_test/flutter_test.dart';

import 'package:bill_record_app/utils/time_span.dart';

void main() {
  // 固定"当前时间"：2026-09-05 15:30
  final now = DateTime(2026, 9, 5, 15, 30);

  group('timeSpanRange 起止计算', () {
    test('全部时间：不限', () {
      final r = timeSpanRange(TimeSpanType.all, now: now);
      expect(r.start, isNull);
      expect(r.end, isNull);
    });

    test('本月：9/1 含 ~ 10/1 不含', () {
      final r = timeSpanRange(TimeSpanType.thisMonth, now: now);
      expect(r.start, DateTime(2026, 9, 1));
      expect(r.end, DateTime(2026, 10, 1));
    });

    test('上月：8/1 ~ 9/1', () {
      final r = timeSpanRange(TimeSpanType.lastMonth, now: now);
      expect(r.start, DateTime(2026, 8, 1));
      expect(r.end, DateTime(2026, 9, 1));
    });

    test('近3个月（含本月）：7/1 ~ 10/1；跨年场景 1 月时回退到前一年', () {
      final r = timeSpanRange(TimeSpanType.last3Months, now: now);
      expect(r.start, DateTime(2026, 7, 1));
      expect(r.end, DateTime(2026, 10, 1));

      final jan = timeSpanRange(TimeSpanType.last3Months, now: DateTime(2026, 1, 10));
      expect(jan.start, DateTime(2025, 11, 1)); // 自动跨年
      expect(jan.end, DateTime(2026, 2, 1));
    });

    test('今年：1/1 ~ 次年 1/1', () {
      final r = timeSpanRange(TimeSpanType.thisYear, now: now);
      expect(r.start, DateTime(2026, 1, 1));
      expect(r.end, DateTime(2027, 1, 1));
    });

    test('自定义：含结束当天（end 取次日 0 点）', () {
      final r = timeSpanRange(
        TimeSpanType.custom,
        now: now,
        customStart: DateTime(2026, 9, 1),
        customEnd: DateTime(2026, 9, 10),
      );
      expect(r.start, DateTime(2026, 9, 1));
      expect(r.end, DateTime(2026, 9, 11));
    });

    test('自定义缺参数：退化为全部', () {
      final r = timeSpanRange(TimeSpanType.custom, now: now);
      expect(r.start, isNull);
      expect(r.end, isNull);
    });
  });

  group('TimeSpanType label', () {
    test('中文标签', () {
      expect(TimeSpanType.all.label, '全部时间');
      expect(TimeSpanType.thisMonth.label, '本月');
      expect(TimeSpanType.custom.label, '自定义');
    });
  });
}
