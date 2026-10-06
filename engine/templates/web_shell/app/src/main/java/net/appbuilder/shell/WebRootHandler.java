package net.appbuilder.shell;

import android.content.res.AssetManager;
import android.webkit.WebResourceResponse;

import androidx.annotation.NonNull;
import androidx.webkit.WebViewAssetLoader;

import java.io.ByteArrayInputStream;
import java.io.IOException;
import java.io.InputStream;
import java.nio.charset.StandardCharsets;
import java.util.HashMap;
import java.util.Locale;
import java.util.Map;

/**
 * Serves assets/www/ as the root of https://appassets.androidplatform.net/.
 * Paths without an extension fall back to index.html (single-page apps).
 */
final class WebRootHandler implements WebViewAssetLoader.PathHandler {
    private static final Map<String, String> MIME_TYPES = new HashMap<>();

    static {
        String[][] types = {
            {"html", "text/html"}, {"htm", "text/html"}, {"js", "text/javascript"}, {"mjs", "text/javascript"},
            {"cjs", "text/javascript"}, {"css", "text/css"}, {"json", "application/json"}, {"map", "application/json"},
            {"webmanifest", "application/manifest+json"}, {"svg", "image/svg+xml"}, {"png", "image/png"},
            {"jpg", "image/jpeg"}, {"jpeg", "image/jpeg"}, {"gif", "image/gif"}, {"webp", "image/webp"},
            {"avif", "image/avif"}, {"ico", "image/x-icon"}, {"bmp", "image/bmp"}, {"wasm", "application/wasm"},
            {"woff", "font/woff"}, {"woff2", "font/woff2"}, {"ttf", "font/ttf"}, {"otf", "font/otf"},
            {"mp3", "audio/mpeg"}, {"ogg", "audio/ogg"}, {"oga", "audio/ogg"}, {"wav", "audio/wav"},
            {"m4a", "audio/mp4"}, {"aac", "audio/aac"}, {"flac", "audio/flac"}, {"mp4", "video/mp4"},
            {"webm", "video/webm"}, {"ogv", "video/ogg"}, {"txt", "text/plain"}, {"xml", "application/xml"},
            {"csv", "text/csv"}, {"pdf", "application/pdf"}, {"glb", "model/gltf-binary"},
            {"gltf", "model/gltf+json"}, {"bin", "application/octet-stream"}
        };
        for (String[] type : types) {
            MIME_TYPES.put(type[0], type[1]);
        }
    }

    private final AssetManager assets;

    WebRootHandler(AssetManager assets) {
        this.assets = assets;
    }

    @Override
    public WebResourceResponse handle(@NonNull String path) {
        String clean = path;
        while (clean.startsWith("/")) {
            clean = clean.substring(1);
        }
        for (String segment : clean.split("/")) {
            if (segment.equals("..")) {
                return notFound();
            }
        }
        if (clean.isEmpty() || clean.endsWith("/")) {
            clean = clean + "index.html";
        }
        String[] candidates = hasExtension(clean)
                ? new String[] {clean}
                : new String[] {clean, clean + "/index.html", clean + ".html", "index.html"};
        for (String candidate : candidates) {
            InputStream stream = open(candidate);
            if (stream != null) {
                return response(candidate, stream);
            }
        }
        return notFound();
    }

    private InputStream open(String relativePath) {
        try {
            return assets.open("www/" + relativePath);
        } catch (IOException e) {
            return null;
        }
    }

    private static boolean hasExtension(String path) {
        String last = path.substring(path.lastIndexOf('/') + 1);
        return last.lastIndexOf('.') > 0;
    }

    private static WebResourceResponse response(String path, InputStream stream) {
        String mime = mimeFor(path);
        boolean text = mime.startsWith("text/") || mime.contains("json") || mime.contains("xml") || mime.contains("javascript");
        WebResourceResponse response = new WebResourceResponse(mime, text ? "utf-8" : null, stream);
        Map<String, String> headers = new HashMap<>();
        headers.put("Cache-Control", "no-cache");
        headers.put("Access-Control-Allow-Origin", "*");
        response.setResponseHeaders(headers);
        return response;
    }

    private static WebResourceResponse notFound() {
        Map<String, String> headers = new HashMap<>();
        headers.put("Cache-Control", "no-cache");
        return new WebResourceResponse("text/plain", "utf-8", 404, "Not Found", headers,
                new ByteArrayInputStream("404 Not Found".getBytes(StandardCharsets.UTF_8)));
    }

    static String mimeFor(String path) {
        int dot = path.lastIndexOf('.');
        String extension = dot < 0 ? "" : path.substring(dot + 1).toLowerCase(Locale.ROOT);
        String mime = MIME_TYPES.get(extension);
        return mime == null ? "application/octet-stream" : mime;
    }
}
