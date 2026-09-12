import 'package:flutter/material.dart';

import '../app_theme.dart';
import 'notify_setting_page.dart';

/// 「使用教程」页（2026-09-10）
///
/// 面向普通用户：讲清 **三条记账途径怎么配合**（自动监听 / 导入账单 / 手动记录）
/// 以及各功能的具体用法。
/// 结构：顶部常显「三途径总览卡」+ 8 个可折叠分区（第 ① 节默认展开）。
class TutorialPage extends StatelessWidget {
  const TutorialPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('使用教程')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const _OverviewCard(),
          const SizedBox(height: 14),

          // ── ① 三条途径怎么配合（默认展开）──
          _Section(
            icon: Icons.alt_route,
            title: '① 三条途径怎么配合',
            initiallyExpanded: true,
            children: [
              _bullet('自动监听：付钱/收钱后，微信、支付宝的系统通知一到，软件就自动记下来'
                  '（先放进「待确认」等你确认）。覆盖微信支付、微信收款到账、支付宝的大部分交易。'),
              _bullet('导入账单：把微信/支付宝的官方账单文件导进来，一次补齐一整段时间的交易。'
                  '它是补历史账单的唯一办法，也是补盲区的主力。建议每月一次。'),
              _bullet('手动记录：主页右下角「+」，自己填金额、分类、备注。'
                  '临时补记、现金、当面扫码付款用这个。'),
              const SizedBox(height: 2),
              _warnBox(
                title: '这些情况自动监听收不到（要靠导入或手动补）',
                items: const [
                  '支付宝「被扫」付款（商家扫你的付款码）——支付宝不发通知，多次实测都没有',
                  '微信主动转账/发红包给对方、微信群里收发红包——微信不发通知',
                  '手机没网、通知被系统拦截、软件被「强行停止」时',
                ],
              ),
            ],
          ),

