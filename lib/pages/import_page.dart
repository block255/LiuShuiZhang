import 'package:flutter/material.dart';

import '../app_theme.dart';
import '../data/record_store.dart';
import '../models/account.dart';
import '../models/record.dart';
import '../services/bill_file_reader.dart';
import '../services/bill_importer.dart';
import '../services/csv_bill_parser.dart';
import '../services/file_pick.dart';
import '../utils/money.dart';
import '../utils/record_time.dart';

/// 导入账单页：选择文件（CSV/XLSX）→ 解析预览 → 确认入库
/// [initialCsv] 仅测试注入用（生产为 null，走文件选择）
class ImportPage extends StatefulWidget {
  final String accountId;
  final String? initialCsv; // 测试注入

  const ImportPage({super.key, required this.accountId, this.initialCsv});

  @override
  State<ImportPage> createState() => _ImportPageState();
}

class _ImportPageState extends State<ImportPage> {
  Account? get _account {
    for (final a in Account.builtin) {
      if (a.id == widget.accountId) return a;
    }
    return null;
  }

  String? _fileName;
  ParseResult? _result;
  int _dupCount = 0;
  bool _working = false;

  @override
  void initState() {
    super.initState();
    if (widget.initialCsv != null) {
      _onRowsLoaded('测试样本.csv', CsvBillParser.parse(widget.initialCsv!));
    }
  }

  Future<void> _pickFile() async {
    setState(() => _working = true);
    try {
      final picked = await pickBillFile();
      if (picked != null) {
        final rows = await BillFileReader.readRows(picked.name, picked.bytes);
        final parsed = CsvBillParser.parseRows(rows);
        _onRowsLoaded(picked.name, parsed);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('选择/解析文件失败：$e')),
        );
      }
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  void _onRowsLoaded(String name, ParseResult parsed) {
    // 预查重复（单号口径，与 BillImporter 简化一致）
    if (parsed.bills.isNotEmpty) {
      final existingOrderIds = <String>{
        for (final r in RecordStore.instance.all)
          if (r.orderId != null && r.orderId!.isNotEmpty) r.orderId!,
      };
      _dupCount =
          parsed.bills.where((b) => b.orderId != null && existingOrderIds.contains(b.orderId)).length;
    }
    setState(() {
      _fileName = name;
      _result = parsed;
    });
  }

