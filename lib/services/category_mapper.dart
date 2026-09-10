import '../models/record.dart';

/// 按交易文本（对方/商品）关键词粗分到内置分类（v1 简单映射）
/// 未命中返回 null（调用方归入"其他"）。
String? mapCategoryId(RecordType type, String text) {
  final t = text;
  if (t.isEmpty) return null;

  if (type == RecordType.expense) {
    const rules = <String, List<String>>{
      'food': ['餐', '饭', '美团', '饿了么', '麦当劳', '肯德基', '奶茶', '咖啡', '小吃', '食堂', '外卖', '面', '烘焙'],
      'transport': ['滴滴', '出行', '地铁', '公交', '高铁', '铁路', '机票', '加油', '打车', '骑行', '停车'],
      'shopping': ['淘宝', '天猫', '京东', '拼多多', '超市', '商场', '便利店', '商城', '优衣库', '沃尔玛'],
      'fun': ['电影', '游戏', '视频', '音乐', 'KTV', '娱乐', '剧本'],
      'housing': ['房租', '水电', '物业', '燃气', '宽带', '维修', '家居'],
      'medical': ['医院', '药', '诊所', '挂号', '体检'],
      'transfer_out': ['转账', '红包', '零钱通', '提现', '充值', '信用卡还款', '理财'],
    };
    for (final e in rules.entries) {
      if (e.value.any(t.contains)) return e.key;
    }
  } else {
    const rules = <String, List<String>>{
      'salary': ['工资', '薪', '奖金', '报销', '补助', '补贴'],
      'refund': ['退款', '退货', '赔付'],
      'redpacket': ['红包', '转账', '转入'],
    };
    for (final e in rules.entries) {
      if (e.value.any(t.contains)) return e.key;
    }
  }
  return null;
}

/// 未命中时的兜底分类 id
String fallbackCategoryId(RecordType type) =>
    type == RecordType.expense ? 'expense_other' : 'income_other';
