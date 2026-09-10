import '../../models/record.dart';
import 'notify_models.dart';

/// 一条通知样本（单测断言 + 模拟面板快捷填充共用）。
///
/// 真实样本由用户手机提供（2026-09-07 起收集）；
/// 其余为按两平台常见通知格式拟的变体，真机后逐条用真实文案替换/校正。
class NotifySample {
  final String label; // 展示名：如 "微信·已支付(真实)"
  final String accountId;
  final String title;
  final String text;
  final NotifyParseOutcome expect;
  final RecordType? expectType;
  final int? expectCents; // 分
  final String? expectCounterpart;

  const NotifySample({
    required this.label,
    required this.accountId,
    required this.title,
    required this.text,
    required this.expect,
    this.expectType,
    this.expectCents,
    this.expectCounterpart,
  });
}

/// 模拟样本库
const List<NotifySample> notifySamples = [
  // ── 真实样本（2026-09-07 用户提供）──
  NotifySample(
    label: '微信·已支付 ¥3.7（真实）',
    accountId: 'acc_wechat',
    title: '微信支付',
    text: '已支付¥3.7',
    expect: NotifyParseOutcome.ok,
    expectType: RecordType.expense,
    expectCents: 370,
  ),
  NotifySample(
    label: '支付宝·支出（真实）',
    accountId: 'acc_alipay',
    title: '交易提醒',
    text: '你有一笔10.00元的支出，点此查看详情',
    expect: NotifyParseOutcome.ok,
    expectType: RecordType.expense,
    expectCents: 1000,
  ),

  // ── 常见变体（真机后校正）──
  NotifySample(
    label: '支付宝·支出带¥号',
    accountId: 'acc_alipay',
    title: '交易提醒',
    text: '你有一笔¥88.8元的支出',
    expect: NotifyParseOutcome.ok,
    expectType: RecordType.expense,
    expectCents: 8880,
  ),
  NotifySample(
    label: '微信·收款到账',
    accountId: 'acc_wechat',
    title: '微信支付',
    text: '收款到账¥50.00',
    expect: NotifyParseOutcome.ok,
    expectType: RecordType.income,
    expectCents: 5000,
  ),
  NotifySample(
    label: '支付宝·红包收入',
    accountId: 'acc_alipay',
    title: '交易提醒',
    text: '你收到一个红包¥6.66',
    expect: NotifyParseOutcome.ok,
    expectType: RecordType.income,
    expectCents: 666,
  ),
  NotifySample(
    label: '支付宝·退款退回',
    accountId: 'acc_alipay',
    title: '交易提醒',
    text: '你有一笔¥15.00元的退款已退回原支付方式',
    expect: NotifyParseOutcome.ok,
    expectType: RecordType.income,
    expectCents: 1500,
  ),
  NotifySample(
    label: '微信·向对方付款（带对方）',
    accountId: 'acc_wechat',
    title: '微信支付',
    text: '你向张三付款¥66.66',
    expect: NotifyParseOutcome.ok,
    expectType: RecordType.expense,
    expectCents: 6666,
    expectCounterpart: '张三',
  ),
  NotifySample(
    label: '微信·来自xx的转账（带对方）',
    accountId: 'acc_wechat',
    title: '微信支付',
    text: '来自李四的转账¥200，已存入零钱',
    expect: NotifyParseOutcome.ok,
    expectType: RecordType.income,
    expectCents: 20000,
    expectCounterpart: '李四',
  ),
  NotifySample(
    label: '微信·一位小数金额',
    accountId: 'acc_wechat',
    title: '微信支付',
    text: '已支付3.7元',
    expect: NotifyParseOutcome.ok,
    expectType: RecordType.expense,
    expectCents: 370,
  ),

  // ── 拒收样本（宁缺毋滥）──
  NotifySample(
    label: '支付宝·支付失败（应忽略）',
    accountId: 'acc_alipay',
    title: '交易提醒',
    text: '你的订单支付失败，已取消扣款',
    expect: NotifyParseOutcome.ignored,
  ),
  NotifySample(
    label: '无锚定金额（应失败）',
    accountId: 'acc_wechat',
    title: '微信支付',
    text: '你有1笔支出待查看详情',
    expect: NotifyParseOutcome.failed,
  ),
  NotifySample(
    label: '方向冲突：收款码支付（应失败）',
    accountId: 'acc_alipay',
    title: '交易提醒',
    text: '你扫了小店收款码支付¥12.00',
    expect: NotifyParseOutcome.failed,
  ),
  NotifySample(
    label: '合并多笔通知（应失败）',
    accountId: 'acc_wechat',
    title: '微信支付',
    text: '你收到2笔转账共¥120.00，点此查看',
    expect: NotifyParseOutcome.failed,
  ),
];

/// 生成样本消息（到达时刻由调用方给：测试固定值、面板用 now）
NotifyMessage sampleMessage(NotifySample s, {required DateTime arrival}) =>
    NotifyMessage(
      accountId: s.accountId,
      title: s.title,
      text: s.text,
      arrival: arrival,
    );
