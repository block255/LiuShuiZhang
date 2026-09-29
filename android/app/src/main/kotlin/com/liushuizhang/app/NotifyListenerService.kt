package com.liushuizhang.app

import android.app.Notification
import android.content.pm.ApplicationInfo
import android.service.notification.NotificationListenerService
import android.service.notification.StatusBarNotification
import android.util.Log
import org.json.JSONArray
import org.json.JSONObject
import java.io.File

/**
 * 通知监听服务（B2）：
 * 用户授权"通知使用权"后，微信/支付宝等目标应用的通知到达时由系统唤起本服务。
 *
 * 职责边界（见架构文档：原生只采集，解析纯 Dart 共用）：
 *  - 包名过滤（含 debug 自测放行自身包名）
 *  - 提取 标题/正文/到达时间 → 追加写入队列文件（App 可能不在运行，先落盘不丢）
 *  - 解析/去重/入库一律在 Flutter 侧（NotifyIngest，App 启动/回前台时补拉）
 */
class NotifyListenerService : NotificationListenerService() {

    override fun onNotificationPosted(sbn: StatusBarNotification) {
        // B3 主开关：用户在 App 内关闭"通知自动记账"后，通知到达直接丢弃（真省电）
        val prefs = getSharedPreferences(PREFS_NAME, MODE_PRIVATE)
        if (!prefs.getBoolean(KEY_LISTENER_ENABLED, true)) return

        val extras = sbn.notification?.extras ?: return
        // B3b 健康探测通知（自身包名 + probe 标记）：绕过包名过滤（release 也放行）
        val isProbe = extras.getBoolean(EXTRA_LSZ_PROBE, false)
        val pkg = sbn.packageName ?: return
        val selfTest = isDebuggable() && pkg == packageName
        if (!isProbe && !selfTest && !TARGET_PACKAGES.contains(pkg)) return

        // debug 自测通知会携带目标包名（伪装成微信/支付宝通知走完整链路）
        val targetPkg = extras.getString(EXTRA_LSZ_TARGET_PKG) ?: pkg
        val title = extras.getCharSequence(Notification.EXTRA_TITLE)?.toString() ?: ""
        val text = extras.getCharSequence(Notification.EXTRA_TEXT)?.toString() ?: ""
        // B4：记录通知渠道（channel），用于区分"支付类 vs 聊天/其它类"（只收支付渠道）
        val channel = sbn.notification?.channelId ?: ""
        if (title.isBlank() && text.isBlank()) return
        // B4 v3：标题特征预过滤——微信/支付宝支付与聊天杂项共用 channel（实测），
        // 只能按标题放行支付类；聊天（群名/人名标题）直接丢弃，零唤醒。
        // 设计：宁宽勿窄 + Flutter 解析器兜底（放行多了无害，漏了才丢支付）。
        // selfTest/probe 不受此规则限制（调试链路）。
        if (!isProbe && !selfTest && !titleAllowed(targetPkg, title)) {
            // 方案 C（2026-09-29）：疑似收付款却被闸门拦下 → 留痕，App 内「未识别通知」可见，
            // 用户复制上报即可补规则（此前只能靠截图通知栏，漏一类就要等下次真机复现）。
            if (UnparsedLog.looksLikePayment(title, text)) {
                UnparsedLog.append(
                    filesDir,
                    UnparsedLog.nativeEntry(
                        targetPkg, title, text, sbn.postTime, channel,
                        "标题不含支付关键词，未自动记账"
                    )
                )
            }
            return
        }
        appendToQueue(targetPkg, title, text, sbn.postTime, channel, isProbe)
    }

    /**
     * B4 v3（2026-09-29）：标题放行规则 = 「支付语义关键词表」命中即放行。
     *
     * 为什么升级：12 天里漏了两类通知（支付宝被扫「支付成功通知」、支付宝「退款提醒」），
     * 每漏一类都要改原生 → 打包 → 重装 → 重新授权。改成关键词表后，新标题基本
     * 无需再动原生；真正入库仍由 Dart 解析器把关（认不出只进「未识别通知」，绝不记错账）。
     *
     * 实测锚点：
     * - 微信支付 title="微信支付"（收付款统一走这个标题）
     * - 支付宝 title="交易提醒"（支出/收入）、"支付成功通知"（被扫）、"退款提醒"（退款）
     *
     * 设计：宁宽勿窄 —— 放行多了无害（解析器是第二道闸），漏放行才会真的丢账。
     * 只匹配 title：聊天/群消息的标题是人名或群名，不命中关键词 → 照旧零唤醒拦下。
     */
    private fun titleAllowed(pkg: String, title: String): Boolean {
        if (title.isBlank()) return false
        val keywords = when (pkg) {
            "com.tencent.mm" -> WECHAT_TITLE_KEYWORDS
            "com.eg.android.AlipayGphone" -> ALIPAY_TITLE_KEYWORDS
            else -> return false
        }
        return keywords.any { title.contains(it) }
    }

