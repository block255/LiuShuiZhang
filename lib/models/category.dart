import 'package:flutter/material.dart';

import 'record.dart';

/// 内置分类（v1：固定列表，S3 用）
/// 每个分类归属于支出表或收入表（type 决定归属），id 全局唯一。
class Category {
  final String id;
  final String name;
  final RecordType type; // 该分类归属：支出表 / 收入表
  final IconData icon;

  /// 图片类图标（asset 名，如 'deepseek' → assets/icons/deepseek.png）；
  /// 非空时渲染层优先用它（彩蛋图标），否则用 [icon]
  final String? assetIcon;

  const Category({
    required this.id,
    required this.name,
    required this.type,
    required this.icon,
    this.assetIcon,
  });
}

/// 支出分类
const List<Category> expenseCategories = [
  Category(id: 'food', name: '餐饮', type: RecordType.expense, icon: Icons.restaurant),
  Category(id: 'transport', name: '交通', type: RecordType.expense, icon: Icons.directions_bus),
  Category(id: 'shopping', name: '购物', type: RecordType.expense, icon: Icons.shopping_bag),
  Category(id: 'fun', name: '娱乐', type: RecordType.expense, icon: Icons.movie),
  Category(id: 'housing', name: '居住', type: RecordType.expense, icon: Icons.home),
  Category(id: 'medical', name: '医疗', type: RecordType.expense, icon: Icons.medical_services),
  Category(id: 'transfer_out', name: '转账', type: RecordType.expense, icon: Icons.swap_horiz),
  Category(id: 'expense_other', name: '其他', type: RecordType.expense, icon: Icons.more_horiz),
];

/// 收入分类
const List<Category> incomeCategories = [
  Category(id: 'salary', name: '工资', type: RecordType.income, icon: Icons.payments),
  Category(id: 'redpacket', name: '红包', type: RecordType.income, icon: Icons.redeem),
  Category(id: 'refund', name: '退款', type: RecordType.income, icon: Icons.assignment_return),
  Category(id: 'transfer_in', name: '转账', type: RecordType.income, icon: Icons.swap_horiz),
  Category(id: 'income_other', name: '其他', type: RecordType.income, icon: Icons.more_horiz),
];

/// 全部分类（按 type 检索用）
const List<Category> allCategories = [
  ...expenseCategories,
  ...incomeCategories,
];

/// 按 id 找分类，找不到返回 null（如导入映射失败时）
Category? categoryById(String id) {
  for (final c in allCategories) {
    if (c.id == id) return c;
  }
  return null;
}

/// 某收支类型下的分类列表
List<Category> categoriesOf(RecordType type) =>
    allCategories.where((c) => c.type == type).toList();
