import 'package:bobo_learning/domain/models/cloud_media_item.dart';

/// 百度网盘只读内容仓储。
abstract interface class CloudMediaRepository {
  Future<List<CloudMediaItem>> fetchMedia(CloudMediaKind kind);
}
