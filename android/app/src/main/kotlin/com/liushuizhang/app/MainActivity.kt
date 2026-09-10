package com.liushuizhang.app

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.provider.Settings
import android.util.Log
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import org.json.JSONArray
import java.io.File

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        // B1：暴露应用私有目录给 Dart 侧文件持久化（lsz_storage 通道）
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "lsz_storage"
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "getFilesDir" -> result.success(filesDir.absolutePath)
                else -> result.notImplemented()
            }
        }
        // B2：通知监听调试辅助（发自测系统通知 / 跳授权设置页）
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "lsz_notify"
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "postTestNotification" -> postTestNotification(
                    call.argument<String>("title") ?: "",
                    call.argument<String>("text") ?: "",
                    call.argument<String>("targetPkg"),
                    result
                )

                "openListenerSettings" -> {
                    startActivity(Intent(Settings.ACTION_NOTIFICATION_LISTENER_SETTINGS))
                    result.success(true)
                }

                "openAppNotificationSettings" -> {
                    val intent = Intent(Settings.ACTION_APP_NOTIFICATION_SETTINGS)
                        .putExtra(Settings.EXTRA_APP_PACKAGE, packageName)
                    startActivity(intent)
                    result.success(true)
                }

                "selfHealListener" -> {
                    selfHealListener(result)
                }

                "setListenerEnabled" -> {
                    val enabled = call.argument<Boolean>("enabled") ?: true
                    getSharedPreferences(
                        NotifyListenerService.PREFS_NAME,
                        Context.MODE_PRIVATE
                    ).edit().putBoolean(
                        NotifyListenerService.KEY_LISTENER_ENABLED,
                        enabled
                    ).apply()
                    result.success(true)
                }

                "getListenerEnabled" -> {
                    val enabled = getSharedPreferences(
                        NotifyListenerService.PREFS_NAME,
                        Context.MODE_PRIVATE
                    ).getBoolean(NotifyListenerService.KEY_LISTENER_ENABLED, true)
                    result.success(enabled)
                }

                "checkListenerHealth" -> {
                    checkListenerHealth(result)
                }

                "setKeepAlive" -> {
                    val on = call.argument<Boolean>("enabled") ?: false
                    setKeepAlive(on)
                    result.success(true)
                }

                "getKeepAlive" -> {
                    val on = getSharedPreferences(
                        NotifyListenerService.PREFS_NAME,
                        Context.MODE_PRIVATE
                    ).getBoolean(NotifyListenerService.KEY_KEEPALIVE_ENABLED, false)
                    result.success(on)
                }

                "startKeepAliveIfEnabled" -> {
                    val on = getSharedPreferences(
                        NotifyListenerService.PREFS_NAME,
                        Context.MODE_PRIVATE
                    ).getBoolean(NotifyListenerService.KEY_KEEPALIVE_ENABLED, false)
                    if (on) startKeepAliveService()
                    result.success(on)
                }

                else -> result.notImplemented()
            }
        }
        // 备份导出：系统"保存到"对话框（SAF，用户自选文件夹/文件名，零存储权限）
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "lsz_file"
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "saveTextFile" -> {
                    val fileName = call.argument<String>("fileName") ?: "export.txt"
                    val content = call.argument<String>("content") ?: ""
                    pendingSaveResult = result
                    pendingSaveContent = content
                    val intent = Intent(Intent.ACTION_CREATE_DOCUMENT).apply {
                        addCategory(Intent.CATEGORY_OPENABLE)
                        type = if (fileName.endsWith(".json")) {
                            "application/json"
                        } else {
                            "text/plain"
                        }
                        putExtra(Intent.EXTRA_TITLE, fileName)
                    }
                    startActivityForResult(intent, REQ_SAVE_FILE)
                }

                "pickFile" -> {
                    // 系统文件选择器（账单导入 / 备份恢复共用）
                    pendingPickResult = result
                    val intent = Intent(Intent.ACTION_OPEN_DOCUMENT).apply {
                        addCategory(Intent.CATEGORY_OPENABLE)
                        type = "*/*"
                    }
                    startActivityForResult(intent, REQ_PICK_FILE)
                }

                else -> result.notImplemented()
            }
        }
    }

    @Deprecated("Deprecated in Java")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode == REQ_SAVE_FILE) {
            val r = pendingSaveResult
            pendingSaveResult = null
            if (r == null) return
            if (resultCode == RESULT_OK && data?.data != null) {
                try {
                    val content = pendingSaveContent
                    pendingSaveContent = null
                    contentResolver.openOutputStream(data.data!!)?.use { out ->
                        out.write((content ?: "").toByteArray(Charsets.UTF_8))
                    }
                    r.success(true)
                } catch (e: Exception) {
                    r.error("save_failed", e.message, null)
                }
            } else {
                r.success(false) // 用户取消
            }
        } else if (requestCode == REQ_PICK_FILE) {
            val r = pendingPickResult
            pendingPickResult = null
            if (r == null) return
            if (resultCode == RESULT_OK && data?.data != null) {
                try {
                    val uri = data.data!!
                    var name = "file"
                    contentResolver.query(
                        uri, arrayOf(android.provider.OpenableColumns.DISPLAY_NAME),
                        null, null, null
                    )?.use { c ->
                        if (c.moveToFirst()) {
                            val idx = c.getColumnIndex(android.provider.OpenableColumns.DISPLAY_NAME)
                            if (idx >= 0) name = c.getString(idx) ?: name
                        }
                    }
                    val bytes = contentResolver.openInputStream(uri)?.use { it.readBytes() }
                    if (bytes != null) {
                        r.success(mapOf("name" to name, "bytes" to bytes))
                    } else {
                        r.success(null)
                    }
                } catch (e: Exception) {
                    r.error("pick_failed", e.message, null)
                }
            } else {
                r.success(null) // 用户取消
            }
        }
    }

    /** 发一条本 App 的系统通知（debug 自测监听链路用）。返回语义见 Flutter 侧。 */
    private fun postTestNotification(
        title: String,
        text: String,
        targetPkg: String?,
        result: MethodChannel.Result
    ) {
        if (Build.VERSION.SDK_INT >= 33 &&
            checkSelfPermission(android.Manifest.permission.POST_NOTIFICATIONS) !=
            PackageManager.PERMISSION_GRANTED
        ) {
            requestPermissions(
                arrayOf(android.Manifest.permission.POST_NOTIFICATIONS),
                REQ_POST_NOTIFICATIONS
            )
            result.success("permission_requested")
            return
        }
        val nm = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        if (Build.VERSION.SDK_INT >= 26) {
            nm.createNotificationChannel(
                NotificationChannel(
                    TEST_CHANNEL_ID,
                    "通知监听自测",
                    NotificationManager.IMPORTANCE_DEFAULT
                )
            )
        }
        val extras = Bundle().apply {
            if (targetPkg != null) {
                putString(NotifyListenerService.EXTRA_LSZ_TARGET_PKG, targetPkg)
            }
        }
        val builder = if (Build.VERSION.SDK_INT >= 26) {
            Notification.Builder(this, TEST_CHANNEL_ID)
        } else {
            @Suppress("DEPRECATION")
            Notification.Builder(this)
        }
        val notification = builder
            .setSmallIcon(R.mipmap.ic_launcher)
            .setContentTitle(title.ifBlank { "流水账测试通知" })
            .setContentText(text)
            .setExtras(extras)
            .setAutoCancel(true)
            .build()
        nm.notify(TEST_NOTIFICATION_ID, notification)
        result.success("posted")
    }

    /**
     * 自愈：禁用再启用监听服务组件，触发系统重新评估并重新绑定
     * 已授权的 NotificationListenerService（荣耀 kill 进程后不会自动重绑，
     * 此 hack 让 App 无需用户手动重开授权即可恢复监听）。
     */
    private fun selfHealListener(result: MethodChannel.Result) {
        val pm = packageManager
        val cn = ComponentName(this, NotifyListenerService::class.java)
        try {
            pm.setComponentEnabledSetting(
                cn,
                PackageManager.COMPONENT_ENABLED_STATE_DISABLED,
                PackageManager.DONT_KILL_APP
            )
            Handler(Looper.getMainLooper()).postDelayed({
                pm.setComponentEnabledSetting(
                    cn,
                    PackageManager.COMPONENT_ENABLED_STATE_ENABLED,
                    PackageManager.DONT_KILL_APP
                )
                result.success("healed")
            }, 600)
        } catch (e: Exception) {
            result.error("heal_failed", e.message, null)
        }
    }

    /**
     * 监听健康检测（B3b；2026-09-10 修：区分"未授权 / 无通知权限 / 真失联"）：
     *  ① 通知使用权未授权 → "no_access"
     *  ② Android 13+ 未授予本应用"通知权限"（自检靠发一条 probe 通知，
     *     无权限时 notify() 静默失败）→ 申请权限并返回 "no_permission"
     *     —— 否则会把"没权限"误报成"监听失联"
     *  ③ 发低重要度 probe 通知（自身包名 + probe 标记，绕过包名过滤）
     *     → 1.5s 后读队列：有 probe 条目 = "ok"（移除该条目）；没有 = "dead"
     * 探测条目 pkg=自身（映射表无此包名），即使漏删也永不入库。
     */
    private fun checkListenerHealth(result: MethodChannel.Result) {
        if (!hasNotificationAccess()) {
            result.success("no_access")
            return
        }
        if (Build.VERSION.SDK_INT >= 33 &&
            checkSelfPermission(android.Manifest.permission.POST_NOTIFICATIONS) !=
            PackageManager.PERMISSION_GRANTED
        ) {
            requestPermissions(
                arrayOf(android.Manifest.permission.POST_NOTIFICATIONS),
                REQ_PROBE_PERMISSIONS
            )
            result.success("no_permission")
            return
        }
        val nm = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        if (Build.VERSION.SDK_INT >= 26) {
            nm.createNotificationChannel(
                NotificationChannel(
                    PROBE_CHANNEL_ID,
                    "监听状态检查",
                    NotificationManager.IMPORTANCE_MIN
                )
            )
        }
        val extras = Bundle().apply {
            putBoolean(NotifyListenerService.EXTRA_LSZ_PROBE, true)
        }
        val builder = if (Build.VERSION.SDK_INT >= 26) {
            Notification.Builder(this, PROBE_CHANNEL_ID)
        } else {
            @Suppress("DEPRECATION")
            Notification.Builder(this)
        }
        nm.notify(
            PROBE_NOTIFICATION_ID,
            builder
                .setSmallIcon(R.drawable.ic_stat_lsz)
                .setContentTitle("流水账监听自检")
                .setContentText("")
                .setExtras(extras)
                .build()
        )
        Handler(Looper.getMainLooper()).postDelayed({
            var healthy = false
            try {
                val f = File(filesDir, NotifyListenerService.QUEUE_FILE)
                if (f.exists()) {
                    val raw = f.readText()
                    if (raw.isNotBlank()) {
                        val arr = JSONArray(raw)
                        val kept = JSONArray()
                        for (i in 0 until arr.length()) {
                            val o = arr.getJSONObject(i)
                            if (o.optBoolean("probe", false)) {
                                healthy = true // 找到探测条目 = 监听活着
                            } else {
                                kept.put(o)
                            }
                        }
                        f.writeText(kept.toString())
                    }
                }
            } catch (e: Exception) {
                Log.e("LszHealth", "check failed", e)
            }
            nm.cancel(PROBE_NOTIFICATION_ID)
            result.success(if (healthy) "ok" else "dead")
        }, 1500)
    }

    /** 本应用是否已获得"通知使用权"（系统设置里那个开关） */
    private fun hasNotificationAccess(): Boolean {
        val cn = ComponentName(this, NotifyListenerService::class.java)
        val flat = cn.flattenToString()
        val short = cn.flattenToShortString()
        val enabled = Settings.Secure.getString(
            contentResolver, "enabled_notification_listeners"
        ) ?: return false
        return enabled.split(":").any {
            it.equals(flat, ignoreCase = true) || it.equals(short, ignoreCase = true)
        }
    }

    /** 方案 B：启停前台保活服务（记录开关状态，随设置联动） */
    private fun setKeepAlive(on: Boolean) {
        getSharedPreferences(NotifyListenerService.PREFS_NAME, Context.MODE_PRIVATE)
            .edit()
            .putBoolean(NotifyListenerService.KEY_KEEPALIVE_ENABLED, on)
            .apply()
        if (on) {
            startKeepAliveService()
        } else {
            stopService(Intent(this, KeepAliveService::class.java))
        }
    }

    private fun startKeepAliveService() {
        val intent = Intent(this, KeepAliveService::class.java)
        if (Build.VERSION.SDK_INT >= 26) {
            startForegroundService(intent)
        } else {
            startService(intent)
        }
    }

    companion object {
        private const val REQ_POST_NOTIFICATIONS = 1001
        private const val REQ_SAVE_FILE = 1002
        private const val REQ_PICK_FILE = 1003
        private const val REQ_PROBE_PERMISSIONS = 1004
        private const val TEST_CHANNEL_ID = "lsz_test_channel"
        private const val TEST_NOTIFICATION_ID = 998877
        private const val PROBE_CHANNEL_ID = "lsz_probe_channel"
        private const val PROBE_NOTIFICATION_ID = 998876

        /** 待系统"保存到"对话框回传的通道结果 */
        private var pendingSaveResult: MethodChannel.Result? = null
        private var pendingSaveContent: String? = null

        /** 待系统文件选择器回传的通道结果 */
        private var pendingPickResult: MethodChannel.Result? = null
    }
}
