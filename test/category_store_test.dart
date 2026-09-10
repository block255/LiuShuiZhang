import 'package:bill_record_app/data/category_store.dart';
import 'package:bill_record_app/models/record.dart';
import 'package:bill_record_app/services/storage/record_storage_stub.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late CategoryStore store;

  setUp(() async {
    store = CategoryStore.replaceForTest(MemoryRecordStorage());
    await store.init();
  });

  group('分类管理 基础', () {
    test('默认：仅内置分类，全部启用', () {
      expect(store.categoriesOf(RecordType.expense), hasLength(8));
      expect(store.categoriesOf(RecordType.income), hasLength(5));
      expect(store.categoryById('food')?.name, '餐饮');
      expect(store.categoryById('not-exist'), isNull);
    });

    test('新增自定义分类 → 出现在记账选择列表（其他固定最末）', () async {
      await store.addCustom(
          name: '学习', type: RecordType.expense, iconKey: 'book');
      final list = store.categoriesOf(RecordType.expense);
      expect(list, hasLength(9));
      expect(list.last.name, '其他'); // 其他恒在末
      expect(list[list.length - 2].name, '学习'); // 新分类在其它之前
      expect(list[list.length - 2].id, startsWith('custom_'));
      // 收入列表不受影响
      expect(store.categoriesOf(RecordType.income), hasLength(5));
      // 按 id 可查
      expect(store.categoryById(list[list.length - 2].id)?.name, '学习');
    });

    test('删除自定义分类 → 列表恢复，categoryById 返回 null', () async {
      await store.addCustom(
          name: '学习', type: RecordType.expense, iconKey: 'book');
      final custom = store
          .categoriesOf(RecordType.expense)
          .firstWhere((c) => c.id.startsWith('custom_'));
      await store.removeCustom(custom.id);
      expect(store.categoriesOf(RecordType.expense), hasLength(8));
      expect(store.categoryById(custom.id), isNull);
    });

    test('停用内置 → 记账列表隐藏，categoryById 仍可查（历史兼容）', () async {
      await store.setBuiltinDisabled('medical', true);
      final names = store
          .categoriesOf(RecordType.expense)
          .map((c) => c.id)
          .toList();
      expect(names.contains('medical'), isFalse);
      expect(names, hasLength(7));
      // 历史记录仍能解析
      expect(store.categoryById('medical')?.name, '医疗');
      // 重新启用恢复
      await store.setBuiltinDisabled('medical', false);
      expect(
          store
              .categoriesOf(RecordType.expense)
              .any((c) => c.id == 'medical'),
          isTrue);
    });

    test('配置持久化 roundtrip（自定义 + 停用，模拟重启）', () async {
      final storage = MemoryRecordStorage();
      final s1 = CategoryStore.replaceForTest(storage);
      await s1.init();
      await s1.addCustom(name: '宠物', type: RecordType.expense, iconKey: 'pet');
      await s1.setBuiltinDisabled('housing', true);

      // 重启：同一 storage 新建实例恢复
      final s2 = CategoryStore.replaceForTest(storage);
      await s2.init();
      final pet = s2
          .categoriesOf(RecordType.expense)
          .firstWhere((c) => c.id.startsWith('custom_'));
      expect(pet.name, '宠物');
      expect(s2.isBuiltinDisabled('housing'), isTrue);
      expect(s2.categoryById(pet.id)?.name, '宠物');
    });
  });

  group('图标库', () {
    test('iconByKey 映射存在', () {
      expect(categoryIconChoices['book'], isNotNull);
      expect(categoryIconChoices['other'], isNotNull);
    });
  });
}
