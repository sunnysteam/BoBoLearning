import 'package:flutter/material.dart';

/// 与具体播放器实现无关的播放状态。
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

  /// 设置播放器未输出首帧时显示的封面。
  void setPoster(Uri posterUri) {}

  Future<void> initialize();

  Future<void> play();

  Future<void> pause();

  /// 调整播放音量，范围为 0 到 1。
  Future<void> setVolume(double volume) async {}

  Future<void> seekTo(Duration position);
}

abstract interface class PlaybackControllerFactory {
  PlaybackController create(Uri streamUri, {Uri? hlsUri});
}
