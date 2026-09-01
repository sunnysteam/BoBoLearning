import 'dart:async';

import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

/// 与具体播放器插件无关的播放状态。
class PlaybackSnapshot {
  const PlaybackSnapshot({
    required this.isInitialized,
    required this.isPlaying,
    required this.isBuffering,
    required this.isCompleted,
    required this.position,
    required this.duration,
    required this.size,
    this.errorMessage,
  });

  const PlaybackSnapshot.loading()
    : isInitialized = false,
      isPlaying = false,
      isBuffering = false,
      isCompleted = false,
      position = Duration.zero,
      duration = Duration.zero,
      size = Size.zero,
      errorMessage = null;

  final bool isInitialized;
  final bool isPlaying;
  final bool isBuffering;
  final bool isCompleted;
  final Duration position;
  final Duration duration;
  final Size size;
  final String? errorMessage;

  double get aspectRatio {
    if (size.width <= 0 || size.height <= 0) {
      return 16 / 9;
    }
    return size.width / size.height;
  }
}

/// 可替换、可测试的视频控制器。
abstract class PlaybackController extends ChangeNotifier {
  PlaybackSnapshot get snapshot;

  Widget buildVideo();

  Future<void> initialize();

  Future<void> play();

  Future<void> pause();

  Future<void> seekTo(Duration position);
}

abstract interface class PlaybackControllerFactory {
  PlaybackController create(Uri streamUri);
}

/// 官方 video_player 插件适配器工厂。
class VideoPlayerControllerFactory implements PlaybackControllerFactory {
  const VideoPlayerControllerFactory();

  @override
  PlaybackController create(Uri streamUri) {
    return VideoPlayerPlaybackController(streamUri);
  }
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
      errorMessage: _externalError ?? value.errorDescription,
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
      _externalError = '视频加载失败，请再试一次';
      _notify();
      rethrow;
    }
  }

  @override
  Future<void> pause() => _controller.pause();

  @override
  Future<void> play() => _controller.play();

  @override
  Future<void> seekTo(Duration position) => _controller.seekTo(position);

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
