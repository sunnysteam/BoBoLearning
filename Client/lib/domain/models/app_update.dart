/// 可安装的 Android 应用更新。
class AppUpdate {
  const AppUpdate({
    required this.versionName,
    required this.versionCode,
    required this.downloadUri,
    required this.sha256,
    required this.sizeBytes,
    required this.releaseNotes,
    required this.publishedAt,
  });

  final String versionName;
  final int versionCode;
  final Uri downloadUri;
  final String sha256;
  final int sizeBytes;
  final List<String> releaseNotes;
  final DateTime publishedAt;

  String get fileName => downloadUri.pathSegments.last;
}

/// 当前平台应用版本信息。
class AppPlatformInfo {
  const AppPlatformInfo({
    required this.supported,
    required this.versionName,
    required this.versionCode,
  });

  const AppPlatformInfo.unsupported() : supported = false, versionName = '', versionCode = 0;

  final bool supported;
  final String versionName;
  final int versionCode;
}

enum UpdateDownloadPhase { notFound, pending, downloading, paused, ready, failed }

/// Android 系统后台下载任务的可恢复快照。
class UpdateDownloadSnapshot {
  const UpdateDownloadSnapshot({
    required this.phase,
    this.versionCode,
    this.downloadedBytes = 0,
    this.totalBytes = 0,
    this.message,
  });

  const UpdateDownloadSnapshot.notFound()
    : phase = UpdateDownloadPhase.notFound,
      versionCode = null,
      downloadedBytes = 0,
      totalBytes = 0,
      message = null;

  final UpdateDownloadPhase phase;
  final int? versionCode;
  final int downloadedBytes;
  final int totalBytes;
  final String? message;

  double? get progress {
    if (totalBytes <= 0 || downloadedBytes < 0) {
      return null;
    }
    return (downloadedBytes / totalBytes).clamp(0, 1);
  }
}

enum UpdateInstallResult { opened, permissionRequired }
