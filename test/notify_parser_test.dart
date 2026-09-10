import 'package:bill_record_app/models/record.dart';
import 'package:bill_record_app/services/notify/notify_models.dart';
import 'package:bill_record_app/services/notify/notify_parser.dart';
import 'package:bill_record_app/services/notify/notify_samples.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('NotifyParser 样本库逐条断言', () {
    for (final s in notifySamples) {
      test(s.label, () {
        final msg = sampleMessage(s, arrival: DateTime(2026, 9, 7, 20, 30));
        final r = NotifyParser.parse(msg);
        expect(r.outcome, s.expect, reason: '解析结果：${r.reason}');
        if (s.expect == NotifyParseOutcome.ok) {
          expect(r.type, s.expectType, reason: '方向');
          expect(r.amountCents, s.expectCents, reason: '金额(分)');
          if (s.expectCounterpart != null) {
            expect(r.counterpart, s.expectCounterpart, reason: '对方');
          } else {
            expect(r.counterpart, isNull, reason: '对方应为空');
          }
          expect(r.reason, isEmpty);
        } else {
          expect(r.reason, isNotEmpty, reason: '失败/忽略需给人话原因');
        }
      });
    }
  });

  group('NotifyParser 补充边界', () {
    NotifyMessage msg(String text, {String title = ''}) => NotifyMessage(
        accountId: 'acc_wechat',
        title: title,
        text: text,
        arrival: DateTime(2026, 9, 7));

    test('标题品牌词不干扰收入正文判定（微信标题=微信支付）', () {
      final r = NotifyParser.parse(
          msg('收款到账¥50.00', title: '微信支付'));
      expect(r.outcome, NotifyParseOutcome.ok);
      expect(r.type, isNotNull);
    });

    test('正文为空时用标题兜底（标题含方向词与金额）', () {
      final r = NotifyParser.parse(msg('', title: '收款到账¥20.00'));
      expect(r.outcome, NotifyParseOutcome.ok);
      expect(r.type, RecordType.income);
      expect(r.amountCents, 2000);
    });

    test('正文只有金额、标题是品牌名 → 宁缺毋滥不判方向', () {
      final r = NotifyParser.parse(msg('¥3.7', title: '微信支付'));
      expect(r.outcome, NotifyParseOutcome.failed);
    });

    test('¥ 与数字间带空格可解析', () {
      final r = NotifyParser.parse(msg('已支付¥ 3.7'));
      expect(r.outcome, NotifyParseOutcome.ok);
      expect(r.amountCents, 370);
    });

    test('￥ 全角符号可解析', () {
      final r = NotifyParser.parse(msg('已支付￥25.5'));
      expect(r.outcome, NotifyParseOutcome.ok);
      expect(r.amountCents, 2550);
    });

    test('大额金额', () {
      final r = NotifyParser.parse(msg('已支付¥1234567.89'));
      expect(r.outcome, NotifyParseOutcome.ok);
      expect(r.amountCents, 123456789);
    });

    test('两位小数以内整数金额（数字元锚定）', () {
      final r = NotifyParser.parse(msg('已支付30元'));
      expect(r.outcome, NotifyParseOutcome.ok);
      expect(r.amountCents, 3000);
    });

    test('纯裸数字不被当金额（无方向词 → 失败而非误记）', () {
      final r = NotifyParser.parse(msg('你有3笔待处理'));
      expect(r.outcome, NotifyParseOutcome.failed);
    });

    test('空文本 → 失败', () {
      final r = NotifyParser.parse(msg(''));
      expect(r.outcome, NotifyParseOutcome.failed);
    });
  });
}
