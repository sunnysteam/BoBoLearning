import 'dart:async';

import 'package:bobo_learning/ui/features/player/services/playback_contract.dart';
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

/// 在 Android、iOS 和桌面端使用官方 video_player 插件。
PlaybackController createPlatformPlaybackController(Uri streamUri, {Uri? hlsUri}) {
  return VideoPlayerPlaybackController(hlsUri ?? streamUri);
}

/// 官方 video_player 插件适配器。
class VideoPlayerPlaybackController extends PlaybackController {
  VideoPlayerPlaybackController(Uri streamUri)
    : _controller = VideoPlayerController.networkUrl(streamUri) {
    _controller.addListener(_onValueChanged);
  }

  final VideoPlayerController _controller;
  String? _externalError;
  bool _disposed = false;

  @override
  PlaybackSnapshot get snapshot {
    final value = _controller.value;
    return PlaybackSnapshot(
      isInitialized: value.isInitialized,
      isPlaying: value.isPlaying,
      isBuffering: value.isBuffering,
      isCompleted: value.isCompleted,
      position: value.position,
      duration: value.duration,
      size: value.size,
      errorMessage: _externalError ?? _localizedError(value.errorDescription),
    );
  }

  @override
  Widget buildVideo() => VideoPlayer(_controller);

  @override
  Future<void> initialize() async {
    try {
      _externalError = null;
      await _controller.initialize();
      await _controller.setLooping(false);
    } on Object {
      _externalError = '视频加载失败，请检查网络后再试';
      _notify();
      rethrow;
    }
  }

  @override
  Future<void> pause() => _controller.pause();

  @override
  Future<void> play() => _controller.play();

  @override
  Future<void> setVolume(double volume) => _controller.setVolume(volume.clamp(0, 1).toDouble());

  @override
  Future<void> seekTo(Duration position) => _controller.seekTo(position);

  String? _localizedError(String? error) {
    if (error == null || error.trim().isEmpty) {
      return null;
    }
    if (RegExp(r'[\u4e00-\u9fff]').hasMatch(error)) {
      return error;
    }
    final normalized = error.toLowerCase();
    if (normalized.contains('user gesture') ||
        normalized.contains('notallowederror') ||
        normalized.contains('not allowed')) {
      return '浏览器暂时阻止了播放，请重新加载后再试';
    }
    if (normalized.contains('network') ||
        normalized.contains('source') ||
        normalized.contains('media')) {
      return '视频连接中断，请检查网络后重新加载';
    }
    return '视频播放失败，请重新加载后再试';
  }

  void _onValueChanged() => _notify();

  void _notify() {
    if (!_disposed) {
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _controller.removeListener(_onValueChanged);
    unawaited(_controller.dispose());
    super.dispose();
  }
}
