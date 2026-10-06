package net.appbuilder.app

import android.Manifest
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/**
 * Bridges the Flutter UI to Android services that have no Flutter plugin
 * equivalent: DownloadManager (background APK download with a system
 * progress notification), PackageInstaller sessions (install progress and
 * the real failure reason) and a foreground service that keeps the build
 * status polling alive while the app is in the background.
 */
class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val messenger = flutterEngine.dartExecutor.binaryMessenger
        MethodChannel(messenger, "net.appbuilder.app/native").setMethodCallHandler { call, result ->
            try {
                handle(call, result)
            } catch (e: Exception) {
                result.error(e.javaClass.simpleName, e.message ?: e.toString(), null)
            }
        }
        EventChannel(messenger, "net.appbuilder.app/install").setStreamHandler(object : EventChannel.StreamHandler {
            override fun onListen(arguments: Any?, events: EventChannel.EventSink) {
                InstallEvents.sink = events
            }

            override fun onCancel(arguments: Any?) {
                InstallEvents.sink = null
            }
        })
    }

    private fun handle(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "requestNotifications" -> {
                if (Build.VERSION.SDK_INT >= 33 &&
                    checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED
                ) {
                    requestPermissions(arrayOf(Manifest.permission.POST_NOTIFICATIONS), REQUEST_NOTIFICATIONS)
                    result.success(false)
                } else {
                    result.success(true)
                }
            }
            "watchStart" -> {
                BuildWatchService.start(this, call.argument<String>("title") ?: "", call.argument<String>("text") ?: "")
                result.success(null)
            }
            "watchUpdate" -> {
                BuildWatchService.update(
                    this,
                    call.argument<String>("title") ?: "",
                    call.argument<String>("text") ?: "",
                    call.argument<Int>("progress") ?: -1,
                )
                result.success(null)
            }
            "watchStop" -> {
                BuildWatchService.stop(this, call.argument<String>("title"), call.argument<String>("text"))
                result.success(null)
            }
            "downloadsDir" -> result.success(ApkDownloads.directory(this).absolutePath)
            "downloadEnqueue" -> result.success(
                ApkDownloads.enqueue(
                    this,
                    url = call.argument<String>("url")!!,
                    headers = call.argument<Map<String, String>>("headers") ?: emptyMap(),
                    relativePath = call.argument<String>("relativePath")!!,
                    title = call.argument<String>("title") ?: "APK",
                    tag = call.argument<String>("tag")!!,
                )
            )
            "downloadQuery" -> result.success(ApkDownloads.query(this, call.argument<Number>("id")!!.toLong()))
            "downloadCancel" -> {
                ApkDownloads.cancel(this, call.argument<Number>("id")!!.toLong())
                result.success(null)
            }
            "canInstall" -> result.success(ApkInstall.canInstall(this))
            "openInstallSettings" -> {
                ApkInstall.openSettings(this)
                result.success(null)
            }
            "apkPackageName" -> result.success(ApkInstall.packageNameOf(this, call.argument<String>("path")!!))
            "install" -> result.success(ApkInstall.start(applicationContext, call.argument<String>("path")!!))
            "launch" -> {
                val intent = packageManager.getLaunchIntentForPackage(call.argument<String>("packageName")!!)
                if (intent == null) {
                    result.success(false)
                } else {
                    startActivity(intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
                    result.success(true)
                }
            }
            else -> result.notImplemented()
        }
    }

    override fun onResume() {
        super.onResume()
        // The installer confirmation is an activity: it may only be shown
        // while AppBuilder itself is on screen.
        InstallEvents.launcher = { confirm -> startActivity(confirm) }
        InstallEvents.pendingConfirm?.let { confirm ->
            InstallEvents.pendingConfirm = null
            startActivity(confirm)
        }
    }

    override fun onPause() {
        InstallEvents.launcher = null
        super.onPause()
    }

    override fun onDestroy() {
        // Without the UI nobody polls the build any more: drop the status notification.
        if (isFinishing && !isChangingConfigurations) BuildWatchService.stop(this, null, null)
        super.onDestroy()
    }

    private companion object {
        const val REQUEST_NOTIFICATIONS = 41
    }
}
