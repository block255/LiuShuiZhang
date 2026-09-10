/// 账户类型
enum AccountType { wechat, alipay, manual }

extension AccountTypeInfo on AccountType {
  String get label => switch (this) {
        AccountType.wechat => '微信支付',
        AccountType.alipay => '支付宝',
        AccountType.manual => '手动账户',
      };
}

/// 账户：一条"绑定"的支付渠道或手动账户
class Account {
  final String id;
  final AccountType type;
  final String name;
  final String? note;

  const Account({
    required this.id,
    required this.type,
    required this.name,
    this.note,
  });

  /// 系统预置账户：微信支付、支付宝
  static const wechat = Account(
    id: 'acc_wechat',
    type: AccountType.wechat,
    name: '微信支付',
  );

  static const alipay = Account(
    id: 'acc_alipay',
    type: AccountType.alipay,
    name: '支付宝',
  );

  /// 预置账户列表（绑定管理 UI 用，S5 实现）
  static const builtin = [wechat, alipay];
}
