package net.appbuilder.app

import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.pm.PackageInstaller
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.os.SystemClock
import android.provider.Settings
import io.flutter.plugin.common.EventChannel
import java.io.File
import java.io.FileInputStream

/** Install progress events for Flutter (`net.appbuilder.app/install`). */
object InstallEvents {
    private val main = Handler(Looper.getMainLooper())

    @Volatile
    var sink: EventChannel.EventSink? = null

    /** Starts the system confirmation while AppBuilder is in the foreground. */
    var launcher: ((Intent) -> Unit)? = null

    /** Confirmation that arrived while AppBuilder was in the background. */
    var pendingConfirm: Intent? = null

    fun emit(sessionId: Int, stage: String, progress: Double? = null, code: Int? = null, message: String? = null, packageName: String? = null) {
        val event = mapOf(
            "sessionId" to sessionId,
            "stage" to stage,
            "progress" to progress,
            "code" to code,
            "message" to message,
            "packageName" to packageName,
        )
        main.post { sink?.success(event) }
    }
}

/**
 * Installs an APK through a PackageInstaller session: the copy into the
 * session reports real progress, and the result broadcast carries the exact
 * reason of a failure (signature conflict, downgrade, storage…).
 */
object ApkInstall {
    private const val ACTION_RESULT = "net.appbuilder.app.INSTALL_RESULT"

    fun canInstall(context: Context): Boolean =
        Build.VERSION.SDK_INT < 26 || context.packageManager.canRequestPackageInstalls()

    fun openSettings(context: Context) {
        if (Build.VERSION.SDK_INT >= 26) {
            context.startActivity(
                Intent(Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES, Uri.parse("package:${context.packageName}"))
            )
        }
    }

    fun packageNameOf(context: Context, path: String): String? {
        val pm = context.packageManager
        val info = if (Build.VERSION.SDK_INT >= 33) {
            pm.getPackageArchiveInfo(path, PackageManager.PackageInfoFlags.of(0))
        } else {
            @Suppress("DEPRECATION")
            pm.getPackageArchiveInfo(path, 0)
        }
        return info?.packageName
    }

    /** Returns the session id; progress and result arrive as [InstallEvents]. */
    fun start(context: Context, path: String): Int {
        val file = File(path)
        require(file.isFile) { "Файл APK не найден: $path" }
        val installer = context.packageManager.packageInstaller
        val params = PackageInstaller.SessionParams(PackageInstaller.SessionParams.MODE_FULL_INSTALL).apply {
            setSize(file.length())
            packageNameOf(context, path)?.let { setAppPackageName(it) }
            // Updates of apps installed by AppBuilder itself go through without a prompt.
            if (Build.VERSION.SDK_INT >= 31) setRequireUserAction(PackageInstaller.SessionParams.USER_ACTION_NOT_REQUIRED)
            if (Build.VERSION.SDK_INT >= 33) setPackageSource(PackageInstaller.PACKAGE_SOURCE_DOWNLOADED_FILE)
        }
        val sessionId = installer.createSession(params)
        Thread {
            try {
                installer.openSession(sessionId).use { session ->
                    FileInputStream(file).use { input ->
                        session.openWrite("base.apk", 0, file.length()).use { output ->
                            val buffer = ByteArray(256 * 1024)
                            val total = file.length().coerceAtLeast(1)
                            var copied = 0L
                            var lastEmit = 0L
                            while (true) {
                                val read = input.read(buffer)
                                if (read < 0) break
                                output.write(buffer, 0, read)
                                copied += read
                                val fraction = copied.toFloat() / total
                                session.setStagingProgress(fraction)
                                val now = SystemClock.uptimeMillis()
                                if (now - lastEmit >= 80) {
                                    lastEmit = now
                                    InstallEvents.emit(sessionId, "staging", fraction.toDouble())
                                }
                            }
                            session.fsync(output)
                        }
                    }
                    InstallEvents.emit(sessionId, "staging", 1.0)
                    val intent = Intent(context, InstallResultReceiver::class.java)
                        .setAction(ACTION_RESULT)
                        .setPackage(context.packageName)
                    val flags = PendingIntent.FLAG_UPDATE_CURRENT or
                        (if (Build.VERSION.SDK_INT >= 31) PendingIntent.FLAG_MUTABLE else 0)
                    val pending = PendingIntent.getBroadcast(context, sessionId, intent, flags)
                    session.commit(pending.intentSender)
                }
                InstallEvents.emit(sessionId, "committed")
            } catch (e: Exception) {
                try {
                    installer.abandonSession(sessionId)
                } catch (ignored: Exception) {
                }
                InstallEvents.emit(sessionId, "failure", message = e.message ?: e.toString())
            }
        }.start()
        return sessionId
    }
}

/** Receives the PackageInstaller session result. */
class InstallResultReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val sessionId = intent.getIntExtra(PackageInstaller.EXTRA_SESSION_ID, -1)
        when (val status = intent.getIntExtra(PackageInstaller.EXTRA_STATUS, PackageInstaller.STATUS_FAILURE)) {
            PackageInstaller.STATUS_PENDING_USER_ACTION -> {
                val confirm: Intent? = if (Build.VERSION.SDK_INT >= 33) {
                    intent.getParcelableExtra(Intent.EXTRA_INTENT, Intent::class.java)
                } else {
                    @Suppress("DEPRECATION")
                    intent.getParcelableExtra(Intent.EXTRA_INTENT)
                }
                if (confirm != null) {
                    val launch = InstallEvents.launcher
                    if (launch != null) launch(confirm) else InstallEvents.pendingConfirm = confirm
                }
                InstallEvents.emit(sessionId, "confirm")
            }
            PackageInstaller.STATUS_SUCCESS -> InstallEvents.emit(
                sessionId,
                "success",
                packageName = intent.getStringExtra(PackageInstaller.EXTRA_PACKAGE_NAME),
            )
            else -> InstallEvents.emit(
                sessionId,
                "failure",
                code = status,
                message = intent.getStringExtra(PackageInstaller.EXTRA_STATUS_MESSAGE),
            )
        }
    }
}
