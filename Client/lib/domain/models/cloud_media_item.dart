/// 百度网盘内容类型。
enum CloudMediaKind { video, photo }

/// 客户端使用的百度网盘只读媒体模型。
class CloudMediaItem {
  const CloudMediaItem({
    required this.id,
    required this.fileName,
    required this.kind,
    required this.sizeBytes,
    required this.modifiedAt,
    required this.thumbnailUri,
    required this.contentUri,
  });

  final String id;
  final String fileName;
  final CloudMediaKind kind;
  final int sizeBytes;
  final int modifiedAt;
  final Uri thumbnailUri;
  final Uri contentUri;
}
