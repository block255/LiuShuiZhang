import 'package:flutter/material.dart';

import '../app_theme.dart';
import '../models/account.dart';

/// 账户圆形徽标（微信绿 / 支付宝蓝 / 手动主蓝），
/// 与「我的」页账户卡视觉一致，供待确认页等复用。
class AccountBadge extends StatelessWidget {
  final String accountId;
  final double size;
  final double iconSize;

  const AccountBadge({
    super.key,
    required this.accountId,
    this.size = 40,
    this.iconSize = 22,
  });

  Account? get _account {
    for (final a in Account.builtin) {
      if (a.id == accountId) return a;
    }
    return null;
  }

  Color get _brandColor => switch (_account?.type) {
        AccountType.wechat => const Color(0xFF07C160),
        AccountType.alipay => const Color(0xFF1677FF),
        _ => AppColors.primary,
      };

  IconData get _icon => switch (_account?.type) {
        AccountType.wechat => Icons.wechat,
        AccountType.alipay => Icons.account_balance_wallet,
        _ => Icons.account_balance,
      };

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: _brandColor.withValues(alpha: 0.12),
        shape: BoxShape.circle,
      ),
      child: Icon(_icon, size: iconSize, color: _brandColor),
    );
  }
}