          // ── ② 第一次使用 ──
          _Section(
            icon: Icons.play_circle_outline,
            title: '② 第一次使用（四步）',
            children: [
              _step(1, '进「我的 → 通知自动记账」，打开顶部开关，按提示去系统里授权「通知使用权」'),
              _step(2, '在手机系统设置里允许本软件自启动和后台运行——找「应用启动管理 / 自启动管理 / '
                  '后台运行管理」，把「流水账」设为允许（各品牌路径不同：华为/荣耀在「应用启动管理」，'
                  '小米在「自启动」，OPPO/vivo 在「自启动 / 后台运行」）'),
              _step(3, '如果「通知自动记账」页里提示「后台运行权限 未允许」，点它一下，'
                  '在系统弹窗里选「允许」——部分手机（如荣耀）不加这一项，后台会收不到通知'),
              _step(4, '建议同时打开「后台保活（推荐）」'),
              _p('做完就不用一直开着软件了，正常用手机即可。'),
              _noteBox('从最近任务里划掉软件不影响记账；只有在系统设置里点了「强行停止」才会暂停监听，'
                  '重新打开软件就会自动恢复。'),
              const SizedBox(height: 10),
              OutlinedButton.icon(
                key: const Key('tutorial_go_notify'),
                onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                    builder: (_) => const NotifySettingPage())),
                icon: const Icon(Icons.notifications_active_outlined, size: 18),
                label: const Text('去开启自动监听',
                    style: TextStyle(fontSize: 13)),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.primary,
                  side: const BorderSide(color: AppColors.primary),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10)),
                  minimumSize: const Size.fromHeight(42),
                ),
              ),
            ],
          ),

          // ── ③ 自动监听怎么用 ──
          _Section(
            icon: Icons.notifications_active_outlined,
            title: '③ 自动监听怎么用',
            children: [
              _bullet('记下来的账先进入「待确认」，主页顶部会出现「有 N 条待确认」提示条'),
              _bullet('待确认页可以：点 ✓ 直接入账；点整行去编辑（补商户名、分类、改金额）；删除误记'),
              _bullet('也可以多选批量处理，或点右上角「全部确认」一次性入账'),
              _bullet('待确认堆到 20 条以上时，超过两天的会自动入账（记为未分类），'
                  '不会无限堆积，之后也能随时编辑'),
              _bullet('收不到通知时：进「我的 → 通知自动记账」看顶部状态条；异常就点「立即修复」，'
                  '或把系统里的通知使用权开关关掉再打开'),
            ],
          ),

          // ── ④ 导入账单 ──
          _Section(
            icon: Icons.file_download_outlined,
            title: '④ 导入账单',
            children: [
              _subTitle('怎么导出官方账单'),
              _bullet('微信：我 → 服务 → 钱包 → 账单 → 右上角「常见问题」→ 下载账单 → 用于个人对账 → '
                  '选时间范围 → 填邮箱 → 邮件里下载压缩包（密码在邮件中）→ 解压得到文件'),
              _bullet('支付宝：我的 → 账单 → 右上角「…」→ 开具交易流水证明 → 用于个人对账 → '
                  '选时间范围 → 填邮箱 → 解压得到文件'),
              const SizedBox(height: 6),
              _subTitle('怎么导入'),
              _bullet('我的 → 导入账单文件 → 选账户（微信/支付宝）→ 选文件 → 看预览 → 确认导入'),
              _bullet('重复导入是安全的：按交易单号自动去重；已经用通知或手动记过的也会自动认出来合并'
                  '（并补上官方单号），不会变成两条'),
              _noteBox('建议每月初导出上个月的账单导入一次。'),
            ],
          ),

          // ── ⑤ 手动记录与查看账单 ──
          _Section(
            icon: Icons.edit_outlined,
            title: '⑤ 手动记录与查看账单',
            children: [
              _p('点主页右下角「+」：填金额 → 选支出/收入 → 选分类 → 可选填对方/商户与备注 → '
                  '选日期 → 保存。'),
              _p('主页列表可点开编辑、多选批量删除；顶部可按账户 / 时间跨度 / 收支筛选，'
                  '汇总卡实时显示收入、支出、结余。'),
            ],
          ),

          // ── ⑥ 分类管理 ──
          _Section(
            icon: Icons.category_outlined,
            title: '⑥ 分类管理',
            children: [
              _bullet('支出/收入分开管理；可停用不需要的内置分类（历史记录不受影响）'),
              _bullet('可新增自定义分类：自己起名 + 从图标库里挑图标'),
              _bullet('「其他」始终排在最后；删掉自定义分类后，属于它的历史记录会回到「未分类」'),
            ],
          ),

          // ── ⑦ 备份与恢复 ──
          _Section(
            icon: Icons.backup_outlined,
            title: '⑦ 备份与恢复',
            children: [
              _bullet('导出备份：全部账单导出为 CSV（Excel/WPS 可打开）或 JSON（完整备份），'
                  '保存位置自己选'),
              _bullet('导入备份：选一个 JSON 备份恢复 —— 「合并去重」（推荐，不动现有数据）'
                  '或「全量覆盖」（先清空再替换，会二次确认）'),
              _bullet('换手机：旧手机导出 JSON → 传文件到新手机 → 新手机「导入备份」恢复'),
            ],
          ),

          // ── ⑧ 常见问题 ──
          _Section(
            icon: Icons.help_outline,
            title: '⑧ 常见问题',
            children: [
              _faq('会不会重复记账？',
                  '不会。通知之间按金额+时间判重；导入按官方单号判重，已经记过的会自动合并。'),
              _faq('数据会上传吗？',
                  '不会。全部数据只存在你自己手机里，通知也只在本机解析，不联网上传。'),
              _faq('为什么有的消费没记上？',
                  '见第 ① 节的提醒：被扫支付、发红包/群红包等场景平台本身不发通知。'
                  '用「导入账单」或「手动记录」补上即可。'),
              _faq('不小心删了记录怎么办？',
                  '删除不可撤销。建议定期「导出备份」，误删后可从备份合并恢复。'),
              _faq('待确认一直不处理会怎样？',
                  '可以一直放着，也可以直接删掉。堆到 20 条以上时，超过两天的会自动入账（未分类）。'),
            ],
          ),
        ],
      ),
    );
  }
}

// ──────────────────────────── 顶部总览卡 ────────────────────────────

/// 常显：三条途径一句话分工
class _OverviewCard extends StatelessWidget {
  const _OverviewCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.primarySoft,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(children: [
            Icon(Icons.auto_awesome, size: 16, color: AppColors.primary),
            SizedBox(width: 6),
            Text('三条途径怎么配合',
                style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: AppColors.primary)),
          ]),
          const SizedBox(height: 10),
          _line(Icons.notifications_active_outlined, '自动监听（日常主力）',
              '开着就自动记，不用管'),
          const SizedBox(height: 8),
          _line(Icons.file_download_outlined, '导入账单（每月兜底）',
              '月底导一次官方账单，补齐没记上的'),
          const SizedBox(height: 8),
          _line(Icons.edit_outlined, '手动记录（随手补）',
              '点「+」记一笔，现金、被扫支付都能补'),
          const SizedBox(height: 10),
          Container(height: 1, color: AppColors.primary.withValues(alpha: 0.15)),
          const SizedBox(height: 8),
          const Text(
            '平时靠自动监听，月底导一次对账，剩下的随手记。三种方式不会重复记账。',
            style: TextStyle(
                fontSize: 12,
                height: 1.6,
                color: AppColors.textSecondary),
          ),
        ],
      ),
    );
  }

  Widget _line(IconData icon, String title, String desc) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 1),
          child: Icon(icon, size: 16, color: AppColors.primary),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title,
                  style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textMain)),
              const SizedBox(height: 1),
              Text(desc,
                  style: const TextStyle(
                      fontSize: 12, color: AppColors.textSecondary)),
            ],
          ),
        ),
      ],
    );
  }
}

