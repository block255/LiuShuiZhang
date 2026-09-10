package com.liushuizhang.app

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.os.Build

/**
 * 开机自启（方案 B 补全）：
 * 手机重启后，若"通知自动记账 + 后台保活"开关都开着 → 自动拉起前台保活服务。
 * （监听服务本身由系统在开机时自动绑定已授权 listener；保活让进程常驻不断绑。）
 * 荣耀需在"应用启动管理"里允许自启动（引导页会提示）。
 */
class BootReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action != Intent.ACTION_BOOT_COMPLETED) return
        val prefs = context.getSharedPreferences(
            NotifyListenerService.PREFS_NAME,
            Context.MODE_PRIVATE
        )
        val listenerOn = prefs.getBoolean(
            NotifyListenerService.KEY_LISTENER_ENABLED, true
        )
        val keepAliveOn = prefs.getBoolean(
            NotifyListenerService.KEY_KEEPALIVE_ENABLED, false
        )
        if (!listenerOn || !keepAliveOn) return
        try {
            val svc = Intent(context, KeepAliveService::class.java)
            if (Build.VERSION.SDK_INT >= 26) {
                context.startForegroundService(svc)
            } else {
                context.startService(svc)
            }
        } catch (e: Exception) {
            // 后台启动限制/ROM 拦截：忽略（用户手动打开 App 时由启动流程兜底拉起）
        }
    }
}
