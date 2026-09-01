/// 客户端使用的视频领域模型。
class VideoItem {
  const VideoItem({
    required this.id,
    required this.title,
    required this.coverUri,
    required this.streamUri,
    this.folderPath = '',
  });

  final String id;
  final String title;
  final String folderPath;
  final Uri coverUri;
  final Uri streamUri;

  @override
  bool operator ==(Object other) {
    return other is VideoItem &&
        other.id == id &&
        other.title == title &&
        other.folderPath == folderPath &&
        other.coverUri == coverUri &&
        other.streamUri == streamUri;
  }

  @override
  int get hashCode => Object.hash(id, title, folderPath, coverUri, streamUri);
}
