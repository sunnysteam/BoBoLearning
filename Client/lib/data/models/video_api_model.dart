/// 后端视频列表中的单条原始模型。
class VideoApiModel {
  const VideoApiModel({
    required this.id,
    required this.title,
    required this.coverUrl,
    required this.streamUrl,
    this.hlsUrl,
    this.folderPath = '',
  });

  factory VideoApiModel.fromJson(Map<String, Object?> json) {
    return VideoApiModel(
      id: _requiredString(json, 'id'),
      title: _requiredString(json, 'title'),
      folderPath: _optionalFolderPath(json),
      coverUrl: _requiredString(json, 'coverUrl'),
      streamUrl: _requiredString(json, 'streamUrl'),
      hlsUrl: _optionalString(json, 'hlsUrl'),
    );
  }

  final String id;
  final String title;
  final String folderPath;
  final String coverUrl;
  final String streamUrl;
  final String? hlsUrl;

  static String _requiredString(Map<String, Object?> json, String key) {
    final value = json[key];
    if (value is! String || value.trim().isEmpty) {
      throw FormatException('视频数据缺少有效字段：$key');
    }
    return value;
  }

  static String _optionalFolderPath(Map<String, Object?> json) {
    final value = json['folderPath'];
    if (value == null) {
      return '';
    }
    if (value is! String) {
      throw const FormatException('视频数据缺少有效字段：folderPath');
    }
    return value;
  }

  static String? _optionalString(Map<String, Object?> json, String key) {
    final value = json[key];
    if (value == null) {
      return null;
    }
    if (value is! String) {
      throw FormatException('视频数据字段类型无效：$key');
    }
    final normalized = value.trim();
    return normalized.isEmpty ? null : normalized;
  }
}
