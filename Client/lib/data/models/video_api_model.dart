/// 后端视频列表中的单条原始模型。
class VideoApiModel {
  const VideoApiModel({
    required this.id,
    required this.title,
    required this.coverUrl,
    required this.streamUrl,
    this.folderPath = '',
  });

  factory VideoApiModel.fromJson(Map<String, Object?> json) {
    return VideoApiModel(
      id: _requiredString(json, 'id'),
      title: _requiredString(json, 'title'),
      folderPath: _optionalFolderPath(json),
      coverUrl: _requiredString(json, 'coverUrl'),
      streamUrl: _requiredString(json, 'streamUrl'),
    );
  }

  final String id;
  final String title;
  final String folderPath;
  final String coverUrl;
  final String streamUrl;

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
}
