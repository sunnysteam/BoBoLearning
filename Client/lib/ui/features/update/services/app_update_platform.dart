import 'package:bobo_learning/domain/models/app_update.dart';
import 'package:flutter/services.dart';

abstract interface class AppUpdatePlatform {
  Future<AppPlatformInfo> getPlatformInfo();

  Future<UpdateDownloadSnapshot> getDownloadStatus();

  Future<void> startDownload(AppUpdate update);

  Future<UpdateInstallResult> installDownloadedUpdate();
}

/// Android 升级原生能力适配器；不支持的平台会返回禁用状态。
class MethodChannelAppUpdatePlatform implements AppUpdatePlatform {
  const MethodChannelAppUpdatePlatform();

  static const _channel = MethodChannel('bobo_learning/app_update');

  @override
  Future<AppPlatformInfo> getPlatformInfo() async {
    try {
      final result = await _channel.invokeMapMethod<String, Object?>('getPlatformInfo');
      if (result == null || result['supported'] != true) {
        return const AppPlatformInfo.unsupported();
      }
      return AppPlatformInfo(
        supported: true,
        versionName: result['versionName'] as String? ?? '',
        versionCode: _asInt(result['versionCode']),
      );
    } on MissingPluginException {
      return const AppPlatformInfo.unsupported();
    } on PlatformException catch (error) {
      throw AppUpdatePlatformException(error.message ?? '无法读取当前应用版本');
    }
  }

  @override
  Future<UpdateDownloadSnapshot> getDownloadStatus() async {
    try {
      final result = await _channel.invokeMapMethod<String, Object?>('getDownloadStatus');
      if (result == null) {
        return const UpdateDownloadSnapshot.notFound();
      }
      final phase = switch (result['status']) {
        'pending' => UpdateDownloadPhase.pending,
        'downloading' => UpdateDownloadPhase.downloading,
        'paused' => UpdateDownloadPhase.paused,
        'ready' => UpdateDownloadPhase.ready,
        'failed' => UpdateDownloadPhase.failed,
        _ => UpdateDownloadPhase.notFound,
      };
      return UpdateDownloadSnapshot(
        phase: phase,
        versionCode: _asNullableInt(result['versionCode']),
        downloadedBytes: _asInt(result['downloadedBytes']),
        totalBytes: _asInt(result['totalBytes']),
        message: result['message'] as String?,
      );
    } on MissingPluginException {
      return const UpdateDownloadSnapshot.notFound();
    } on PlatformException catch (error) {
      throw AppUpdatePlatformException(error.message ?? '无法读取升级包下载状态');
    }
  }

  @override
  Future<void> startDownload(AppUpdate update) async {
    try {
      await _channel.invokeMethod<void>('startDownload', <String, Object>{
        'url': update.downloadUri.toString(),
        'fileName': update.fileName,
        'versionCode': update.versionCode,
        'sha256': update.sha256,
        'sizeBytes': update.sizeBytes,
      });
    } on PlatformException catch (error) {
      throw AppUpdatePlatformException(error.message ?? '无法开始下载升级包');
    }
  }

  @override
  Future<UpdateInstallResult> installDownloadedUpdate() async {
    try {
      final result = await _channel.invokeMethod<String>('installDownloadedUpdate');
      return result == 'permissionRequired'
          ? UpdateInstallResult.permissionRequired
          : UpdateInstallResult.opened;
    } on PlatformException catch (error) {
      throw AppUpdatePlatformException(error.message ?? '无法打开系统安装器');
    }
  }
}

class AppUpdatePlatformException implements Exception {
  const AppUpdatePlatformException(this.message);

  final String message;

  @override
  String toString() => message;
}

int _asInt(Object? value) => value is int ? value : 0;

int? _asNullableInt(Object? value) => value is int ? value : null;
