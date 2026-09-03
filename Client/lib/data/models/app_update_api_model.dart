/// 升级清单接口模型。
class AppUpdateApiModel {
  const AppUpdateApiModel({
    required this.versionName,
    required this.versionCode,
    required this.downloadUrl,
    required this.sha256,
    required this.sizeBytes,
    required this.releaseNotes,
    required this.publishedAt,
  });

  factory AppUpdateApiModel.fromJson(Map<String, Object?> json) {
    final notes = json['releaseNotes'];
    if (notes is! List<Object?> || notes.any((note) => note is! String)) {
      throw const FormatException('升级说明格式不正确');
    }

    return AppUpdateApiModel(
      versionName: _requiredString(json, 'versionName'),
      versionCode: _requiredPositiveInt(json, 'versionCode'),
      downloadUrl: _requiredString(json, 'downloadUrl'),
      sha256: _requiredString(json, 'sha256'),
      sizeBytes: _requiredPositiveInt(json, 'sizeBytes'),
      releaseNotes: List<String>.unmodifiable(notes.cast<String>()),
      publishedAt: _requiredString(json, 'publishedAt'),
    );
  }

  final String versionName;
  final int versionCode;
  final String downloadUrl;
  final String sha256;
  final int sizeBytes;
  final List<String> releaseNotes;
  final String publishedAt;
}

String _requiredString(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value is! String || value.trim().isEmpty) {
    throw FormatException('升级清单缺少 $key');
  }
  return value.trim();
}

int _requiredPositiveInt(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value is! int || value <= 0) {
    throw FormatException('升级清单中的 $key 必须大于 0');
  }
  return value;
}
