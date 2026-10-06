package net.appbuilder.shell;

import android.content.Context;
import android.graphics.Color;
import android.net.Uri;

import org.json.JSONObject;

import java.io.ByteArrayOutputStream;
import java.io.InputStream;
import java.nio.charset.StandardCharsets;
import java.util.Locale;

/** Runtime configuration written by AppBuilder Engine into assets/appbuilder-shell.json. */
final class ShellConfig {
    static final String LOCAL_HOST = "appassets.androidplatform.net";
    static final String LOCAL_ORIGIN = "https://" + LOCAL_HOST;

    final String startUrl;
    final boolean fullscreen;
    final int themeColor;
    final int backgroundColor;
    final boolean openLinksExternally;
    /** Remote start host without "www." (remote-site mode), otherwise null. */
    final String remoteSite;

    private ShellConfig(JSONObject json) {
        startUrl = json.optString("startUrl", "index.html");
        fullscreen = json.optBoolean("fullscreen", false);
        themeColor = parseColor(json.optString("themeColor", "#1565C0"), 0xFF1565C0);
        backgroundColor = parseColor(json.optString("backgroundColor", "#FFFFFF"), Color.WHITE);
        openLinksExternally = json.optBoolean("openLinksExternally", true);
        String host = isRemote() ? Uri.parse(startUrl).getHost() : null;
        remoteSite = host == null ? null : stripWww(host.toLowerCase(Locale.ROOT));
    }

    static ShellConfig load(Context context) {
        try (InputStream in = context.getAssets().open("appbuilder-shell.json")) {
            ByteArrayOutputStream out = new ByteArrayOutputStream();
            byte[] buffer = new byte[8192];
            int read;
            while ((read = in.read(buffer)) > 0) {
                out.write(buffer, 0, read);
            }
            return new ShellConfig(new JSONObject(new String(out.toByteArray(), StandardCharsets.UTF_8)));
        } catch (Exception e) {
            return new ShellConfig(new JSONObject());
        }
    }

    boolean isRemote() {
        return startUrl.startsWith("https://") || startUrl.startsWith("http://");
    }

    String initialUrl() {
        if (isRemote()) {
            return startUrl;
        }
        if (startUrl.isEmpty() || startUrl.equals("index.html")) {
            return LOCAL_ORIGIN + "/";
        }
        return LOCAL_ORIGIN + "/" + startUrl;
    }

    /** Hosts that stay inside the app: bundled assets and the remote site (with subdomains). */
    boolean isAppHost(String host) {
        if (host == null) {
            return false;
        }
        String h = host.toLowerCase(Locale.ROOT);
        if (LOCAL_HOST.equals(h)) {
            return true;
        }
        return remoteSite != null && (stripWww(h).equals(remoteSite) || h.endsWith("." + remoteSite));
    }

    static boolean isLight(int color) {
        double luminance = (0.299 * Color.red(color) + 0.587 * Color.green(color) + 0.114 * Color.blue(color)) / 255.0;
        return luminance > 0.6;
    }

    private static String stripWww(String host) {
        return host.startsWith("www.") ? host.substring(4) : host;
    }

    private static int parseColor(String value, int fallback) {
        try {
            return Color.parseColor(value);
        } catch (IllegalArgumentException e) {
            return fallback;
        }
    }
}
