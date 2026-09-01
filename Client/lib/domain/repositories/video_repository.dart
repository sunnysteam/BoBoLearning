import 'package:bobo_learning/domain/models/video_item.dart';

/// 视频目录仓储契约。
abstract interface class VideoRepository {
  Future<List<VideoItem>> fetchVideos();
}
