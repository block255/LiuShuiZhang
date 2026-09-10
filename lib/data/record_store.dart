import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../models/account.dart';
import '../models/record.dart';
import '../services/storage/record_storage.dart';
import '../utils/app_log.dart';

/// 查询条件
/// - [accountId] null = 全部账户
/// - [type]      null = 收支都查
/// - [status]    null = 仅已入账(confirmed)
/// - [start]/[end]：时间范围，start <= t < end（end 不含），null 不限制
class RecordQuery {
  final String? accountId;
  final RecordType? type;
  final DateTime? start;
  final DateTime? end;
  final List<RecordStatus> statusList;

  const RecordQuery({
    this.accountId,
    this.type,
    this.start,
    this.end,
    this.statusList = const [RecordStatus.confirmed],
  });

  bool matches(Record r) {
    if (accountId != null && r.accountId != accountId) return false;
    if (type != null && r.type != type) return false;
    if (!statusList.contains(r.status)) return false;
    if (start != null && r.time.isBefore(start!)) return false;
    if (end != null && !r.time.isBefore(end!)) return false;
    return true;
  }
}

/// 查询结果：记录列表 + 收入/支出合计（分）
class QueryResult {
  final List<Record> records;
  final int incomeCents;
  final int expenseCents;

  const QueryResult({
    required this.records,
    required this.incomeCents,
    required this.expenseCents,
  });
}

/// 全局仓库：内存 + 持久化 + 自动清理
///
/// - 任何增删改后自动全量保存到 [RecordStorage]
/// - 定期清理：保留最近 [retentionYears] 年（默认 3），
///   两次清理最小间隔 [cleanMinIntervalDays] 天（启动时检查）
/// - 容量保护：写入体积超过 [softLimitBytes] 时先"紧急裁剪"最老记录直到可存；
///   仍写不进则置 [storageFull]（UI 提示），绝不静默丢新数据
class RecordStore extends ChangeNotifier {
  RecordStore._(
    this._storage, {
    this.retentionYears = 3,
    this.cleanMinIntervalDays = 30,
  });

  static RecordStore instance = RecordStore._(createRecordStorage());

  /// 测试用：换掉全局实例（配独立内存存储）
  @visibleForTesting
  static RecordStore replaceForTest(RecordStorage storage,
      {int retentionYears = 3, int cleanMinIntervalDays = 30}) {
    instance = RecordStore._(storage,
        retentionYears: retentionYears,
        cleanMinIntervalDays: cleanMinIntervalDays);
    return instance;
  }

  final RecordStorage _storage;
  final List<Record> _records = [];

  /// 保留年限（默认 3 年）
  final int retentionYears;

  /// 定期清理最小间隔（天）
  final int cleanMinIntervalDays;

  /// 容量软限：超过则触发紧急裁剪（默认 4MB，给浏览器配额留余量）
  @visibleForTesting
  int softLimitBytes = 4 * 1024 * 1024;

  bool _initialized = false;

  /// 最近一次自动清理删除的条数（UI 一次性消费）
  int _autoCleanCount = 0;
  int get autoCleanCount => _autoCleanCount;

  /// 持久化被容量卡死（UI 提示"存储已满"）
  bool _storageFull = false;
  bool get storageFull => _storageFull;

  // ── 待确认(pending)治理：防无限堆积 ──

  /// 常规线：pending 超过此数 且 该条已满 [pendingAutoMinAge] → 最老的自动入账
  @visibleForTesting
  int pendingSoftLimit = 20;

  /// 容量兜底：pending 超过此数 → 无条件把最老的自动入账（长期不打开也不爆表）
  @visibleForTesting
  int pendingHardLimit = 100;

  /// 自动入账的最短待确认时长（给用户确认窗口）
  static const Duration pendingAutoMinAge = Duration(hours: 48);

  /// 最近一次 tidyPending 自动入账条数（UI 一次性消费）
  int _pendingAutoConfirmed = 0;
  int get pendingAutoConfirmed => _pendingAutoConfirmed;

  /// 当前全部记录（按时间倒序）
  List<Record> get all => List.unmodifiable(_records);

  /// 初始化：从存储恢复 + 定期清理检查（幂等）
  Future<void> init() async {
    if (_initialized) return;
    _initialized = true;

    final loaded = await _storage.load();
    _records
      ..clear()
      ..addAll(loaded);
    _sort();

    await _maybePeriodicClean();
    notifyListeners();
  }

  /// 定期清理：距上次清理 ≥ 间隔 且 存在超龄记录 → 删除并落盘
  Future<void> _maybePeriodicClean() async {
    final now = DateTime.now();
    final lastClean = await _storage.loadLastClean();
    if (lastClean != null &&
        now.difference(lastClean).inDays < cleanMinIntervalDays) {
      return; // 间隔未到，跳过
    }

    final cutoff = DateTime(now.year - retentionYears, now.month, now.day);
    final expired = _records.where((r) => r.time.isBefore(cutoff)).toList();
    if (expired.isNotEmpty) {
      _records.removeWhere((r) => expired.contains(r));
      _autoCleanCount += expired.length;
      _sort();
      await _persist();
    }
    await _storage.saveLastClean(now);
  }

  /// 新增记录（默认已入账）
  void add(Record record) {
    _records.add(record);
    _sort();
    notifyListeners();
    _persist();
  }

  /// 备份恢复：全量覆盖——清空现有记录后载入备份列表
  Future<void> restoreAll(List<Record> records) async {
    _records
      ..clear()
      ..addAll(records);
    _sort();
    notifyListeners();
    await _persist();
  }

