package com.liushuizhang.app

import android.util.Log
import org.json.JSONArray
import org.json.JSONObject
import java.io.File

/**
 * 「未识别通知」留痕（2026-09-29 新增，方案 C）。
 *
 * 目的：把"疑似收付款、但没被自动记账"的通知原文留在本机，App 内可查看/一键复制，
 * 用于持续补齐放行规则与解析规则 —— 以前只能靠用户截图通知栏，现在自带清单。
 *
 * 两个写入方，统一走本对象（@Synchronized → 单写入者，避免读改写竞态）：
 *  - [NotifyListenerService]：被标题闸门拦下的通知（source = native）
 *  - Dart 侧解析器认不出的通知（source = parser，经 lsz_notify 通道 append）
 *
 * 文件：应用私有目录 unparsed_log.json，环形上限 [MAX] 条（超出丢最旧）。
 * 注意：仅本机保存，不上传（与本 App 其它数据一致）。
 */
object UnparsedLog {

    const val FILE_NAME = "unparsed_log.json"
    const val MAX = 100

    private const val TAG = "LszUnparsed"

    /**
     * 「疑似支付」特征词（比放行词表更宽：只决定"要不要留痕"，不影响是否记账）。
     * 例：微信群聊「转我50元」也会留痕 —— 宁可多留几条，也别把真支付漏在外面。
     */
    private val SUSPICIOUS_KEYWORDS = listOf(
        "支付", "付款", "收款", "退款", "退回", "退还", "到账", "转账",
        "红包", "扣款", "消费", "支出", "收入", "账单", "交易", "余额",
        "零钱", "花呗", "借呗", "还款", "元", "¥", "￥"
    )

    /** 无"元/¥"字样但带两位小数的金额（如 62.60） */
    private val AMOUNT_RE = Regex("""\d+\.\d{2}""")

    /** 这条通知看起来像收付款吗（留痕判据） */
    fun looksLikePayment(title: String, text: String): Boolean {
        val s = "$title $text"
        return SUSPICIOUS_KEYWORDS.any { s.contains(it) } || AMOUNT_RE.containsMatchIn(s)
    }

    /** 组装一条留痕记录（source 固定 native：被原生标题闸门拦下） */
    fun nativeEntry(
        pkg: String,
        title: String,
        text: String,
        timeMs: Long,
        channel: String,
        reason: String
    ): JSONObject = JSONObject().apply {
        put("time", timeMs)
        put("source", "native")
        put("pkg", pkg)
        put("title", title)
        put("text", text.take(200))
        put("channel", channel)
        put("reason", reason)
    }

    /** 追加一条（超出 [MAX] 丢最旧） */
    @Synchronized
    fun append(dir: File, entry: JSONObject) {
        try {
            val f = File(dir, FILE_NAME)
            val arr = readArray(f)
            arr.put(entry)
            while (arr.length() > MAX) {
                arr.remove(0)
            }
            f.writeText(arr.toString())
        } catch (e: Exception) {
            Log.e(TAG, "append failed", e)
        }
    }

    /** 读取全部（无文件/损坏 → "[]"；Dart 侧按 JSON 数组解析） */
    @Synchronized
    fun read(dir: File): String {
        return try {
            readArray(File(dir, FILE_NAME)).toString()
        } catch (e: Exception) {
            Log.e(TAG, "read failed", e)
            "[]"
        }
    }

    /** 清空（删除文件） */
    @Synchronized
    fun clear(dir: File) {
        try {
            val f = File(dir, FILE_NAME)
            if (f.exists()) f.delete()
        } catch (e: Exception) {
            Log.e(TAG, "clear failed", e)
        }
    }

    /** 读成 JSONArray（不存在/损坏 → 空数组，不让脏文件拖垮写入） */
    private fun readArray(f: File): JSONArray {
        if (!f.exists()) return JSONArray()
        return try {
            val raw = f.readText()
            if (raw.isBlank()) JSONArray() else JSONArray(raw)
        } catch (e: Exception) {
            Log.e(TAG, "corrupt log, reset", e)
            JSONArray()
        }
    }
}
