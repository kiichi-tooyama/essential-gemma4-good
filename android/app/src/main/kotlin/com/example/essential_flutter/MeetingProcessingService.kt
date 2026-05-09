package com.example.essential_flutter

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.IBinder
import android.os.PowerManager

class MeetingProcessingService : Service() {
    private var wakeLock: PowerManager.WakeLock? = null

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (intent?.action == ACTION_STOP) {
            releaseWakeLock()
            stopForeground(STOP_FOREGROUND_REMOVE)
            stopSelf()
            return START_NOT_STICKY
        }
        ensureChannel()
        acquireWakeLock()
        startForeground(NOTIFICATION_ID, buildNotification(intent))
        return START_STICKY
    }

    override fun onDestroy() {
        releaseWakeLock()
        super.onDestroy()
    }

    private fun acquireWakeLock() {
        if (wakeLock?.isHeld == true) {
            return
        }
        val powerManager = getSystemService(Context.POWER_SERVICE) as PowerManager
        wakeLock = powerManager.newWakeLock(
            PowerManager.PARTIAL_WAKE_LOCK,
            "$packageName:meeting-processing",
        ).apply {
            setReferenceCounted(false)
            acquire(2 * 60 * 60 * 1000L)
        }
    }

    private fun releaseWakeLock() {
        try {
            if (wakeLock?.isHeld == true) {
                wakeLock?.release()
            }
        } catch (_: Exception) {
        } finally {
            wakeLock = null
        }
    }

    private fun ensureChannel() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) {
            return
        }
        val manager = getSystemService(NotificationManager::class.java)
        val channel = NotificationChannel(
            CHANNEL_ID,
            "会議アシスタント",
            NotificationManager.IMPORTANCE_LOW,
        ).apply {
            description = "会議音声の文字起こし、要約、翻訳を処理しています"
            setShowBadge(false)
        }
        manager.createNotificationChannel(channel)
        val doneChannel = NotificationChannel(
            DONE_CHANNEL_ID,
            "会議アシスタント完了",
            NotificationManager.IMPORTANCE_DEFAULT,
        ).apply {
            description = "会議処理の完了と失敗を通知します"
        }
        manager.createNotificationChannel(doneChannel)
    }

    private fun buildNotification(intent: Intent?): Notification {
        val stage = intent?.getStringExtra(EXTRA_STAGE)?.takeIf { it.isNotBlank() }
            ?: "会議を処理中"
        val detail = intent?.getStringExtra(EXTRA_DETAIL)?.takeIf { it.isNotBlank() }
            ?: "バックグラウンドで処理を続けています"
        val openIntent = Intent(this, MainActivity::class.java).apply {
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP)
        }
        val openPendingIntent = PendingIntent.getActivity(
            this,
            0,
            openIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
        return Notification.Builder(this, CHANNEL_ID)
            .setSmallIcon(android.R.drawable.ic_btn_speak_now)
            .setContentTitle(stage)
            .setContentText(detail)
            .setOngoing(true)
            .setOnlyAlertOnce(true)
            .setContentIntent(openPendingIntent)
            .build()
    }

    companion object {
        private const val CHANNEL_ID = "essential_meeting_processing"
        private const val DONE_CHANNEL_ID = "essential_meeting_done"
        private const val NOTIFICATION_ID = 43020
        private const val DONE_NOTIFICATION_ID = 43021
        private const val ACTION_STOP = "com.example.essential_flutter.STOP_MEETING_PROCESSING"
        private const val EXTRA_STAGE = "stage"
        private const val EXTRA_DETAIL = "detail"

        fun start(context: Context, stage: String, detail: String) {
            val intent = Intent(context, MeetingProcessingService::class.java).apply {
                putExtra(EXTRA_STAGE, stage)
                putExtra(EXTRA_DETAIL, detail)
            }
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                context.startForegroundService(intent)
            } else {
                context.startService(intent)
            }
        }

        fun stop(context: Context) {
            context.stopService(Intent(context, MeetingProcessingService::class.java))
        }

        fun showCompleted(context: Context, title: String, sessionId: String) {
            stop(context)
            showDoneNotification(
                context,
                "会議処理が完了しました",
                title.ifBlank { "要約と文字起こしを確認できます" },
                sessionId,
            )
        }

        fun showFailed(context: Context, detail: String) {
            stop(context)
            showDoneNotification(
                context,
                "会議処理に失敗しました",
                detail.ifBlank { "アプリを開いて詳細を確認してください" },
                "",
            )
        }

        private fun showDoneNotification(
            context: Context,
            title: String,
            detail: String,
            sessionId: String,
        ) {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                val manager = context.getSystemService(NotificationManager::class.java)
                val channel = NotificationChannel(
                    DONE_CHANNEL_ID,
                    "会議アシスタント完了",
                    NotificationManager.IMPORTANCE_DEFAULT,
                ).apply {
                    description = "会議処理の完了と失敗を通知します"
                }
                manager.createNotificationChannel(channel)
            }
            val openIntent = Intent(context, MainActivity::class.java).apply {
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP)
                putExtra("meeting_session_id", sessionId)
            }
            val openPendingIntent = PendingIntent.getActivity(
                context,
                DONE_NOTIFICATION_ID,
                openIntent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
            )
            val notification = Notification.Builder(context, DONE_CHANNEL_ID)
                .setSmallIcon(android.R.drawable.ic_btn_speak_now)
                .setContentTitle(title)
                .setContentText(detail)
                .setStyle(Notification.BigTextStyle().bigText(detail))
                .setOngoing(false)
                .setAutoCancel(true)
                .setContentIntent(openPendingIntent)
                .build()
            val manager = context.getSystemService(NotificationManager::class.java)
            manager.notify(DONE_NOTIFICATION_ID, notification)
        }
    }
}
