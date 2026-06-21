package com.linkvault.app

import android.app.Activity
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.provider.OpenableColumns
import android.provider.Settings
import androidx.documentfile.provider.DocumentFile
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.BufferedOutputStream
import java.io.EOFException
import java.io.OutputStream
import java.net.HttpURLConnection
import java.net.URL
import java.util.Locale
import java.util.UUID
import kotlin.concurrent.thread

class MainActivity : FlutterActivity() {
    private var pendingFolderPickerResult: MethodChannel.Result? = null
    private var pendingUploadPickerResult: MethodChannel.Result? = null
    private val downloadSessions = mutableMapOf<String, OutputStream>()
    private val uploadConnections = mutableMapOf<String, HttpURLConnection>()
    private val transferPriorityLock = Object()
    @Volatile private var foregroundRequestActive = false
    private val mainHandler = Handler(Looper.getMainLooper())
    private var binaryMessenger: BinaryMessenger? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        binaryMessenger = flutterEngine.dartExecutor.binaryMessenger

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            DEVICE_INFO_CHANNEL,
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "currentDeviceName" -> result.success(currentDeviceName())
                else -> result.notImplemented()
            }
        }

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            DOWNLOADS_CHANNEL,
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "ensureDownloadPermissions" -> ensureDownloadPermissions(result)
                "pickDownloadFolder" -> pickDownloadFolder(result)
                "createFolder" -> createFolder(call, result)
                "downloadExists" -> downloadExists(call, result)
                "downloadSize" -> downloadSize(call, result)
                "openDownload" -> openDownload(call, result)
                "writeDownloadChunk" -> writeDownloadChunk(call, result)
                "closeDownload" -> closeDownload(call, result)
                "cancelDownload" -> cancelDownload(call, result)
                "deleteDownload" -> deleteDownload(call, result)
                "downloadFile" -> downloadFile(call, result)
                else -> result.notImplemented()
            }
        }

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            TRANSFER_PRIORITY_CHANNEL,
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "setForegroundRequestActive" -> setForegroundRequestActive(call, result)
                else -> result.notImplemented()
            }
        }

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            UPLOADS_CHANNEL,
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "pickUploadFiles" -> pickUploadFiles(result)
                "uploadFile" -> uploadFile(call, result)
                "cancelUpload" -> cancelUpload(call, result)
                else -> result.notImplemented()
            }
        }
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        when (requestCode) {
            DOWNLOAD_FOLDER_REQUEST -> handleDownloadFolderResult(resultCode, data)
            UPLOAD_FILES_REQUEST -> handleUploadFilesResult(resultCode, data)
        }
    }

    private fun handleDownloadFolderResult(resultCode: Int, data: Intent?) {
        val result = pendingFolderPickerResult ?: return
        pendingFolderPickerResult = null
        if (resultCode != Activity.RESULT_OK) {
            result.success(null)
            return
        }

        val uri = data?.data
        if (uri == null) {
            result.success(null)
            return
        }

        val flags = data.flags and (
            Intent.FLAG_GRANT_READ_URI_PERMISSION or
                Intent.FLAG_GRANT_WRITE_URI_PERMISSION
            )
        try {
            contentResolver.takePersistableUriPermission(uri, flags)
        } catch (_: SecurityException) {
            // Some providers do not grant persistable access. The returned URI
            // can still be used while the app keeps the transient grant.
        }
        result.success(uri.toString())
    }

    private fun handleUploadFilesResult(resultCode: Int, data: Intent?) {
        val result = pendingUploadPickerResult ?: return
        pendingUploadPickerResult = null
        if (resultCode != Activity.RESULT_OK) {
            result.success(emptyList<Map<String, Any?>>())
            return
        }

        val selectedFiles = mutableListOf<Map<String, Any?>>()
        val grantFlags = data?.flags ?: 0
        val clipData = data?.clipData
        if (clipData != null) {
            for (index in 0 until clipData.itemCount) {
                val uri = clipData.getItemAt(index).uri
                persistUploadReadPermission(uri, grantFlags)
                selectedFiles.add(uploadFileInfo(uri))
            }
        } else {
            data?.data?.let { uri ->
                persistUploadReadPermission(uri, grantFlags)
                selectedFiles.add(uploadFileInfo(uri))
            }
        }
        result.success(selectedFiles)
    }

    private fun currentDeviceName(): String {
        return globalSetting(Settings.Global.DEVICE_NAME)
            ?: secureSetting("bluetooth_name")
            ?: formattedAndroidModel()
    }

    private fun globalSetting(key: String): String? {
        return try {
            Settings.Global.getString(contentResolver, key).normalizedOrNull()
        } catch (_: RuntimeException) {
            null
        }
    }

    private fun secureSetting(key: String): String? {
        return try {
            Settings.Secure.getString(contentResolver, key).normalizedOrNull()
        } catch (_: RuntimeException) {
            null
        }
    }

    private fun formattedAndroidModel(): String {
        val manufacturer = Build.MANUFACTURER.normalizedOrNull().orEmpty()
        val model = Build.MODEL.normalizedOrNull().orEmpty()
        if (model.isEmpty()) {
            return manufacturer.ifEmpty { "Android Device" }
        }
        if (manufacturer.isEmpty() || model.startsWith(manufacturer, ignoreCase = true)) {
            return model
        }
        return "${manufacturer.capitalized()} $model"
    }

    private fun String?.normalizedOrNull(): String? {
        val normalized = this?.trim()
        return normalized?.takeIf { it.isNotEmpty() }
    }

    private fun String.capitalized(): String {
        return replaceFirstChar { char ->
            if (char.isLowerCase()) char.titlecase(Locale.ROOT) else char.toString()
        }
    }

    private fun String?.safeLogValue(): String? {
        return this
            ?.replace('\n', ' ')
            ?.replace('\r', ' ')
            ?.trim()
            ?.takeIf { it.isNotEmpty() }
    }

    private fun ensureDownloadPermissions(result: MethodChannel.Result) {
        result.success(true)
    }

    private fun pickUploadFiles(result: MethodChannel.Result) {
        if (pendingUploadPickerResult != null) {
            result.error("picker_active", "An upload picker is already active", null)
            return
        }
        pendingUploadPickerResult = result
        val intent = Intent(Intent.ACTION_OPEN_DOCUMENT).apply {
            addCategory(Intent.CATEGORY_OPENABLE)
            type = "*/*"
            putExtra(Intent.EXTRA_ALLOW_MULTIPLE, true)
            addFlags(
                Intent.FLAG_GRANT_READ_URI_PERMISSION or
                    Intent.FLAG_GRANT_PERSISTABLE_URI_PERMISSION
            )
        }
        startActivityForResult(intent, UPLOAD_FILES_REQUEST)
    }

    private fun persistUploadReadPermission(uri: Uri, flags: Int) {
        val readFlags = flags and Intent.FLAG_GRANT_READ_URI_PERMISSION
        if (readFlags == 0) {
            return
        }
        try {
            contentResolver.takePersistableUriPermission(uri, readFlags)
        } catch (_: SecurityException) {
            // Some providers only grant transient read access.
        }
    }

    private fun uploadFileInfo(uri: Uri): Map<String, Any?> {
        val metadata = queryUploadMetadata(uri)
        return mapOf(
            "contentUri" to uri.toString(),
            "name" to metadata.name,
            "sizeBytes" to metadata.sizeBytes,
        )
    }

    private fun queryUploadMetadata(uri: Uri): UploadMetadata {
        var name: String? = null
        var sizeBytes: Long = -1L
        contentResolver.query(
            uri,
            arrayOf(OpenableColumns.DISPLAY_NAME, OpenableColumns.SIZE),
            null,
            null,
            null,
        )?.use { cursor ->
            if (cursor.moveToFirst()) {
                val nameIndex = cursor.getColumnIndex(OpenableColumns.DISPLAY_NAME)
                if (nameIndex >= 0 && !cursor.isNull(nameIndex)) {
                    name = cursor.getString(nameIndex)
                }
                val sizeIndex = cursor.getColumnIndex(OpenableColumns.SIZE)
                if (sizeIndex >= 0 && !cursor.isNull(sizeIndex)) {
                    sizeBytes = cursor.getLong(sizeIndex)
                }
            }
        }
        return UploadMetadata(
            name = name.safeLogValue() ?: "upload.bin",
            sizeBytes = sizeBytes.coerceAtLeast(0L),
        )
    }

    private fun uploadFile(call: MethodCall, result: MethodChannel.Result) {
        val contentUri = call.argument<String>("contentUri")
        val url = call.argument<String>("url")
        val headers = call.argument<Map<*, *>>("headers").toStringMap()
        val fileName = call.argument<String>("fileName").safeLogValue() ?: "upload.bin"
        val uploadSessionId = call.argument<String>("uploadSessionId") ?: UUID.randomUUID().toString()
        val offset = (call.argument<Any>("offset") as? Number)?.toLong() ?: 0L
        val progressChannelName = call.argument<String>("progressChannel")
        if (contentUri == null || url == null) {
            result.error("upload_failed", "contentUri and url are required", null)
            return
        }

        thread(name = "linkvault-upload") {
            try {
                val progressChannel = progressChannelName?.let { channelName ->
                    binaryMessenger?.let { messenger -> MethodChannel(messenger, channelName) }
                }
                val response = uploadRawBody(
                    Uri.parse(contentUri),
                    URL(url),
                    headers,
                    fileName,
                    uploadSessionId,
                    offset,
                    progressChannel,
                )
                mainHandler.post {
                    result.success(
                        mapOf(
                            "statusCode" to response.statusCode,
                            "body" to response.body,
                            "uploadedBytes" to response.uploadedBytes,
                        )
                    )
                }
            } catch (error: Exception) {
                mainHandler.post {
                    result.error("upload_failed", error.message, null)
                }
            }
        }
    }

    private fun uploadRawBody(
        contentUri: Uri,
        url: URL,
        headers: Map<String, String>,
        fileName: String,
        uploadSessionId: String,
        offset: Long,
        progressChannel: MethodChannel?,
    ): UploadResponse {
        val connection = (url.openConnection() as HttpURLConnection).apply {
            requestMethod = "POST"
            doOutput = true
            connectTimeout = 30_000
            readTimeout = 30 * 60_000
            setRequestProperty("Content-Type", "application/octet-stream")
            headers.forEach { (key, value) ->
                if (!key.equals("content-type", ignoreCase = true)) {
                    setRequestProperty(key, value)
                }
            }
            setChunkedStreamingMode(64 * 1024)
        }

        try {
            synchronized(uploadConnections) {
                uploadConnections[uploadSessionId] = connection
            }
            var uploadedBytes = 0L
            BufferedOutputStream(connection.outputStream).use { output ->
                contentResolver.openInputStream(contentUri).use { input ->
                    if (input == null) {
                        throw IllegalStateException("Cannot open upload input stream")
                    }
                    skipFully(input, offset)
                    val buffer = ByteArray(64 * 1024)
                    while (true) {
                        waitForForegroundRequests()
                        val read = input.read(buffer)
                        if (read < 0) {
                            break
                        }
                        output.write(buffer, 0, read)
                        uploadedBytes += read.toLong()
                        progressChannel?.notifyUploadProgress(uploadedBytes)
                    }
                }
            }
            val statusCode = connection.responseCode
            val responseStream = if (statusCode >= 400) connection.errorStream else connection.inputStream
            val body = responseStream?.bufferedReader(Charsets.UTF_8)?.use { it.readText() }.orEmpty()
            return UploadResponse(statusCode, body, uploadedBytes)
        } finally {
            synchronized(uploadConnections) {
                uploadConnections.remove(uploadSessionId)
            }
            connection.disconnect()
        }
    }

    private fun setForegroundRequestActive(call: MethodCall, result: MethodChannel.Result) {
        val active = call.argument<Boolean>("active") ?: false
        synchronized(transferPriorityLock) {
            foregroundRequestActive = active
            if (!active) {
                transferPriorityLock.notifyAll()
            }
        }
        result.success(null)
    }

    private fun waitForForegroundRequests() {
        synchronized(transferPriorityLock) {
            val deadline = System.currentTimeMillis() + TRANSFER_PRIORITY_MAX_WAIT_MS
            while (foregroundRequestActive) {
                val remaining = deadline - System.currentTimeMillis()
                if (remaining <= 0L) {
                    foregroundRequestActive = false
                    transferPriorityLock.notifyAll()
                    return
                }
                transferPriorityLock.wait(remaining.coerceAtMost(250L))
            }
        }
    }

    private fun cancelUpload(call: MethodCall, result: MethodChannel.Result) {
        try {
            val uploadSessionId = call.argument<String>("uploadSessionId")
                ?: throw IllegalArgumentException("uploadSessionId is required")
            synchronized(uploadConnections) {
                uploadConnections.remove(uploadSessionId)
            }?.disconnect()
            result.success(null)
        } catch (error: Exception) {
            result.error("cancel_upload_failed", error.message, null)
        }
    }

    private fun skipFully(input: java.io.InputStream, bytes: Long) {
        var remaining = bytes.coerceAtLeast(0L)
        while (remaining > 0) {
            val skipped = input.skip(remaining)
            if (skipped <= 0L) {
                if (input.read() < 0) {
                    return
                }
                remaining -= 1L
            } else {
                remaining -= skipped
            }
        }
    }

    private fun MethodChannel.notifyUploadProgress(uploadedBytes: Long) {
        mainHandler.post {
            invokeMethod("uploadProgress", uploadedBytes)
        }
    }

    private fun MethodChannel.notifyDownloadProgress(downloadedBytes: Long) {
        mainHandler.post {
            invokeMethod("downloadProgress", downloadedBytes)
        }
    }

    private fun pickDownloadFolder(result: MethodChannel.Result) {
        if (pendingFolderPickerResult != null) {
            result.error("picker_active", "A folder picker is already active", null)
            return
        }
        pendingFolderPickerResult = result
        val intent = Intent(Intent.ACTION_OPEN_DOCUMENT_TREE).apply {
            addFlags(
                Intent.FLAG_GRANT_READ_URI_PERMISSION or
                    Intent.FLAG_GRANT_WRITE_URI_PERMISSION or
                    Intent.FLAG_GRANT_PERSISTABLE_URI_PERMISSION
            )
        }
        startActivityForResult(intent, DOWNLOAD_FOLDER_REQUEST)
    }

    private fun createFolder(call: MethodCall, result: MethodChannel.Result) {
        try {
            val treeUri = call.argument<String>("treeUri")
                ?: throw IllegalArgumentException("treeUri is required")
            val relativePath = call.argument<String>("relativePath")
                ?: throw IllegalArgumentException("relativePath is required")
            directoryForPath(treeUri, relativePath)
            result.success(null)
        } catch (error: Exception) {
            result.error("create_folder_failed", error.message, null)
        }
    }

    private fun downloadExists(call: MethodCall, result: MethodChannel.Result) {
        try {
            val treeUri = call.argument<String>("treeUri")
                ?: throw IllegalArgumentException("treeUri is required")
            val relativePath = call.argument<String>("relativePath")
                ?: throw IllegalArgumentException("relativePath is required")
            result.success(findDocumentForPath(treeUri, relativePath) != null)
        } catch (error: Exception) {
            result.error("exists_failed", error.message, null)
        }
    }

    private fun downloadSize(call: MethodCall, result: MethodChannel.Result) {
        try {
            val treeUri = call.argument<String>("treeUri")
                ?: throw IllegalArgumentException("treeUri is required")
            val relativePath = call.argument<String>("relativePath")
                ?: throw IllegalArgumentException("relativePath is required")
            val document = findDocumentForPath(treeUri, relativePath)
            result.success(document?.length() ?: 0L)
        } catch (error: Exception) {
            result.error("size_failed", error.message, null)
        }
    }

    private fun openDownload(call: MethodCall, result: MethodChannel.Result) {
        try {
            val treeUri = call.argument<String>("treeUri")
                ?: throw IllegalArgumentException("treeUri is required")
            val relativePath = call.argument<String>("relativePath")
                ?: throw IllegalArgumentException("relativePath is required")
            val append = call.argument<Boolean>("append") ?: false
            val document = writableFileForPath(treeUri, relativePath)
            val outputStream = contentResolver.openOutputStream(document.uri, if (append) "wa" else "w")
                ?: throw IllegalStateException("Cannot open output stream")
            val sessionId = UUID.randomUUID().toString()
            downloadSessions[sessionId] = outputStream
            result.success(sessionId)
        } catch (error: Exception) {
            result.error("open_failed", error.message, null)
        }
    }

    private fun writeDownloadChunk(call: MethodCall, result: MethodChannel.Result) {
        try {
            val sessionId = call.argument<String>("sessionId")
                ?: throw IllegalArgumentException("sessionId is required")
            val bytes = call.argument<ByteArray>("bytes")
                ?: throw IllegalArgumentException("bytes is required")
            val outputStream = downloadSessions[sessionId]
                ?: throw IllegalArgumentException("Unknown download session")
            outputStream.write(bytes)
            result.success(null)
        } catch (error: Exception) {
            result.error("write_failed", error.message, null)
        }
    }

    private fun closeDownload(call: MethodCall, result: MethodChannel.Result) {
        try {
            val sessionId = call.argument<String>("sessionId")
                ?: throw IllegalArgumentException("sessionId is required")
            downloadSessions.remove(sessionId)?.close()
            result.success(null)
        } catch (error: Exception) {
            result.error("close_failed", error.message, null)
        }
    }

    private fun cancelDownload(call: MethodCall, result: MethodChannel.Result) {
        try {
            val sessionId = call.argument<String>("sessionId")
                ?: throw IllegalArgumentException("sessionId is required")
            downloadSessions.remove(sessionId)?.close()
            result.success(null)
        } catch (error: Exception) {
            result.error("cancel_failed", error.message, null)
        }
    }

    private fun deleteDownload(call: MethodCall, result: MethodChannel.Result) {
        try {
            val treeUri = call.argument<String>("treeUri")
                ?: throw IllegalArgumentException("treeUri is required")
            val relativePath = call.argument<String>("relativePath")
                ?: throw IllegalArgumentException("relativePath is required")
            findDocumentForPath(treeUri, relativePath)?.delete()
            result.success(null)
        } catch (error: Exception) {
            result.error("delete_failed", error.message, null)
        }
    }

    private fun downloadFile(call: MethodCall, result: MethodChannel.Result) {
        val treeUri = call.argument<String>("treeUri")
        val relativePath = call.argument<String>("relativePath")
        val url = call.argument<String>("url")
        val headers = call.argument<Map<*, *>>("headers").toStringMap()
        val offset = (call.argument<Any>("offset") as? Number)?.toLong() ?: 0L
        val offsetAlreadyApplied = call.argument<Boolean>("offsetAlreadyApplied") ?: false
        val progressChannelName = call.argument<String>("progressChannel")
        val totalBytes = (call.argument<Any>("totalBytes") as? Number)?.toLong()
        if (treeUri == null || relativePath == null || url == null) {
            result.error("download_failed", "treeUri, relativePath and url are required", null)
            return
        }

        thread(name = "linkvault-download") {
            try {
                val progressChannel = progressChannelName?.let { channelName ->
                    binaryMessenger?.let { messenger -> MethodChannel(messenger, channelName) }
                }
                val document = writableFileForPath(treeUri, relativePath)
                val outputStream = contentResolver.openOutputStream(document.uri, if (offset > 0L) "wa" else "w")
                    ?: throw IllegalStateException("Cannot open output stream")
                val downloadedBytes = downloadUrlToStream(
                    URL(url),
                    headers,
                    outputStream,
                    totalBytes,
                    progressChannel,
                    offset,
                    offsetAlreadyApplied,
                )
                mainHandler.post {
                    result.success(downloadedBytes)
                }
            } catch (error: Exception) {
                mainHandler.post {
                    result.error(
                        "download_failed",
                        error.localizedMessage ?: error.message ?: error::class.java.name,
                        null
                    )
                }
            }
        }
    }

    private fun downloadUrlToStream(
        url: URL,
        headers: Map<String, String>,
        outputStream: OutputStream,
        totalBytes: Long?,
        progressChannel: MethodChannel?,
        offset: Long = 0L,
        offsetAlreadyApplied: Boolean = false,
    ): Long {
        val connection = (url.openConnection() as HttpURLConnection).apply {
            requestMethod = "GET"
            connectTimeout = 30_000
            readTimeout = 30 * 60_000
            headers.forEach { (key, value) -> setRequestProperty(key, value) }
            if (offset > 0L && !offsetAlreadyApplied && headers.keys.none { it.equals("range", ignoreCase = true) }) {
                setRequestProperty("Range", "bytes=$offset-")
            }
        }
        try {
            val statusCode = connection.responseCode
            if (statusCode < 200 || statusCode >= 300) {
                val body = connection.errorStream?.bufferedReader(Charsets.UTF_8)?.use { it.readText() }.orEmpty()
                throw IllegalStateException("Download failed with HTTP $statusCode $body")
            }
            if (offset > 0L && !offsetAlreadyApplied && statusCode != 206) {
                throw IllegalStateException("Download server did not accept resume offset")
            }
            var downloadedBytes = 0L
            val expectedBytes = totalBytes
                ?.let { (it - offset).coerceAtLeast(0L) }
                ?: connection.contentLengthLong.takeIf { it >= 0L }
            outputStream.use { output ->
                try {
                    connection.inputStream.use { input ->
                        val buffer = ByteArray(64 * 1024)
                        while (true) {
                            waitForForegroundRequests()
                            val read = input.read(buffer)
                            if (read < 0) {
                                break
                            }
                            output.write(buffer, 0, read)
                            downloadedBytes += read.toLong()
                            progressChannel?.notifyDownloadProgress(downloadedBytes)
                        }
                        output.flush()
                    }
                } catch (error: EOFException) {
                    if (expectedBytes == null || downloadedBytes < expectedBytes) {
                        throw error
                    }
                    output.flush()
                }
            }
            return downloadedBytes
        } finally {
            connection.disconnect()
        }
    }

    private fun directoryForPath(treeUri: String, relativePath: String): DocumentFile {
        val root = DocumentFile.fromTreeUri(this, Uri.parse(treeUri))
            ?: throw IllegalArgumentException("Invalid download folder")
        val parts = relativePath.split('/', '\\').filter { it.isNotBlank() }
        if (parts.isEmpty()) {
            return root
        }

        var current = root
        for (part in parts) {
            current = current.findFile(part)?.takeIf { it.isDirectory }
                ?: current.createDirectory(part)
                ?: throw IllegalStateException("Cannot create folder: $part")
        }
        return current
    }

    private fun writableFileForPath(treeUri: String, relativePath: String): DocumentFile {
        val root = DocumentFile.fromTreeUri(this, Uri.parse(treeUri))
            ?: throw IllegalArgumentException("Invalid download folder")
        val parts = relativePath.split('/', '\\').filter { it.isNotBlank() }
        if (parts.isEmpty()) {
            throw IllegalArgumentException("relativePath is empty")
        }

        var current = root
        for (part in parts.dropLast(1)) {
            current = current.findFile(part)?.takeIf { it.isDirectory }
                ?: current.createDirectory(part)
                ?: throw IllegalStateException("Cannot create folder: $part")
        }

        val fileName = parts.last()
        val existing = current.findFile(fileName)
        if (existing != null) {
            if (!existing.isFile) {
                throw IllegalStateException("Target exists and is not a file: $fileName")
            }
            return existing
        }
        return current.createFile(mimeTypeFor(fileName), fileName)
            ?: throw IllegalStateException("Cannot create file: $fileName")
    }

    private fun findDocumentForPath(treeUri: String, relativePath: String): DocumentFile? {
        var current = DocumentFile.fromTreeUri(this, Uri.parse(treeUri)) ?: return null
        val parts = relativePath.split('/', '\\').filter { it.isNotBlank() }
        for (part in parts) {
            current = current.findFile(part) ?: return null
        }
        return current
    }

    private fun mimeTypeFor(fileName: String): String {
        val extension = fileName.substringAfterLast('.', missingDelimiterValue = "")
            .lowercase(Locale.ROOT)
        return when (extension) {
            "jpg", "jpeg" -> "image/jpeg"
            "png" -> "image/png"
            "gif" -> "image/gif"
            "webp" -> "image/webp"
            "pdf" -> "application/pdf"
            "txt" -> "text/plain"
            "json" -> "application/json"
            "zip" -> "application/zip"
            else -> "application/octet-stream"
        }
    }

    private companion object {
        const val DEVICE_INFO_CHANNEL = "com.linkvault.app/device_info"
        const val DOWNLOADS_CHANNEL = "com.linkvault.app/downloads"
        const val UPLOADS_CHANNEL = "com.linkvault.app/uploads"
        const val TRANSFER_PRIORITY_CHANNEL = "com.linkvault.app/transfer_priority"
        const val TRANSFER_PRIORITY_MAX_WAIT_MS = 30_000L
        const val DOWNLOAD_FOLDER_REQUEST = 4217
        const val UPLOAD_FILES_REQUEST = 4219
    }

    private data class UploadMetadata(val name: String, val sizeBytes: Long)

    private data class UploadResponse(val statusCode: Int, val body: String, val uploadedBytes: Long)
}

private fun Map<*, *>?.toStringMap(): Map<String, String> {
    if (this == null) {
        return emptyMap()
    }
    return entries.associate { (key, value) -> key.toString() to value.toString() }
}
