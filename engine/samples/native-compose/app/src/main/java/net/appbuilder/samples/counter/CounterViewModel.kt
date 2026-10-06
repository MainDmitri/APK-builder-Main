package net.appbuilder.samples.counter

import android.app.Application
import androidx.lifecycle.AndroidViewModel
import kotlinx.coroutines.flow.StateFlow

class CounterViewModel(application: Application) : AndroidViewModel(application) {
    private val store = CounterStore(application)

    val count: StateFlow<Int> = store.value

    fun increment() = store.set(count.value + 1)

    fun decrement() = store.set(count.value - 1)

    fun reset() = store.set(0)
}
