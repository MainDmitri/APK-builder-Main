package net.appbuilder.app

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.IBinder

/**
 * Foreground service with a status notification while a build runs. It keeps
 * the process (and the Dart code polling the build) alive when AppBuilder is
 * in the background, so the APK download starts as soon as the build is
 * ready.
 */
class BuildWatchService : Service() {
    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        ensureChannels(this)
        val notification = notification(
            this,
            intent?.getStringExtra(EXTRA_TITLE) ?: "AppBuilder",
            intent?.getStringExtra(EXTRA_TEXT) ?: "",
            -1,
        )
        if (Build.VERSION.SDK_INT >= 29) {
            startForeground(NOTIFICATION_ID, notification, ServiceInfo.FOREGROUND_SERVICE_TYPE_DATA_SYNC)
        } else {
            startForeground(NOTIFICATION_ID, notification)
        }
        running = true
        return START_NOT_STICKY
    }

    override fun onTaskRemoved(rootIntent: Intent?) {
        stopSelf()
        super.onTaskRemoved(rootIntent)
    }

    /** Android 15+: data sync services are limited to 6 hours a day. */
    override fun onTimeout(startId: Int, fgsType: Int) {
        stopSelf()
    }

    override fun onDestroy() {
        running = false
        super.onDestroy()
    }

    override fun onBind(intent: Intent?): IBinder? = null

    companion object {
        private const val CHANNEL_WATCH = "build_watch"
        private const val CHANNEL_DONE = "build_done"
        private const val NOTIFICATION_ID = 4101
        private const val DONE_ID = 4102
        private const val EXTRA_TITLE = "title"
        private const val EXTRA_TEXT = "text"

        @Volatile
        private var running = false

        fun start(context: Context, title: String, text: String) {
            val intent = Intent(context, BuildWatchService::class.java)
                .putExtra(EXTRA_TITLE, title)
                .putExtra(EXTRA_TEXT, text)
            if (Build.VERSION.SDK_INT >= 26) context.startForegroundService(intent) else context.startService(intent)
        }

        /** [progress] 0..100, or -1 for an indeterminate bar. */
        fun update(context: Context, title: String, text: String, progress: Int) {
            if (!running) return
            manager(context).notify(NOTIFICATION_ID, notification(context, title, text, progress))
        }

        /** Stops the service; with a [title] a final dismissible notification stays. */
        fun stop(context: Context, title: String?, text: String?) {
            context.stopService(Intent(context, BuildWatchService::class.java))
            running = false
            if (title != null) {
                ensureChannels(context)
                val done = builder(context, CHANNEL_DONE)
                    .setContentTitle(title)
                    .setContentText(text ?: "")
                    .setStyle(Notification.BigTextStyle().bigText(text ?: ""))
                    .setAutoCancel(true)
                    .build()
                manager(context).notify(DONE_ID, done)
            }
        }

        private fun manager(context: Context) =
            context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager

        private fun ensureChannels(context: Context) {
            if (Build.VERSION.SDK_INT < 26) return
            val nm = manager(context)
            nm.createNotificationChannel(
                NotificationChannel(CHANNEL_WATCH, "Сборка APK", NotificationManager.IMPORTANCE_LOW).apply {
                    description = "Статус текущей сборки"
                    setShowBadge(false)
                }
            )
            nm.createNotificationChannel(
                NotificationChannel(CHANNEL_DONE, "Результат сборки", NotificationManager.IMPORTANCE_DEFAULT).apply {
                    description = "APK готов или сборка завершилась ошибкой"
                }
            )
        }

        private fun builder(context: Context, channel: String): Notification.Builder {
            val open = PendingIntent.getActivity(
                context,
                0,
                Intent(context, MainActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP),
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
            )
            val builder = if (Build.VERSION.SDK_INT >= 26) {
                Notification.Builder(context, channel)
            } else {
                @Suppress("DEPRECATION")
                Notification.Builder(context)
            }
            return builder
                .setSmallIcon(R.drawable.ic_stat_appbuilder)
                .setColor(0xFF8B5CF6.toInt())
                .setContentIntent(open)
                .setShowWhen(false)
        }

        private fun notification(context: Context, title: String, text: String, progress: Int): Notification =
            builder(context, CHANNEL_WATCH)
                .setContentTitle(title)
                .setContentText(text)
                .setOngoing(true)
                .setOnlyAlertOnce(true)
                .setProgress(100, progress.coerceIn(0, 100), progress < 0)
                .build()
    }
}
