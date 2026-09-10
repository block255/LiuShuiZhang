import '../../models/record.dart';
import 'notify_models.dart';

/// 通知文本解析器：无效词拦截 → 方向判定 → 金额提取 → 对方提取。
///
/// 设计决策（见 笔记/设计草稿/通知监听-架构设计.md）：
/// - 规则集中在文件头部词表，真机样本到达后只改这里 + 补单测；
/// - 方向冲突即失败（宁缺毋滥，绝不猜测）；
/// - 金额必须带 ¥/￥ 或 "元" 锚定，防把"第3笔"当金额；
/// - 对方尽力而为，提取不到返回 null（待确认页人工补充）。
class NotifyParser {
  // ── 无效词（必须先于方向判定拦截："支付失败"含"支付"但不能记支出）──
  static const List<String> ignoreKeywords = [
    '失败', '取消', '关闭', '超时', '未支付',
  ];

  // ── 方向词表（多数决；平局或全无 → 失败，见 _judgeType）──
  static const List<String> expenseKeywords = [
    '已支付', '支付', '付款', '支出', '转出', '扣款', '消费',
  ];
  static const List<String> incomeKeywords = [
    '到账', '收款', '收到', '存入', '入账', '转入', '退款', '退回', '退还',
  ];

  // ── 金额锚定 ──
  /// "¥3.7" / "￥10.00" 等
  static final RegExp _symbolAmountRe = RegExp(r'[¥￥]\s*(\d+(?:\.\d{1,2})?)');
  /// "10.00元" / "3.7元" 等
  static final RegExp _yuanAmountRe = RegExp(r'(\d+(?:\.\d{1,2})?)\s*元');

  // ── 对方（尽力而为；不匹配返回 null）──
  /// "向张三支付/付款/转账"、"给李四转账"
  static final RegExp _payToRe = RegExp(
      r'(?:向|给)([\u4e00-\u9fa5A-Za-z0-9]{1,12})(?:支付|付款|转账)');
  /// "来自王五的转账/收款/支付"
  static final RegExp _fromRe = RegExp(
      r'来自([\u4e00-\u9fa5A-Za-z0-9]{1,12})(?:的转账|的收款|的支付)');

  NotifyParser._();

  static NotifyParseResult parse(NotifyMessage msg) {
    // 判定只取正文：标题通常是固定渠道名（"微信支付"/"交易提醒"），
    // 混入会把收入通知误判成方向冲突；正文为空时才用标题兜底。
    final s = msg.text.trim().isNotEmpty ? msg.text : msg.title;

    // 1. 无效词拦截
    for (final k in ignoreKeywords) {
      if (s.contains(k)) {
        return NotifyParseResult.ignored('无效通知（含"$k"），不记账');
      }
    }

    // 1.5 合并通知拦截："你收到2笔转账共¥120" 会误判成单条总额，
    //     多笔拆分规则待真机样本，先拒收（宁缺毋滥）。
    if ((s.contains('共') || s.contains('合计')) && s.contains('笔')) {
      return NotifyParseResult.failed('疑似多条合并通知（含"共/合计"与"笔"），暂不自动拆分');
    }

    // 2. 方向判定：多数决；平局（含全无）→ 失败。
    //    例如"退款已退回原支付方式"：退款/退回 2 个收入词 > "支付"1 个附带词 → 收入
    int hits(List<String> words) => words.where(s.contains).length;
    final exHits = hits(expenseKeywords);
    final inHits = hits(incomeKeywords);
    final RecordType? type;
    if (exHits > inHits) {
      type = RecordType.expense;
    } else if (inHits > exHits) {
      type = RecordType.income;
    } else if (exHits == 0 && inHits == 0) {
      return NotifyParseResult.failed('无法识别收支方向，需人工补规则');
    } else {
      return NotifyParseResult.failed(
          '方向冲突（支出词与收入词同票，各 $exHits 个），需人工补规则');
    }

    // 3. 金额提取（¥ 锚定优先，其次"元"锚定；都无 → 失败）
    final match = _symbolAmountRe.firstMatch(s) ?? _yuanAmountRe.firstMatch(s);
    if (match == null) {
      return NotifyParseResult.failed('未找到带 ¥/￥ 或"元"锚定的金额');
    }
    final cents = _parseCents(match.group(1)!);
    if (cents == null || cents <= 0) {
      return NotifyParseResult.failed('金额无法换算（原文片段：${match.group(0)}）');
    }

    // 4. 对方（尽力而为）
    final counterpart = _payToRe.firstMatch(s)?.group(1) ??
        _fromRe.firstMatch(s)?.group(1);

    return NotifyParseResult.ok(
        type: type, amountCents: cents, counterpart: counterpart);
  }

  /// "3.7" → 370；"10.00" → 1000。解析失败返回 null。
  static int? _parseCents(String numStr) {
    final dot = numStr.indexOf('.');
    if (dot < 0) {
      final yuan = int.tryParse(numStr);
      return yuan == null ? null : yuan * 100;
    }
    final yuanPart = int.tryParse(numStr.substring(0, dot));
    if (yuanPart == null) return null;
    var fenStr = numStr.substring(dot + 1);
    if (fenStr.length > 2) return null; // 正则已限，防御
    while (fenStr.length < 2) {
      fenStr = '${fenStr}0';
    }
    final fen = int.tryParse(fenStr);
    if (fen == null) return null;
    return yuanPart * 100 + fen;
  }
}
