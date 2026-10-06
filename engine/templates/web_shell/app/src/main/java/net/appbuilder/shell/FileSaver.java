package net.appbuilder.shell;

import android.Manifest;
import android.content.ContentResolver;
import android.content.ContentValues;
import android.content.Context;
import android.content.pm.PackageManager;
import android.net.Uri;
import android.os.Build;
import android.os.Environment;
import android.provider.MediaStore;
import android.util.Base64;

import java.io.File;
import java.io.FileOutputStream;
import java.io.IOException;
import java.io.OutputStream;
import java.nio.charset.StandardCharsets;

/** Writes files produced by the web app into the public Downloads folder. */
final class FileSaver {
    private FileSaver() {
    }

    /** Saves [data] and returns a user-readable location. */
    static String save(Context context, byte[] data, String fileName, String mimeType) throws IOException {
        String name = sanitize(fileName);
        String mime = mimeType == null || mimeType.isEmpty() ? WebRootHandler.mimeFor(name) : mimeType;
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            ContentResolver resolver = context.getContentResolver();
            ContentValues values = new ContentValues();
            values.put(MediaStore.MediaColumns.DISPLAY_NAME, name);
            values.put(MediaStore.MediaColumns.MIME_TYPE, mime);
            values.put(MediaStore.MediaColumns.RELATIVE_PATH, Environment.DIRECTORY_DOWNLOADS);
            Uri uri = resolver.insert(MediaStore.Downloads.EXTERNAL_CONTENT_URI, values);
            if (uri == null) {
                throw new IOException("MediaStore insert failed");
            }
            try (OutputStream out = resolver.openOutputStream(uri)) {
                if (out == null) {
                    throw new IOException("Cannot open output stream");
                }
                out.write(data);
            }
            return Environment.DIRECTORY_DOWNLOADS + "/" + name;
        }
        File directory;
        if (context.checkSelfPermission(Manifest.permission.WRITE_EXTERNAL_STORAGE) == PackageManager.PERMISSION_GRANTED) {
            directory = Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_DOWNLOADS);
        } else {
            directory = context.getExternalFilesDir(Environment.DIRECTORY_DOWNLOADS);
        }
        if (directory == null || (!directory.exists() && !directory.mkdirs())) {
            throw new IOException("Downloads directory is not available");
        }
        File target = uniqueFile(directory, name);
        try (FileOutputStream out = new FileOutputStream(target)) {
            out.write(data);
        }
        return target.getAbsolutePath();
    }

    /** Decodes a data: URL (base64 or percent-encoded). */
    static byte[] decodeDataUrl(String dataUrl) {
        int comma = dataUrl.indexOf(',');
        if (!dataUrl.startsWith("data:") || comma < 0) {
            throw new IllegalArgumentException("Not a data URL");
        }
        String meta = dataUrl.substring(5, comma);
        String payload = dataUrl.substring(comma + 1);
        if (meta.endsWith(";base64")) {
            return Base64.decode(payload, Base64.DEFAULT);
        }
        return Uri.decode(payload).getBytes(StandardCharsets.UTF_8);
    }

    /** MIME type declared in a data: URL, or an empty string. */
    static String mimeOfDataUrl(String dataUrl) {
        int comma = dataUrl.indexOf(',');
        if (!dataUrl.startsWith("data:") || comma < 0) {
            return "";
        }
        String meta = dataUrl.substring(5, comma);
        int semicolon = meta.indexOf(';');
        return semicolon < 0 ? meta : meta.substring(0, semicolon);
    }

    static String sanitize(String fileName) {
        String name = fileName == null ? "" : fileName.replaceAll("[\\\\/:*?\"<>|\\p{Cntrl}]", "_").trim();
        if (name.isEmpty() || name.equals(".") || name.equals("..")) {
            name = "download";
        }
        return name.length() > 120 ? name.substring(0, 120) : name;
    }

    private static File uniqueFile(File directory, String name) {
        File file = new File(directory, name);
        int dot = name.lastIndexOf('.');
        String base = dot > 0 ? name.substring(0, dot) : name;
        String extension = dot > 0 ? name.substring(dot) : "";
        for (int i = 1; file.exists(); i++) {
            file = new File(directory, base + " (" + i + ")" + extension);
        }
        return file;
    }
}
