package net.appbuilder.samples.counter

import android.content.Context
import androidx.core.content.edit
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow

/** Counter value persisted in SharedPreferences. */
class CounterStore(context: Context) {
    private val prefs = context.getSharedPreferences("counter", Context.MODE_PRIVATE)
    private val state = MutableStateFlow(prefs.getInt(KEY, 0))

    val value: StateFlow<Int> = state.asStateFlow()

    fun set(newValue: Int) {
        state.value = newValue
        prefs.edit { putInt(KEY, newValue) }
    }

    private companion object {
        const val KEY = "value"
    }
}