// ──────────────────────────── 折叠分区 ────────────────────────────

/// 单个可折叠分区：白底 + 细边框 + 主色图标标题
class _Section extends StatelessWidget {
  const _Section({
    required this.icon,
    required this.title,
    required this.children,
    this.initiallyExpanded = false,
  });

  final IconData icon;
  final String title;
  final List<Widget> children;
  final bool initiallyExpanded;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.divider),
      ),
      clipBehavior: Clip.antiAlias,
      // 注意：背景色必须由 Material 提供（不能放在外层容器上）——ExpansionTile 内部是
      // ListTile，若被带背景色的 DecoratedBox 包住，框架会断言 "ListTile background
      // color or ink splashes may be invisible"（水波纹被遮住），test 直接失败。
      child: Material(
        color: AppColors.background,
        child: Theme(
          // 去掉 ExpansionTile 默认的上下分隔线（与本项目"细边框卡片"风格统一）
          data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
          child: ExpansionTile(
            initiallyExpanded: initiallyExpanded,
            tilePadding:
                const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
            childrenPadding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
            expandedCrossAxisAlignment: CrossAxisAlignment.start,
            leading: Icon(icon, size: 20, color: AppColors.primary),
            iconColor: AppColors.primary,
            collapsedIconColor: AppColors.textSecondary,
            title: Text(title,
                style: const TextStyle(
                    fontSize: 14.5,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textMain)),
            children: children,
          ),
        ),
      ),
    );
  }
}

// ──────────────────────────── 文案零件 ────────────────────────────

/// 正文段落
Widget _p(String text) => Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(text,
          style: const TextStyle(
              fontSize: 13, height: 1.7, color: AppColors.textMain)),
    );

/// 小标题（分区内二级标题）
Widget _subTitle(String text) => Padding(
      padding: const EdgeInsets.only(top: 2, bottom: 6),
      child: Text(text,
          style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: AppColors.textMain)),
    );

/// 要点行（主色小圆点 + 正文）
Widget _bullet(String text) => Padding(
      padding: const EdgeInsets.only(bottom: 7),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 8, right: 8),
            child: Container(
              width: 5,
              height: 5,
              decoration: const BoxDecoration(
                  color: AppColors.primary, shape: BoxShape.circle),
            ),
          ),
          Expanded(
            child: Text(text,
                style: const TextStyle(
                    fontSize: 13, height: 1.7, color: AppColors.textMain)),
          ),
        ],
      ),
    );

/// 步骤行（圆形序号 + 正文）
Widget _step(int n, String text) => Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 20,
            height: 20,
            alignment: Alignment.center,
            decoration: const BoxDecoration(
                color: AppColors.primary, shape: BoxShape.circle),
            child: Text('$n',
                style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: Colors.white)),
          ),
          const SizedBox(width: 9),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(top: 1),
              child: Text(text,
                  style: const TextStyle(
                      fontSize: 13, height: 1.6, color: AppColors.textMain)),
            ),
          ),
        ],
      ),
    );

/// 提示条（浅蓝底 + 灯泡）
Widget _noteBox(String text) => Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(11),
      decoration: BoxDecoration(
        color: AppColors.primarySoft,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.only(top: 1),
            child: Icon(Icons.lightbulb_outline,
                size: 15, color: AppColors.primary),
          ),
          const SizedBox(width: 7),
          Expanded(
            child: Text(text,
                style: const TextStyle(
                    fontSize: 12,
                    height: 1.6,
                    color: AppColors.textSecondary)),
          ),
        ],
      ),
    );

/// 提醒条（浅橙底 + 警示图标）：用于"收不到通知"的盲区说明
Widget _warnBox({required String title, required List<String> items}) =>
    Container(
      padding: const EdgeInsets.all(11),
      decoration: BoxDecoration(
        color: AppColors.warnSoft,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            const Icon(Icons.error_outline,
                size: 15, color: AppColors.warn),
            const SizedBox(width: 6),
            Expanded(
              child: Text(title,
                  style: const TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                      color: AppColors.warn)),
            ),
          ]),
          const SizedBox(height: 7),
          for (final s in items)
            Padding(
              padding: const EdgeInsets.only(bottom: 5),
              child: Text('· $s',
                  style: const TextStyle(
                      fontSize: 12,
                      height: 1.6,
                      color: AppColors.textMain)),
            ),
        ],
      ),
    );

/// 常见问答
Widget _faq(String q, String a) => Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Q：$q',
              style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textMain)),
          const SizedBox(height: 3),
          Text('A：$a',
              style: const TextStyle(
                  fontSize: 12.5, height: 1.7, color: AppColors.textSecondary)),
        ],
      ),
    );
