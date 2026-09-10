import 'package:flutter/material.dart';

import '../models/category.dart';

/// 分类图标统一渲染：图片类图标（assetIcon，如 DeepSeek 鲸鱼彩蛋）
/// 走 Image.asset，其余走 Material 图标（IconData + color）。
class CategoryIcon extends StatelessWidget {
  final Category? category;
  final IconData? fallbackIcon;
  final double size;
  final Color? color;

  const CategoryIcon({
    super.key,
    required this.category,
    this.fallbackIcon,
    this.size = 20,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    final asset = category?.assetIcon;
    if (asset != null) {
      return Image.asset(
        'assets/icons/$asset.png',
        width: size,
        height: size,
        fit: BoxFit.contain,
      );
    }
    return Icon(
      category?.icon ?? fallbackIcon ?? Icons.receipt_long,
      size: size,
      color: color,
    );
  }
}
