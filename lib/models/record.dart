/// 收支类型
enum RecordType { income, expense }

/// 记录来源：手动 / 官方账单导入 / 通知自动记账
enum RecordSource { manual, import, notify }

/// 记录状态：
/// - pending:   待确认（通知解析进来，等用户确认）
/// - confirmed: 已入账（正式账单，列表展示）
/// - merged:    已合并（与导入记录去重合并，冗余，不展示）
/// - discarded: 已忽略
enum RecordStatus { pending, confirmed, merged, discarded }

/// 单条账单记录（核心数据模型，见设计稿 v0.2）
/// 金额一律用"分"存整数，避免浮点误差。
class Record {
  final String id;
  final String accountId; // 账户来源（wechat/alipay/manual）
  final RecordSource source;
  final RecordType type;
  final int amountCents; // 正数，收支方向由 type 决定
  final DateTime time;
  final String? counterpart; // 对方/商户
  final String? categoryId; // 分类（内置体系）
  final String? note; // 备注
  final String? orderId; // 官方交易单号（导入有，用于去重）
  final RecordStatus status;

  const Record({
    required this.id,
    required this.accountId,
    required this.source,
    required this.type,
    required this.amountCents,
    required this.time,
    this.counterpart,
    this.categoryId,
    this.note,
    this.orderId,
    this.status = RecordStatus.confirmed,
  });

  /// 生成简易唯一 id（时间戳 + 随机后缀）
  static String newId() =>
      'rec_${DateTime.now().microsecondsSinceEpoch}_${DateTime.now().millisecond}';

  Record copyWith({
    String? accountId,
    RecordSource? source,
    RecordType? type,
    int? amountCents,
    DateTime? time,
    String? counterpart,
    String? categoryId,
    String? note,
    String? orderId,
    RecordStatus? status,
  }) {
    return Record(
      id: id,
      accountId: accountId ?? this.accountId,
      source: source ?? this.source,
      type: type ?? this.type,
      amountCents: amountCents ?? this.amountCents,
      time: time ?? this.time,
      counterpart: counterpart ?? this.counterpart,
      categoryId: categoryId ?? this.categoryId,
      note: note ?? this.note,
      orderId: orderId ?? this.orderId,
      status: status ?? this.status,
    );
  }

  // ── 序列化（持久化用）──

  Map<String, dynamic> toJson() => {
        'id': id,
        'accountId': accountId,
        'source': source.name,
        'type': type.name,
        'amountCents': amountCents,
        'time': time.toIso8601String(),
        'counterpart': counterpart,
        'categoryId': categoryId,
        'note': note,
        'orderId': orderId,
        'status': status.name,
      };

  /// 反序列化；对损坏/缺失字段做兜底，不让单条脏数据拖垮整库
  factory Record.fromJson(Map<String, dynamic> j) {
    RecordType typeOf(String? v) =>
        RecordType.values.asNameMap()[v] ?? RecordType.expense;
    RecordSource sourceOf(String? v) =>
        RecordSource.values.asNameMap()[v] ?? RecordSource.manual;
    RecordStatus statusOf(String? v) =>
        RecordStatus.values.asNameMap()[v] ?? RecordStatus.confirmed;
    final rawTime = j['time'] as String?;
    final time = rawTime == null ? null : DateTime.tryParse(rawTime);
    return Record(
      id: (j['id'] as String?) ?? newId(),
      accountId: (j['accountId'] as String?) ?? 'acc_wechat',
      source: sourceOf(j['source'] as String?),
      type: typeOf(j['type'] as String?),
      amountCents: (j['amountCents'] as num?)?.toInt() ?? 0,
      time: time ?? DateTime.now(),
      counterpart: j['counterpart'] as String?,
      categoryId: j['categoryId'] as String?,
      note: j['note'] as String?,
      orderId: j['orderId'] as String?,
      status: statusOf(j['status'] as String?),
    );
  }
}
