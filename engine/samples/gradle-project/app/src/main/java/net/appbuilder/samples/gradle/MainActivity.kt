package net.appbuilder.samples.gradle

import android.app.Activity
import android.os.Build
import android.os.Bundle
import android.util.TypedValue
import android.widget.ScrollView
import android.widget.TextView

/** Shows real information about the device the app runs on. */
class MainActivity : Activity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        val metrics = resources.displayMetrics
        val info = buildString {
            appendLine("Производитель: ${Build.MANUFACTURER}")
            appendLine("Модель: ${Build.MODEL}")
            appendLine("Android: ${Build.VERSION.RELEASE} (API ${Build.VERSION.SDK_INT})")
            appendLine("ABI: ${Build.SUPPORTED_ABIS.joinToString()}")
            appendLine("Экран: ${metrics.widthPixels}×${metrics.heightPixels}, ${metrics.densityDpi} dpi")
            appendLine("Процессоров: ${Runtime.getRuntime().availableProcessors()}")
            appendLine("Память JVM: ${Runtime.getRuntime().maxMemory() / 1024 / 1024} МБ")
        }
        val text = TextView(this).apply {
            text = info
            setTextSize(TypedValue.COMPLEX_UNIT_SP, 18f)
            val pad = (24 * metrics.density).toInt()
            setPadding(pad, pad * 2, pad, pad)
        }
        setContentView(ScrollView(this).apply { addView(text) })
    }
}