  /// 备份恢复：合并去重——按 id 并入；同 id 用备份版覆盖（备份为导出时点状态），
  /// 库中独有保留，备份独有新增。返回 (added, updated)。
  Future<({int added, int updated})> mergeBackup(List<Record> backup) async {
    final map = {for (final r in _records) r.id: r};
    var added = 0;
    var updated = 0;
    for (final b in backup) {
      if (map.containsKey(b.id)) {
        updated++;
      } else {
        added++;
      }
      map[b.id] = b;
    }
    _records
      ..clear()
      ..addAll(map.values);
    _sort();
    notifyListeners();
    await _persist();
    return (added: added, updated: updated);
  }

  /// 删除记录
  void remove(String id) {
    _records.removeWhere((r) => r.id == id);
    notifyListeners();
    _persist();
  }

  /// 更新记录（按 id 整体替换）
  void update(Record record) {
    final i = _records.indexWhere((r) => r.id == record.id);
    if (i < 0) return;
    _records[i] = record;
    _sort();
    notifyListeners();
    _persist();
  }

  /// 按条件查询（时间倒序）
  QueryResult query(RecordQuery q) {
    final matched = _records.where(q.matches).toList();
    matched.sort((a, b) => b.time.compareTo(a.time));
    var income = 0;
    var expense = 0;
    for (final r in matched) {
      if (r.type == RecordType.income) {
        income += r.amountCents;
      } else {
        expense += r.amountCents;
      }
    }
    return QueryResult(
        records: matched, incomeCents: income, expenseCents: expense);
  }

  /// 待确认记录（通知进来未处理）
  QueryResult pending() =>
      query(const RecordQuery(statusList: [RecordStatus.pending]));

  /// 待确认治理：防无限堆积（启动/回前台时调用）
  ///
  /// 1. 常规线：pending > [pendingSoftLimit] 时，把"最老的、已满
  ///    [pendingAutoMinAge]"的差额条数自动入账（转 confirmed，分类保持未分类）；
  /// 2. 容量兜底：处理完常规线后仍超 [pendingHardLimit] → 无条件入账最老到硬顶。
  ///
  /// 返回本次自动入账条数；UI 经 [consumePendingAutoNotice] 一次性提示。
  Future<int> tidyPending() async {
    final pendings = _records
        .where((r) => r.status == RecordStatus.pending)
        .toList()
      ..sort((a, b) => a.time.compareTo(b.time)); // 最老在前
    final n = pendings.length;
    if (n == 0) return 0;

    final now = DateTime.now();
    final toConfirm = <String>{};

    // 1. 常规线（数量超限才处理，且只清"老"的）
    if (n > pendingSoftLimit) {
      var need = n - pendingSoftLimit;
      for (final p in pendings) {
        if (need <= 0) break;
        if (now.difference(p.time) >= pendingAutoMinAge) {
          toConfirm.add(p.id);
          need--;
        }
      }
    }

    // 2. 容量兜底（无条件清到硬顶内）
    var remaining = n - toConfirm.length;
    if (remaining > pendingHardLimit) {
      var forced = remaining - pendingHardLimit;
      for (final p in pendings) {
        if (forced <= 0) break;
        if (toConfirm.add(p.id)) forced--;
      }
    }

    if (toConfirm.isEmpty) return 0;
    for (final id in toConfirm) {
      final i = _records.indexWhere((r) => r.id == id);
      if (i >= 0) {
        // 自动入账：状态转 confirmed，分类保持未分类（用户可稍后编辑补分类）
        _records[i] =
            _records[i].copyWith(status: RecordStatus.confirmed);
      }
    }
    _pendingAutoConfirmed += toConfirm.length;
    _sort();
    notifyListeners();
    await _persist();
    return toConfirm.length;
  }

  /// UI 一次性消费"待确认自动入账"提示（返回本次条数并清零）
  int consumePendingAutoNotice() {
    final n = _pendingAutoConfirmed;
    _pendingAutoConfirmed = 0;
    return n;
  }

  /// UI 一次性消费"自动清理"提示（返回本次条数并清零）
  int consumeAutoCleanNotice() {
    final n = _autoCleanCount;
    _autoCleanCount = 0;
    return n;
  }

  /// 仅测试用：清空数据与存储
  @visibleForTesting
  void clearForTest() {
    _records.clear();
    _storage.clear();
  }

  // ── 持久化 ──

  Future<void> _persist() async {
    var list = _records;
    if (utf8.encode(_encode(list)).length > softLimitBytes) {
      // 容量超限：紧急裁剪最老记录（同步改内存）直到可存
      _emergencyTrim();
      list = _records;
    }
    try {
      await _storage.save(list);
      _storageFull = false;
    } catch (e) {
      _storageFull = true;
      debugLog('[RecordStore] 持久化失败: $e');
    }
  }

  /// 紧急裁剪：从最老开始删，直到预估体积 ≤ 软限（或删空）
  void _emergencyTrim() {
    final sortedOldFirst = List<Record>.of(_records)
      ..sort((a, b) => a.time.compareTo(b.time));
    for (final r in sortedOldFirst) {
      if (utf8.encode(_encode(_records)).length <= softLimitBytes) break;
      _records.removeWhere((x) => x.id == r.id);
      _autoCleanCount++;
    }
    _sort();
    notifyListeners();
  }

  String _encode(List<Record> list) =>
      jsonEncode(list.map((r) => r.toJson()).toList());

  /// 预置账户校验：不存在的 accountId 不允许入库（防御）
  bool validAccount(String accountId) =>
      Account.builtin.any((a) => a.id == accountId);

  void _sort() {
    _records.sort((a, b) => b.time.compareTo(a.time));
  }
}
