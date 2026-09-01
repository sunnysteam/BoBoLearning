import 'package:bobo_learning/config/app_config.dart';
import 'package:bobo_learning/data/services/video_api_service.dart';
import 'package:bobo_learning/domain/models/video_item.dart';
import 'package:bobo_learning/domain/repositories/video_repository.dart';

/// 视频仓储默认实现。
class VideoRepositoryImpl implements VideoRepository {
  const VideoRepositoryImpl({required this._apiService, required this._config});

  final VideoApiService _apiService;
  final AppConfig _config;

  @override
  Future<List<VideoItem>> fetchVideos() async {
    final models = await _apiService.fetchVideos();
    return models
        .map(
          (model) => VideoItem(
            id: model.id,
            title: model.title,
            folderPath: model.folderPath,
            coverUri: _config.resolveResource(model.coverUrl),
            streamUri: _config.resolveResource(model.streamUrl),
          ),
        )
        .toList(growable: false);
  }
}