    private fun isDebuggable(): Boolean =
        (applicationInfo.flags and ApplicationInfo.FLAG_DEBUGGABLE) != 0

    @Synchronized
    private fun appendToQueue(
        pkg: String,
        title: String,
        text: String,
        time: Long,
        channel: String,
        probe: Boolean
    ) {
        try {
            val f = File(filesDir, QUEUE_FILE)
            val arr = JSONArray()
            if (f.exists()) {
                val raw = f.readText()
                if (raw.isNotBlank()) {
                    val existing = JSONArray(raw)
                    for (i in 0 until existing.length()) {
                        arr.put(existing.get(i))
                    }
                }
            }
            arr.put(JSONObject().apply {
                put("pkg", pkg)
                put("title", title)
                put("text", text)
                put("time", time)
                put("channel", channel)
                if (probe) put("probe", true)
            })
            f.writeText(arr.toString())
            Log.i(TAG, "queued: $pkg [$channel] $title")
            logCapture(pkg, title, text, time, channel)
        } catch (e: Exception) {
            Log.e(TAG, "appendToQueue failed", e)
        }
    }

    /**
     * 调试捕获日志（仅 debug 构建写）：每条捕获落一行 JSON 到 capture_log.txt，
     * 不受队列 drain 影响 —— B4 分析"支付 vs 聊天"渠道差异的样本源。
     * 环形上限 [CAPTURE_LOG_MAX] 行，超出丢最旧。
     */
    private fun logCapture(pkg: String, title: String, text: String, time: Long, channel: String) {
        if (!isDebuggable()) return
        try {
            val f = File(filesDir, CAPTURE_LOG)
            val lines = mutableListOf<String>()
            if (f.exists()) {
                lines.addAll(f.readLines())
            }
            val entry = JSONObject().apply {
                put("time", time)
                put("pkg", pkg)
                put("channel", channel)
                put("title", title)
                put("text", text.take(120))
            }
            lines.add(entry.toString())
            while (lines.size > CAPTURE_LOG_MAX) lines.removeAt(0)
            f.writeText(lines.joinToString("\n"))
        } catch (e: Exception) {
            Log.e(TAG, "capture log failed", e)
        }
    }

    companion object {
        private const val TAG = "LszNotify"

        /** 队列文件名（MainActivity 健康检测也读，故公开） */
        const val QUEUE_FILE = "notify_queue.json"
        private const val CAPTURE_LOG = "capture_log.txt"
        private const val CAPTURE_LOG_MAX = 300

        /** B3 主开关存储（与 MainActivity 的 lsz_notify 通道共用） */
        const val PREFS_NAME = "lsz_settings"
        const val KEY_LISTENER_ENABLED = "listener_enabled"

        /** 方案 B：前台保活开关（与主开关联动） */
        const val KEY_KEEPALIVE_ENABLED = "keepalive_enabled"

        /** 自测通知携带目标包名的 extra key（与 Flutter/模拟面板约定） */
        const val EXTRA_LSZ_TARGET_PKG = "lsz_target_pkg"

        /** 健康探测标记（B3b：设置页检测监听用，探测条目不入库） */
        const val EXTRA_LSZ_PROBE = "lsz_probe"

        /** 关注的平台包名（与 lib/services/notify/notify_account_map.dart 同步维护） */
        private val TARGET_PACKAGES = setOf(
            "com.tencent.mm", // 微信
            "com.eg.android.AlipayGphone" // 支付宝（真机 logcat 实证包名）
        )

        /**
         * B4 v3 微信：收付款通知统一走「微信支付」标题；其余为到账/收款/退款类
         * （真实样本持续补充中，宁宽勿窄）。
         */
        private val WECHAT_TITLE_KEYWORDS = listOf(
            "微信支付", "到账", "收款", "退款", "退回", "退还",
            "转账", "红包", "零钱", "付款"
        )

        /**
         * B4 v3 支付宝：标题形态多样（交易提醒 / 支付成功通知 / 退款提醒 …），
         * 按支付语义关键词放行。解析不了的会进「未识别通知」，不会记错账。
         */
        private val ALIPAY_TITLE_KEYWORDS = listOf(
            "交易", "支付", "付款", "收款", "到账", "退款", "退回", "退还",
            "转账", "红包", "扣款", "消费", "支出", "收入", "账单", "还款", "结息"
        )
    }
}
