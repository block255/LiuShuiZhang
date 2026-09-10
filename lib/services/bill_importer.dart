import '../data/record_store.dart';
import '../models/record.dart';
import 'category_mapper.dart';
import 'csv_bill_parser.dart';

/// 导入结果统计
class ImportSummary {
  final int imported; // 实际入库条数
  final int duplicated; // 因单号/指纹重复跳过条数（含桥接）
  final int skipped; // 解析阶段跳过条数（退款/失败/无法识别）
  final int bridged; // 指纹桥接条数：与库内"无单号记录"（通知/手动）配对并回填 orderId

  const ImportSummary({
    required this.imported,
    required this.duplicated,
    required this.skipped,
    this.bridged = 0,
  });

  bool get nothingImported => imported == 0;
}

/// 把解析出的账单条目应用到仓库（去重后入库）
///
/// 去重规则：
/// 1. 官方单号 orderId 已存在于库中 → duplicate
/// 2. 【指纹桥】无单号命中时：库内"无单号记录"（通知/手动记的）按
///    同账户+同方向+同金额+时间差 ≤ [bridgeWindowMinutes] 配对 →
///    命中则跳过导入，并把账单的 orderId 回填到该记录
///    —— 指纹只做"首次对账的桥"，回填后该记录永久带官方 id，后续导入直接单号去重
class BillImporter {
  BillImporter._();

  /// 指纹桥时间窗（分钟）：通知到达/记账时刻 vs 账单交易时刻的允许偏差
  /// 待真实校准实验（通知到达≈交易时刻，支付宝推送代理可能延迟）
  static const int bridgeWindowMinutes = 5;

  static ImportSummary apply({
    required String accountId,
    required List<ParsedBill> bills,
    RecordStore? store,
  }) {
    final s = store ?? RecordStore.instance;
    final existing = s.all;
    final orderIds = <String>{
      for (final r in existing)
        if (r.orderId != null && r.orderId!.isNotEmpty) r.orderId!,
    };

    var imported = 0;
    var duplicated = 0;
    var bridged = 0;
    // 本次已桥接的记录 id（多候选时排除，逐条配对不重复）
    final bridgedIds = <String>{};

    for (final b in bills) {
      // 1. 官方单号查重
      if (b.orderId != null && orderIds.contains(b.orderId)) {
        duplicated++;
        continue;
      }

      // 2. 指纹桥：配对库内"无单号"记录（通知/手动），回填 orderId 后跳过
      final candidates = existing
          .where((r) =>
              r.orderId == null &&
              !bridgedIds.contains(r.id) &&
              r.type == b.type &&
              r.amountCents == b.amountCents &&
              r.accountId == accountId &&
              r.time.difference(b.time).inMinutes.abs() <= bridgeWindowMinutes)
          .toList();
      if (candidates.isNotEmpty) {
        // 时间最接近的优先（同额多笔逐条桥接也能正确配对）
        candidates.sort((a, c) => a.time
            .difference(b.time)
            .inMinutes
            .abs()
            .compareTo(c.time.difference(b.time).inMinutes.abs()));
        final target = candidates.first;
        s.update(target.copyWith(orderId: b.orderId));
        bridgedIds.add(target.id);
        if (b.orderId != null) orderIds.add(b.orderId!);
        duplicated++;
        bridged++;
        continue;
      }

      // 3. 全新条目：入库
      s.add(Record(
        id: Record.newId(),
        accountId: accountId,
        source: RecordSource.import,
        type: b.type,
        amountCents: b.amountCents,
        time: b.time,
        counterpart: b.counterpart.isEmpty ? null : b.counterpart,
        categoryId: mapCategoryId(b.type, b.counterpart) ??
            fallbackCategoryId(b.type),
        orderId: b.orderId,
        status: RecordStatus.confirmed,
      ));
      if (b.orderId != null) orderIds.add(b.orderId!);
      imported++;
    }

    return ImportSummary(
      imported: imported,
      duplicated: duplicated,
      skipped: 0,
      bridged: bridged,
    );
  }
}
