package com.bobo.learning.bobo_learning

import android.app.DownloadManager
import android.content.Context
import android.content.Intent
import android.content.pm.PackageInfo
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.os.Environment
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileInputStream
import java.security.MessageDigest
import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors

class MainActivity : FlutterActivity() {
    private val worker: ExecutorService = Executors.newSingleThreadExecutor()

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            UPDATE_CHANNEL,
        ).setMethodCallHandler(::handleUpdateMethod)
    }

    override fun onResume() {
        super.onResume()
        val preferences = updatePreferences()
        if (!preferences.getBoolean(KEY_INSTALL_AFTER_PERMISSION, false)) {
            return
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O &&
            !packageManager.canRequestPackageInstalls()
        ) {
            return
        }

        preferences.edit().putBoolean(KEY_INSTALL_AFTER_PERMISSION, false).apply()
        worker.execute {
            runCatching {
                val snapshot = queryDownloadStatus()
                if (snapshot["status"] == STATUS_READY) {
                    runOnUiThread { openSystemInstaller() }
                }
            }
        }
    }

    override fun onDestroy() {
        worker.shutdownNow()
        super.onDestroy()
    }

    private fun handleUpdateMethod(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "getPlatformInfo" -> result.success(currentPlatformInfo())
            "startDownload" -> startDownload(call, result)
            "getDownloadStatus" -> runInWorker(result, ::queryDownloadStatus)
            "installDownloadedUpdate" -> prepareInstallation(result)
            else -> result.notImplemented()
        }
    }

    private fun currentPlatformInfo(): Map<String, Any> {
        val info = currentPackageInfo()
        return mapOf(
            "supported" to true,
            "versionName" to (info.versionName ?: ""),
            "versionCode" to packageVersionCode(info),
        )
    }

    private fun startDownload(call: MethodCall, result: MethodChannel.Result) {
        runCatching {
            val url = requiredStringArgument(call, "url")
            val fileName = requiredStringArgument(call, "fileName")
            val sha256 = requiredStringArgument(call, "sha256")
            val versionCode = requiredLongArgument(call, "versionCode")
            val sizeBytes = requiredLongArgument(call, "sizeBytes")
            validateDownloadArguments(url, fileName, sha256, versionCode, sizeBytes)

            val preferences = updatePreferences()
            val manager = downloadManager()
            val previousId = preferences.getLong(KEY_DOWNLOAD_ID, NO_DOWNLOAD_ID)
            if (previousId != NO_DOWNLOAD_ID) {
                manager.remove(previousId)
            }

            val destination = updateFile(fileName)
            if (destination.exists() && !destination.delete()) {
                error("无法清理旧升级包")
            }
            val request = DownloadManager.Request(Uri.parse(url))
                .setTitle("菠萝乐园正在准备更新")
                .setDescription("下载完成后会提示安装")
                .setMimeType(APK_MIME_TYPE)
                .setAllowedOverMetered(true)
                .setAllowedOverRoaming(false)
                .setNotificationVisibility(DownloadManager.Request.VISIBILITY_VISIBLE)
                .setDestinationInExternalFilesDir(
                    this,
                    Environment.DIRECTORY_DOWNLOADS,
                    fileName,
                )
            val downloadId = manager.enqueue(request)
            val saved = preferences.edit()
                .putLong(KEY_DOWNLOAD_ID, downloadId)
                .putLong(KEY_VERSION_CODE, versionCode)
                .putLong(KEY_SIZE_BYTES, sizeBytes)
                .putString(KEY_FILE_NAME, fileName)
                .putString(KEY_SHA256, sha256)
                .putBoolean(KEY_VERIFIED, false)
                .putBoolean(KEY_INSTALL_AFTER_PERMISSION, false)
                .commit()
            check(saved) { "无法保存升级任务状态" }
        }.onSuccess {
            result.success(null)
        }.onFailure { error ->
            result.error("update_download_failed", error.message ?: "无法开始下载升级包", null)
        }
    }

    private fun queryDownloadStatus(): Map<String, Any?> {
        val preferences = updatePreferences()
        val downloadId = preferences.getLong(KEY_DOWNLOAD_ID, NO_DOWNLOAD_ID)
        val versionCode = preferences.getLong(KEY_VERSION_CODE, 0)
        if (downloadId == NO_DOWNLOAD_ID || versionCode <= 0) {
            return downloadStatus(STATUS_NOT_FOUND)
        }

        val query = DownloadManager.Query().setFilterById(downloadId)
        downloadManager().query(query)?.use { cursor ->
            if (!cursor.moveToFirst()) {
                clearDownloadState(removeDownload = false)
                return downloadStatus(STATUS_NOT_FOUND)
            }
            val systemStatus = cursor.getInt(cursor.getColumnIndexOrThrow(DownloadManager.COLUMN_STATUS))
            val downloadedBytes = cursor.getLong(
                cursor.getColumnIndexOrThrow(DownloadManager.COLUMN_BYTES_DOWNLOADED_SO_FAR),
            )
            val totalBytes = cursor.getLong(
                cursor.getColumnIndexOrThrow(DownloadManager.COLUMN_TOTAL_SIZE_BYTES),
            )
            return when (systemStatus) {
                DownloadManager.STATUS_PENDING -> downloadStatus(
                    STATUS_PENDING,
                    versionCode,
                    downloadedBytes,
                    totalBytes,
                )
                DownloadManager.STATUS_RUNNING -> downloadStatus(
                    STATUS_DOWNLOADING,
                    versionCode,
                    downloadedBytes,
                    totalBytes,
                )
                DownloadManager.STATUS_PAUSED -> downloadStatus(
                    STATUS_PAUSED,
                    versionCode,
                    downloadedBytes,
                    totalBytes,
                )
                DownloadManager.STATUS_SUCCESSFUL -> verifySuccessfulDownload(
                    versionCode,
                    downloadedBytes,
                    totalBytes,
                )
                DownloadManager.STATUS_FAILED -> {
                    val reason = cursor.getInt(
                        cursor.getColumnIndexOrThrow(DownloadManager.COLUMN_REASON),
                    )
                    clearDownloadState(removeDownload = true)
                    downloadStatus(
                        STATUS_FAILED,
                        versionCode,
                        downloadedBytes,
                        totalBytes,
                        "升级包下载失败（系统代码 $reason），稍后会自动重试",
                    )
                }
                else -> downloadStatus(STATUS_NOT_FOUND)
            }
        }
        clearDownloadState(removeDownload = false)
        return downloadStatus(STATUS_NOT_FOUND)
    }

    private fun verifySuccessfulDownload(
        versionCode: Long,
        downloadedBytes: Long,
        totalBytes: Long,
    ): Map<String, Any?> {
        val preferences = updatePreferences()
        if (preferences.getBoolean(KEY_VERIFIED, false)) {
            return downloadStatus(STATUS_READY, versionCode, downloadedBytes, totalBytes)
        }

        return runCatching {
            val fileName = preferences.getString(KEY_FILE_NAME, null) ?: error("升级包文件名已丢失")
            val expectedSha256 = preferences.getString(KEY_SHA256, null) ?: error("升级包校验值已丢失")
            val expectedSize = preferences.getLong(KEY_SIZE_BYTES, 0)
            val file = updateFile(fileName)
            validateDownloadedPackage(file, expectedSha256, expectedSize, versionCode)
            check(preferences.edit().putBoolean(KEY_VERIFIED, true).commit()) {
                "无法保存升级包校验状态"
            }
            downloadStatus(STATUS_READY, versionCode, downloadedBytes, totalBytes)
        }.getOrElse { error ->
            clearDownloadState(removeDownload = true)
            downloadStatus(
                STATUS_FAILED,
                versionCode,
                downloadedBytes,
                totalBytes,
                error.message ?: "升级包安全校验失败",
            )
        }
    }

    private fun validateDownloadedPackage(
        file: File,
        expectedSha256: String,
        expectedSize: Long,
        expectedVersionCode: Long,
    ) {
        check(file.isFile) { "升级包文件不存在" }
        check(file.length() == expectedSize) { "升级包长度与发布清单不一致" }
        check(fileSha256(file) == expectedSha256) { "升级包 SHA-256 校验失败" }

        val flags = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            PackageManager.GET_SIGNING_CERTIFICATES
        } else {
            @Suppress("DEPRECATION")
            PackageManager.GET_SIGNATURES
        }
        @Suppress("DEPRECATION")
        val archiveInfo = packageManager.getPackageArchiveInfo(file.absolutePath, flags)
            ?: error("无法读取升级包信息")
        check(archiveInfo.packageName == packageName) { "升级包应用标识不匹配" }
        check(packageVersionCode(archiveInfo) == expectedVersionCode) { "升级包版本号不匹配" }
        check(expectedVersionCode > packageVersionCode(currentPackageInfo(flags))) {
            "升级包版本不高于当前版本"
        }
        check(signingDigests(archiveInfo) == signingDigests(currentPackageInfo(flags))) {
            "升级包签名与当前应用不一致"
        }
    }

    private fun prepareInstallation(result: MethodChannel.Result) {
        runInWorker(result) {
            val snapshot = queryDownloadStatus()
            check(snapshot["status"] == STATUS_READY) { "升级包尚未下载或未通过安全校验" }
            val needsPermission = Build.VERSION.SDK_INT >= Build.VERSION_CODES.O &&
                !packageManager.canRequestPackageInstalls()
            runOnUiThread {
                if (needsPermission) {
                    updatePreferences().edit()
                        .putBoolean(KEY_INSTALL_AFTER_PERMISSION, true)
                        .apply()
                    val settingsIntent = Intent(
                        Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES,
                        Uri.parse("package:$packageName"),
                    )
                    startActivity(settingsIntent)
                } else {
                    openSystemInstaller()
                }
            }
            if (needsPermission) "permissionRequired" else "opened"
        }
    }

    private fun openSystemInstaller() {
        val downloadId = updatePreferences().getLong(KEY_DOWNLOAD_ID, NO_DOWNLOAD_ID)
        check(downloadId != NO_DOWNLOAD_ID) { "没有可安装的升级任务" }
        val contentUri = downloadManager().getUriForDownloadedFile(downloadId)
            ?: error("无法获取升级包安装地址")
        val intent = Intent(Intent.ACTION_VIEW)
            .setDataAndType(contentUri, APK_MIME_TYPE)
            .addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
            .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        startActivity(intent)
    }

    private fun validateDownloadArguments(
        url: String,
        fileName: String,
        sha256: String,
        versionCode: Long,
        sizeBytes: Long,
    ) {
        val uri = Uri.parse(url)
        check(uri.scheme == "http" || uri.scheme == "https") { "升级地址必须使用 HTTP 或 HTTPS" }
        check(!uri.host.isNullOrBlank()) { "升级地址缺少主机" }
        check(SAFE_APK_FILE_NAME.matches(fileName)) { "升级包文件名不安全" }
        check(SHA256.matches(sha256)) { "升级包校验值格式不正确" }
        check(versionCode > packageVersionCode(currentPackageInfo())) { "目标版本必须高于当前版本" }
        check(sizeBytes > 0) { "升级包长度必须大于 0" }
    }

    private fun signingDigests(info: PackageInfo): Set<String> {
        val signatures = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            info.signingInfo?.apkContentsSigners ?: emptyArray()
        } else {
            @Suppress("DEPRECATION")
            info.signatures ?: emptyArray()
        }
        return signatures.map { signature ->
            MessageDigest.getInstance("SHA-256")
                .digest(signature.toByteArray())
                .joinToString("") { byte -> "%02x".format(byte.toInt() and 0xff) }
        }.toSet()
    }

    private fun fileSha256(file: File): String {
        val digest = MessageDigest.getInstance("SHA-256")
        FileInputStream(file).use { input ->
            val buffer = ByteArray(DEFAULT_BUFFER_SIZE)
            while (true) {
                val count = input.read(buffer)
                if (count < 0) break
                digest.update(buffer, 0, count)
            }
        }
        return digest.digest().joinToString("") { byte ->
            "%02x".format(byte.toInt() and 0xff)
        }
    }

    private fun updateFile(fileName: String): File {
        val directory = getExternalFilesDir(Environment.DIRECTORY_DOWNLOADS)
            ?: error("无法使用应用升级目录")
        check(directory.exists() || directory.mkdirs()) { "无法创建应用升级目录" }
        return File(directory, fileName)
    }

    private fun clearDownloadState(removeDownload: Boolean) {
        val preferences = updatePreferences()
        val downloadId = preferences.getLong(KEY_DOWNLOAD_ID, NO_DOWNLOAD_ID)
        val fileName = preferences.getString(KEY_FILE_NAME, null)
        if (removeDownload && downloadId != NO_DOWNLOAD_ID) {
            downloadManager().remove(downloadId)
        }
        if (removeDownload && fileName != null) {
            runCatching { updateFile(fileName).delete() }
        }
        preferences.edit().clear().apply()
    }

    private fun downloadStatus(
        status: String,
        versionCode: Long? = null,
        downloadedBytes: Long = 0,
        totalBytes: Long = 0,
        message: String? = null,
    ): Map<String, Any?> = mapOf(
        "status" to status,
        "versionCode" to versionCode,
        "downloadedBytes" to downloadedBytes,
        "totalBytes" to totalBytes,
        "message" to message,
    )

    private fun requiredStringArgument(call: MethodCall, name: String): String =
        call.argument<String>(name)?.takeIf { it.isNotBlank() }
            ?: error("缺少参数：$name")

    private fun requiredLongArgument(call: MethodCall, name: String): Long =
        (call.argument<Number>(name)?.toLong()) ?: error("缺少参数：$name")

    private fun runInWorker(
        result: MethodChannel.Result,
        action: () -> Any?,
    ) {
        worker.execute {
            runCatching(action).onSuccess { value ->
                runOnUiThread { result.success(value) }
            }.onFailure { error ->
                runOnUiThread {
                    result.error(
                        "update_operation_failed",
                        error.message ?: "升级操作失败",
                        null,
                    )
                }
            }
        }
    }

    @Suppress("DEPRECATION")
    private fun currentPackageInfo(flags: Int = 0): PackageInfo =
        packageManager.getPackageInfo(packageName, flags)

    @Suppress("DEPRECATION")
    private fun packageVersionCode(info: PackageInfo): Long =
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            info.longVersionCode
        } else {
            info.versionCode.toLong()
        }

    private fun downloadManager(): DownloadManager =
        getSystemService(Context.DOWNLOAD_SERVICE) as DownloadManager

    private fun updatePreferences() = getSharedPreferences(PREFERENCES_NAME, Context.MODE_PRIVATE)

    companion object {
        private const val UPDATE_CHANNEL = "bobo_learning/app_update"
        private const val PREFERENCES_NAME = "bobo_learning_update"
        private const val APK_MIME_TYPE = "application/vnd.android.package-archive"
        private const val NO_DOWNLOAD_ID = -1L
        private const val KEY_DOWNLOAD_ID = "download_id"
        private const val KEY_VERSION_CODE = "version_code"
        private const val KEY_SIZE_BYTES = "size_bytes"
        private const val KEY_FILE_NAME = "file_name"
        private const val KEY_SHA256 = "sha256"
        private const val KEY_VERIFIED = "verified"
        private const val KEY_INSTALL_AFTER_PERMISSION = "install_after_permission"
        private const val STATUS_NOT_FOUND = "notFound"
        private const val STATUS_PENDING = "pending"
        private const val STATUS_DOWNLOADING = "downloading"
        private const val STATUS_PAUSED = "paused"
        private const val STATUS_READY = "ready"
        private const val STATUS_FAILED = "failed"
        private val SAFE_APK_FILE_NAME = Regex("^[A-Za-z0-9._-]+\\.apk$")
        private val SHA256 = Regex("^[0-9a-f]{64}$")
    }
}
