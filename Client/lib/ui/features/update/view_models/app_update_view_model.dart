import 'dart:async';

import 'package:bobo_learning/data/services/app_update_api_service.dart';
import 'package:bobo_learning/domain/models/app_update.dart';
import 'package:bobo_learning/domain/repositories/app_update_repository.dart';
import 'package:bobo_learning/ui/features/update/services/app_update_platform.dart';
import 'package:flutter/foundation.dart';

enum AppUpdatePhase { disabled, idle, checking, downloading, ready, installing, failed }

/// 协调版本检查、系统后台下载和安装状态，不承担界面绘制。
class AppUpdateViewModel extends ChangeNotifier {
  AppUpdateViewModel({
    required this.repository,
    required this.platform,
    this.pollInterval = const Duration(seconds: 2),
    this.minimumCheckInterval = const Duration(minutes: 15),
  });

  final AppUpdateRepository repository;
  final AppUpdatePlatform platform;
  final Duration pollInterval;
  final Duration minimumCheckInterval;

  AppUpdatePhase _phase = AppUpdatePhase.idle;
  AppUpdate? _update;
  double? _progress;
  String? _message;
  DateTime? _lastCheckedAt;
  Timer? _pollTimer;
  bool _working = false;
  bool _disposed = false;

  AppUpdatePhase get phase => _phase;
  AppUpdate? get update => _update;
  double? get progress => _progress;
  String? get message => _message;

  Future<void> start() => _checkForUpdate(force: true);

  Future<void> onAppResumed() async {
    if (_disposed || _working || _phase == AppUpdatePhase.disabled) {
      return;
    }
    if (_update != null &&
        const {
          AppUpdatePhase.downloading,
          AppUpdatePhase.ready,
          AppUpdatePhase.installing,
        }.contains(_phase)) {
      await _refreshDownloadStatus();
      return;
    }
    await _checkForUpdate(force: false);
  }

  Future<UpdateInstallResult?> install() async {
    if (_update == null || _phase != AppUpdatePhase.ready || _working) {
      return null;
    }
    _working = true;
    _setState(phase: AppUpdatePhase.installing, clearMessage: true);
    try {
      final result = await platform.installDownloadedUpdate();
      if (result == UpdateInstallResult.permissionRequired) {
        _setState(phase: AppUpdatePhase.ready, message: '请允许菠萝乐园安装应用，返回后会继续打开安装页面');
      }
      return result;
    } on AppUpdatePlatformException catch (error) {
      _setState(phase: AppUpdatePhase.failed, message: error.message);
      return null;
    } finally {
      _working = false;
    }
  }

  Future<void> _checkForUpdate({required bool force}) async {
    if (_disposed || _working) {
      return;
    }
    final lastCheckedAt = _lastCheckedAt;
    if (!force &&
        lastCheckedAt != null &&
        DateTime.now().difference(lastCheckedAt) < minimumCheckInterval) {
      return;
    }

    _working = true;
    _setState(phase: AppUpdatePhase.checking, clearMessage: true);
    try {
      final platformInfo = await platform.getPlatformInfo();
      if (!platformInfo.supported) {
        _setState(phase: AppUpdatePhase.disabled, clearMessage: true);
        return;
      }
      _lastCheckedAt = DateTime.now();
      final available = await repository.findAvailableUpdate(
        currentVersionCode: platformInfo.versionCode,
      );
      if (available == null) {
        _update = null;
        _setState(phase: AppUpdatePhase.idle, progress: null, clearMessage: true);
        return;
      }

      _update = available;
      final snapshot = await platform.getDownloadStatus();
      if (snapshot.versionCode == available.versionCode &&
          snapshot.phase != UpdateDownloadPhase.notFound &&
          snapshot.phase != UpdateDownloadPhase.failed) {
        _applySnapshot(snapshot);
      } else {
        await platform.startDownload(available);
        _setState(phase: AppUpdatePhase.downloading, progress: 0, clearMessage: true);
        _startPolling();
      }
    } on AppUpdateApiException catch (error) {
      _setState(phase: AppUpdatePhase.failed, message: error.message);
    } on AppUpdatePlatformException catch (error) {
      _setState(phase: AppUpdatePhase.failed, message: error.message);
    } finally {
      _working = false;
    }
  }

  Future<void> _refreshDownloadStatus() async {
    if (_disposed || _working || _update == null) {
      return;
    }
    _working = true;
    try {
      final snapshot = await platform.getDownloadStatus();
      if (snapshot.versionCode != _update!.versionCode) {
        _stopPolling();
        _setState(phase: AppUpdatePhase.failed, message: '升级包状态已失效，将在稍后重新下载');
        return;
      }
      _applySnapshot(snapshot);
    } on AppUpdatePlatformException catch (error) {
      _stopPolling();
      _setState(phase: AppUpdatePhase.failed, message: error.message);
    } finally {
      _working = false;
    }
  }

  void _applySnapshot(UpdateDownloadSnapshot snapshot) {
    switch (snapshot.phase) {
      case UpdateDownloadPhase.pending:
      case UpdateDownloadPhase.downloading:
      case UpdateDownloadPhase.paused:
        _setState(
          phase: AppUpdatePhase.downloading,
          progress: snapshot.progress,
          clearMessage: true,
        );
        _startPolling();
      case UpdateDownloadPhase.ready:
        _stopPolling();
        _setState(phase: AppUpdatePhase.ready, progress: 1, clearMessage: true);
      case UpdateDownloadPhase.failed:
      case UpdateDownloadPhase.notFound:
        _stopPolling();
        _setState(phase: AppUpdatePhase.failed, message: snapshot.message ?? '升级包下载失败，将在稍后自动重试');
    }
  }

  void _startPolling() {
    if (_disposed || _pollTimer != null) {
      return;
    }
    _pollTimer = Timer.periodic(pollInterval, (_) => unawaited(_refreshDownloadStatus()));
  }

  void _stopPolling() {
    _pollTimer?.cancel();
    _pollTimer = null;
  }

  void _setState({
    required AppUpdatePhase phase,
    double? progress,
    String? message,
    bool clearMessage = false,
  }) {
    if (_disposed) {
      return;
    }
    _phase = phase;
    _progress = progress;
    if (clearMessage) {
      _message = null;
    } else if (message != null) {
      _message = message;
    }
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _stopPolling();
    super.dispose();
  }
}
