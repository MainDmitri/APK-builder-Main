package net.appbuilder.app

import android.app.DownloadManager
import android.content.Context
import android.net.Uri
import android.os.Environment
import java.io.File

/**
 * APK downloads through the system DownloadManager: they continue when the
 * app is in the background or closed, resume after network loss and show a
 * progress notification. Files land in the app-specific external directory
 * (no storage permission needed).
 */
object ApkDownloads {
    fun directory(context: Context): File =
        context.getExternalFilesDir(Environment.DIRECTORY_DOWNLOADS)
            ?: throw IllegalStateException("Внешнее хранилище недоступно")

    private fun manager(context: Context) = context.getSystemService(Context.DOWNLOAD_SERVICE) as DownloadManager

    /**
     * Starts a download into `<downloads>/<relativePath>`, or returns the id of
     * an unfinished download with the same [tag] (e.g. after the app restarted).
     */
    fun enqueue(
        context: Context,
        url: String,
        headers: Map<String, String>,
        relativePath: String,
        title: String,
        tag: String,
    ): Long {
        val dm = manager(context)
        findActive(dm, tag)?.let { return it }
        val target = File(directory(context), relativePath)
        target.parentFile?.mkdirs()
        if (target.exists()) target.delete()
        val request = DownloadManager.Request(Uri.parse(url))
            .setTitle(title)
            .setDescription(tag)
            .setMimeType("application/vnd.android.package-archive")
            .setNotificationVisibility(DownloadManager.Request.VISIBILITY_VISIBLE_NOTIFY_COMPLETED)
            .setDestinationInExternalFilesDir(context, Environment.DIRECTORY_DOWNLOADS, relativePath)
            .setAllowedOverMetered(true)
            .setAllowedOverRoaming(true)
        for ((name, value) in headers) request.addRequestHeader(name, value)
        return dm.enqueue(request)
    }

    private fun findActive(dm: DownloadManager, tag: String): Long? {
        val filter = DownloadManager.Query().setFilterByStatus(
            DownloadManager.STATUS_PENDING or DownloadManager.STATUS_RUNNING or DownloadManager.STATUS_PAUSED
        )
        dm.query(filter)?.use { c ->
            val idColumn = c.getColumnIndexOrThrow(DownloadManager.COLUMN_ID)
            val descriptionColumn = c.getColumnIndexOrThrow(DownloadManager.COLUMN_DESCRIPTION)
            while (c.moveToNext()) {
                if (c.getString(descriptionColumn) == tag) return c.getLong(idColumn)
            }
        }
        return null
    }

    fun query(context: Context, id: Long): Map<String, Any?> {
        manager(context).query(DownloadManager.Query().setFilterById(id))?.use { c ->
            if (!c.moveToFirst()) return mapOf("status" to "missing")
            val status = when (c.getInt(c.getColumnIndexOrThrow(DownloadManager.COLUMN_STATUS))) {
                DownloadManager.STATUS_PENDING -> "pending"
                DownloadManager.STATUS_RUNNING -> "running"
                DownloadManager.STATUS_PAUSED -> "paused"
                DownloadManager.STATUS_SUCCESSFUL -> "successful"
                else -> "failed"
            }
            return mapOf(
                "status" to status,
                "downloaded" to c.getLong(c.getColumnIndexOrThrow(DownloadManager.COLUMN_BYTES_DOWNLOADED_SO_FAR)),
                "total" to c.getLong(c.getColumnIndexOrThrow(DownloadManager.COLUMN_TOTAL_SIZE_BYTES)),
                "reason" to c.getInt(c.getColumnIndexOrThrow(DownloadManager.COLUMN_REASON)),
            )
        }
        return mapOf("status" to "missing")
    }

    fun cancel(context: Context, id: Long) {
        manager(context).remove(id)
    }
}
