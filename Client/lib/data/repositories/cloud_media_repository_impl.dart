import 'package:bobo_learning/config/app_config.dart';
import 'package:bobo_learning/data/services/cloud_media_api_service.dart';
import 'package:bobo_learning/domain/models/cloud_media_item.dart';
import 'package:bobo_learning/domain/repositories/cloud_media_repository.dart';

/// 百度网盘内容仓储默认实现。
class CloudMediaRepositoryImpl implements CloudMediaRepository {
  const CloudMediaRepositoryImpl({required this.apiService, required this.config});

  final CloudMediaApiService apiService;
  final AppConfig config;

  @override
  Future<List<CloudMediaItem>> fetchMedia(CloudMediaKind kind) async {
    final models = await apiService.fetchMedia(kind);
    final items = models
        .where((model) => model.kind == kind)
        .map(
          (model) => CloudMediaItem(
            id: model.id,
            fileName: model.fileName,
            kind: model.kind,
            sizeBytes: model.sizeBytes,
            modifiedAt: model.modifiedAt,
            thumbnailUri: config.resolveResource(model.thumbnailUrl),
            contentUri: config.resolveResource(model.contentUrl),
          ),
        )
        .toList(growable: true);
    items.sort((left, right) {
      final normalized = right.fileName.toLowerCase().compareTo(left.fileName.toLowerCase());
      return normalized != 0 ? normalized : right.fileName.compareTo(left.fileName);
    });
    return List.unmodifiable(items);
  }
}