  Future<void> _confirmImport() async {
    final result = _result;
    if (result == null || result.bills.isEmpty) return;
    setState(() => _working = true);
    // 让 UI 先刷新
    await Future<void>.delayed(const Duration(milliseconds: 50));
    final summary = BillImporter.apply(accountId: widget.accountId, bills: result.bills);
    if (!mounted) return;
    // 先取 messenger 再 pop（pop 后本页 context 失效）
    final messenger = ScaffoldMessenger.of(context);
    Navigator.of(context).pop(true);
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          '导入完成：新增 ${summary.imported} 条'
          '${summary.bridged > 0 ? '，与已记交易合并 ${summary.bridged} 条（已补交易单号）' : ''}'
          '${summary.duplicated > summary.bridged ? '，跳过重复 ${summary.duplicated - summary.bridged} 条' : ''}'
          '${summary.skipped > 0 ? '，无法识别 ${summary.skipped} 行' : ''}',
        ),
        duration: const Duration(seconds: 3),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final result = _result;
    return Scaffold(
      appBar: AppBar(title: Text('导入账单${_account == null ? '' : ' · ${_account!.name}'}')),
      body: result == null ? _buildIdle() : _buildPreview(),
    );
  }

  // ── 待选择状态 ──
  Widget _buildIdle() {
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        const SizedBox(height: 24),
        Icon(Icons.file_download_outlined,
            size: 72,
            color: AppColors.primary.withValues(alpha: 0.6)),
        const SizedBox(height: 16),
        const Text(
          '选择微信/支付宝导出的账单文件',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 8),
        Text(
          '支持 CSV / XLSX 文件（微信导出为 xlsx，支付宝为 csv）',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
        ),
        const SizedBox(height: 24),
        FilledButton.icon(
          key: const Key('pick_file_btn'),
          onPressed: _working ? null : _pickFile,
          icon: const Icon(Icons.folder_open),
          label: Text(_working ? '请选择文件…' : '选择账单文件'),
          style: FilledButton.styleFrom(
            backgroundColor: AppColors.primary,
            minimumSize: const Size.fromHeight(46),
          ),
        ),
        const SizedBox(height: 32),
        // 导出方法帮助
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: AppColors.surfaceGroup,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('如何导出账单？',
                  style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textMain)),
              const SizedBox(height: 8),
              _helpLine('微信：钱包 → 账单 → 下载账单 → 时间范围 → 发邮箱'),
              _helpLine('支付宝：我的 → 账单 → ⋯ → 开具交易流水证明'),
              _helpLine('邮箱收到加密压缩包 → 密码解压 → 得到 xlsx / csv 文件'),
            ],
          ),
        ),
      ],
    );
  }

  Widget _helpLine(String s) => Padding(
        padding: const EdgeInsets.only(bottom: 4),
        child: Text(s,
            style: const TextStyle(
                fontSize: 12, color: AppColors.textSecondary, height: 1.4)),
      );

  // ── 预览状态 ──
  Widget _buildPreview() {
    final result = _result!;
    final previewBills = result.bills.take(50).toList();
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Row(
          children: [
            const Icon(Icons.description_outlined,
                size: 18, color: AppColors.textSecondary),
            const SizedBox(width: 8),
            Expanded(
              child: Text(_fileName ?? '',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      fontSize: 13, color: AppColors.textMain)),
            ),
          ],
        ),
        const SizedBox(height: 12),
        // 统计
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: AppColors.surfaceGroup,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            children: [
              _stat('识别', '${result.bills.length}', AppColors.primary),
              _stat('重复', '$_dupCount', AppColors.expense),
              _stat('跳过', '${result.skippedRows}', AppColors.textSecondary),
            ],
          ),
        ),
        const SizedBox(height: 16),
        if (result.bills.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 32),
            child: Text(
              '未能从文件中识别到有效账单（可能格式不支持或均为退款/失败记录）',
              textAlign: TextAlign.center,
              style: TextStyle(
                  fontSize: 13,
                  color: AppColors.textSecondary.withValues(alpha: 0.8)),
            ),
          )
        else ...[
          const Text('预览（最新在前）',
              style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textSecondary)),
          const SizedBox(height: 4),
          ...previewBills.map((b) => _PreviewRow(bill: b)),
          if (result.bills.length > previewBills.length)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Text('… 其余 ${result.bills.length - previewBills.length} 条已识别',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                      fontSize: 12, color: AppColors.textSecondary)),
            ),
        ],
        const SizedBox(height: 24),
        Row(
          children: [
            Expanded(
              child: OutlinedButton(
                key: const Key('repick_btn'),
                onPressed: _working ? null : _pickFile,
                child: const Text('重新选择'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: FilledButton(
                key: const Key('confirm_import_btn'),
                onPressed:
                    (_working || result.bills.isEmpty) ? null : _confirmImport,
                style: FilledButton.styleFrom(
                    backgroundColor: AppColors.primary),
                child: Text(
                    _working ? '导入中…' : '确认导入 ${result.bills.length} 条'),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _stat(String label, String value, Color color) => Expanded(
        child: Column(
          children: [
            Text(value,
                style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                    color: color)),
            Text(label,
                style: const TextStyle(
                    fontSize: 11, color: AppColors.textSecondary)),
          ],
        ),
      );
}

/// 导入预览行
class _PreviewRow extends StatelessWidget {
  final ParsedBill bill;

  const _PreviewRow({required this.bill});

  @override
  Widget build(BuildContext context) {
    final isExpense = bill.type == RecordType.expense;
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 8),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: AppColors.divider, width: 0.5)),
      ),
      child: Row(
        children: [
          Icon(
            isExpense ? Icons.arrow_upward : Icons.arrow_downward,
            size: 16,
            color: isExpense ? AppColors.expense : AppColors.income,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  bill.counterpart.isEmpty ? '（无对方信息）' : bill.counterpart,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      fontSize: 14, color: AppColors.textMain),
                ),
                Text(
                  formatRecordTime(bill.time),
                  style: const TextStyle(
                      fontSize: 11, color: AppColors.textSecondary),
                ),
              ],
            ),
          ),
          Text(
            '${isExpense ? '-' : '+'}¥${Money.format(bill.amountCents)}',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: isExpense ? AppColors.expense : AppColors.income,
            ),
          ),
        ],
      ),
    );
  }
}
