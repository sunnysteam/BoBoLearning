import 'package:bobo_learning/config/app_config.dart';
import 'package:bobo_learning/data/services/app_update_api_service.dart';
import 'package:bobo_learning/domain/models/app_update.dart';
import 'package:bobo_learning/domain/repositories/app_update_repository.dart';
import 'package:flutter/foundation.dart';

class AppUpdateRepositoryImpl implements AppUpdateRepository {
  const AppUpdateRepositoryImpl({required this.apiService, required this.config});

  final AppUpdateApiService apiService;
  final AppConfig config;

  @override
  Future<AppUpdate?> findAvailableUpdate({required int currentVersionCode}) async {
    final model = await apiService.fetchLatest();
    if (model == null || model.versionCode <= currentVersionCode) {
      return null;
    }

    final downloadUri = config.resolveResource(model.downloadUrl);
    if (!const {'http', 'https'}.contains(downloadUri.scheme) || downloadUri.host.isEmpty) {
      throw const AppUpdateApiException('升级包下载地址不正确');
    }
    if (kReleaseMode && downloadUri.scheme != 'https') {
      throw const AppUpdateApiException('正式版本只允许通过 HTTPS 下载升级包');
    }
    if (downloadUri.pathSegments.isEmpty || !downloadUri.pathSegments.last.endsWith('.apk')) {
      throw const AppUpdateApiException('升级包必须是 APK 文件');
    }
    if (!RegExp(r'^[0-9a-f]{64}$').hasMatch(model.sha256)) {
      throw const AppUpdateApiException('升级包校验值格式不正确');
    }
    final publishedAt = DateTime.tryParse(model.publishedAt);
    if (publishedAt == null) {
      throw const AppUpdateApiException('升级包发布时间格式不正确');
    }

    return AppUpdate(
      versionName: model.versionName,
      versionCode: model.versionCode,
      downloadUri: downloadUri,
      sha256: model.sha256,
      sizeBytes: model.sizeBytes,
      releaseNotes: model.releaseNotes,
      publishedAt: publishedAt,
    );
  }
}
