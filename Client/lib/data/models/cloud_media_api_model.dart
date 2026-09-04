import 'package:bobo_learning/domain/models/cloud_media_item.dart';

/// 后端百度网盘列表中的单条原始模型。
class CloudMediaApiModel {
  const CloudMediaApiModel({
    required this.id,
    required this.fileName,
    required this.kind,
    required this.sizeBytes,
    required this.modifiedAt,
    required this.thumbnailUrl,
    required this.contentUrl,
  });

  factory CloudMediaApiModel.fromJson(Map<String, Object?> json) {
    final kindValue = _requiredString(json, 'kind');
    final kind = switch (kindValue) {
      'video' => CloudMediaKind.video,
      'photo' => CloudMediaKind.photo,
      _ => throw const FormatException('云端媒体类型无效'),
    };
    return CloudMediaApiModel(
      id: _requiredString(json, 'id'),
      fileName: _requiredString(json, 'fileName'),
      kind: kind,
      sizeBytes: _requiredInt(json, 'sizeBytes'),
      modifiedAt: _requiredInt(json, 'modifiedAt'),
      thumbnailUrl: _requiredString(json, 'thumbnailUrl'),
      contentUrl: _requiredString(json, 'contentUrl'),
    );
  }

  final String id;
  final String fileName;
  final CloudMediaKind kind;
  final int sizeBytes;
  final int modifiedAt;
  final String thumbnailUrl;
  final String contentUrl;

  static String _requiredString(Map<String, Object?> json, String key) {
    final value = json[key];
    if (value is! String || value.trim().isEmpty) {
      throw FormatException('云端媒体数据缺少有效字段：$key');
    }
    return value;
  }

  static int _requiredInt(Map<String, Object?> json, String key) {
    final value = json[key];
    if (value is! int || value < 0) {
      throw FormatException('云端媒体数据缺少有效字段：$key');
    }
    return value;
  }
}
