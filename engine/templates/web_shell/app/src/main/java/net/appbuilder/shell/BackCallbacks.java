package net.appbuilder.shell;

import android.app.Activity;
import android.window.OnBackInvokedCallback;
import android.window.OnBackInvokedDispatcher;

import androidx.annotation.RequiresApi;

/**
 * Android 13+ back handling. The callback is registered only while the WebView
 * can go back, so that the system back gesture (and predictive back animation)
 * closes the app on the first page.
 */
@RequiresApi(33)
final class BackCallbacks {
    private final Activity activity;
    private final OnBackInvokedCallback callback;
    private boolean registered;

    BackCallbacks(Activity activity, Runnable onBack) {
        this.activity = activity;
        this.callback = onBack::run;
    }

    void setEnabled(boolean enabled) {
        OnBackInvokedDispatcher dispatcher = activity.getOnBackInvokedDispatcher();
        if (enabled && !registered) {
            dispatcher.registerOnBackInvokedCallback(OnBackInvokedDispatcher.PRIORITY_DEFAULT, callback);
            registered = true;
        } else if (!enabled && registered) {
            dispatcher.unregisterOnBackInvokedCallback(callback);
            registered = false;
        }
    }
}
