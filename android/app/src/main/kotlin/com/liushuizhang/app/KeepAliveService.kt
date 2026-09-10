package com.liushuizhang.app

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.IBinder

/**
 * 前台保活服务（方案 B）：
 * 让进程保持"前台身份" → 系统省电/内存清理跳过本进程 →
 * NotificationListenerService 的系统绑定不断 → 通知必达。
 *
 * 只挂前台不做事；被杀后系统会尝试自动重启（START_STICKY）。
 * 与"通知自动记账"主开关联动：开关关 → 停服务。
 */
class KeepAliveService : Service() {

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        startAsForeground()
        return START_STICKY
    }

    private fun startAsForeground() {
        val nm = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        if (Build.VERSION.SDK_INT >= 26) {
            nm.createNotificationChannel(
                NotificationChannel(
                    CHANNEL_ID,
                    "监听保活",
                    NotificationManager.IMPORTANCE_MIN // 低重要度：无声、折叠进"正在运行"
                )
            )
        }
        val builder = if (Build.VERSION.SDK_INT >= 26) {
            Notification.Builder(this, CHANNEL_ID)
        } else {
            @Suppress("DEPRECATION")
            Notification.Builder(this)
        }
        val notification = builder
            .setSmallIcon(R.drawable.ic_stat_lsz)
            .setContentTitle("流水账正在监听收付款通知")
            .setContentText("在「通知自动记账」中可关闭")
            .setOngoing(true)
            .build()
        if (Build.VERSION.SDK_INT >= 34) {
            // Android 14+：前台服务必须声明类型
            startForeground(
                NOTIFICATION_ID,
                notification,
                ServiceInfo.FOREGROUND_SERVICE_TYPE_SPECIAL_USE
            )
        } else {
            startForeground(NOTIFICATION_ID, notification)
        }
    }

    companion object {
        const val CHANNEL_ID = "lsz_keepalive_channel"
        const val NOTIFICATION_ID = 998875
    }
}
