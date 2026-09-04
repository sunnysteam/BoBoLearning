import 'dart:async';

import 'package:bobo_learning/domain/models/video_item.dart';
import 'package:bobo_learning/ui/features/player/services/playback_controller.dart';
import 'package:bobo_learning/ui/features/player/view_models/player_view_model.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('PlayerViewModel', () {
    test('初始化后自动播放并预加载相邻视频', () async {
      final factory = _FakePlaybackControllerFactory();
      final viewModel = PlayerViewModel(
        items: [_video('1'), _video('2'), _video('3')],
        initialIndex: 0,
        controllerFactory: factory,
      );

      await viewModel.initialize();
      await Future<void>.delayed(Duration.zero);

      expect(factory.controllers[0].initializeCount, 1);
      expect(factory.controllers[0].posterUri, Uri.parse('https://example.com/1.jpg'));
      expect(factory.controllers[0].playCount, 1);
      expect(factory.controllers[1].initializeCount, 1);
      expect(factory.controllers, hasLength(2));
      expect(factory.hlsUris, [
        Uri.parse('https://example.com/1/index.m3u8'),
        Uri.parse('https://example.com/2/index.m3u8'),
      ]);
      viewModel.dispose();
    });

    test('切换页面会暂停旧视频并播放新视频', () async {
      final factory = _FakePlaybackControllerFactory();
      final viewModel = PlayerViewModel(
        items: [_video('1'), _video('2')],
        initialIndex: 0,
        controllerFactory: factory,
      );
      await viewModel.initialize();

      await viewModel.changePage(1);

      expect(viewModel.currentIndex, 1);
      expect(factory.controllers[0].pauseCount, 1);
      expect(factory.controllers[1].playCount, 1);
      viewModel.dispose();
    });

    test('拖动进度会暂停并在定位后恢复播放', () async {
      final factory = _FakePlaybackControllerFactory();
      final viewModel = PlayerViewModel(
        items: [_video('1')],
        initialIndex: 0,
        controllerFactory: factory,
      );
      await viewModel.initialize();

      await viewModel.beginSeek();
      await viewModel.completeSeek(const Duration(seconds: 36));

      final controller = factory.controllers.single;
      expect(controller.pauseCount, 1);
      expect(controller.lastSeek, const Duration(seconds: 36));
      expect(controller.playCount, 2);
      viewModel.dispose();
    });

    test('点击画面会在暂停和播放之间切换', () async {
      final factory = _FakePlaybackControllerFactory();
      final viewModel = PlayerViewModel(
        items: [_video('1')],
        initialIndex: 0,
        controllerFactory: factory,
      );
      await viewModel.initialize();

      await viewModel.togglePlayback();
      expect(factory.controllers.single.snapshot.isPlaying, isFalse);

      await viewModel.togglePlayback();
      expect(factory.controllers.single.snapshot.isPlaying, isTrue);
      viewModel.dispose();
    });

    test('自动播放被浏览器拒绝时提示用户点击播放', () async {
      final factory = _FakePlaybackControllerFactory(playShouldFail: true);
      final viewModel = PlayerViewModel(
        items: [_video('1')],
        initialIndex: 0,
        controllerFactory: factory,
      );

      await viewModel.initialize();

      expect(viewModel.requiresUserPlay, isTrue);
      expect(viewModel.isAutoPlayPending, isFalse);
      viewModel.dispose();
    });

    test('Web 自动播放会先静音并允许用户恢复声音', () async {
      final factory = _FakePlaybackControllerFactory();
      final viewModel = PlayerViewModel(
        items: [_video('1')],
        initialIndex: 0,
        controllerFactory: factory,
        useMutedWebAutoPlay: true,
      );

      await viewModel.initialize();

      expect(factory.controllers.single.volumeChanges, [0]);
      expect(factory.controllers.single.snapshot.isPlaying, isTrue);
      expect(viewModel.isMutedForAutoPlay, isTrue);

      await viewModel.enableSound();

      expect(factory.controllers.single.volumeChanges, [0, 1]);
      expect(viewModel.isMutedForAutoPlay, isFalse);
      viewModel.dispose();
    });

    test('播放器初始化超时会提供中文错误而不是无限等待', () async {
      final initializeGate = Completer<void>();
      final factory = _FakePlaybackControllerFactory(initializeGate: initializeGate);
      final viewModel = PlayerViewModel(
        items: [_video('1')],
        initialIndex: 0,
        controllerFactory: factory,
        initializationTimeout: const Duration(milliseconds: 5),
      );

      await viewModel.initialize();

      expect(viewModel.currentErrorMessage, '视频加载超时，请检查网络后重新加载');
      expect(viewModel.isAutoPlayPending, isFalse);
      viewModel.dispose();
    });

    test('切页撞上后台预加载失败时会用新控制器重试', () async {
      final factory = _PreloadRetryFactory();
      final viewModel = PlayerViewModel(
        items: [_video('1'), _video('2')],
        initialIndex: 0,
        controllerFactory: factory,
      );

      await viewModel.initialize();
      await Future<void>.delayed(Duration.zero);
      expect(factory.secondVideoCreateCount, 1);

      final pageChange = viewModel.changePage(1);
      await Future<void>.delayed(Duration.zero);
      factory.firstPreloadGate.completeError(StateError('后台预加载超时'));
      await pageChange;

      expect(factory.secondVideoCreateCount, 2);
      expect(viewModel.currentSnapshot.isPlaying, isTrue);
      expect(viewModel.currentErrorMessage, isNull);
      viewModel.dispose();
    });

    test('自动播放调用完成前保持等待态，完成后自动清除', () async {
      final playGate = Completer<void>();
      final factory = _FakePlaybackControllerFactory(playGate: playGate);
      final viewModel = PlayerViewModel(
        items: [_video('1')],
        initialIndex: 0,
        controllerFactory: factory,
      );

      final initialization = viewModel.initialize();
      await Future<void>.delayed(Duration.zero);

      expect(viewModel.isAutoPlayPending, isTrue);
      expect(factory.controllers.single.snapshot.isPlaying, isFalse);

      playGate.complete();
      await initialization;

      expect(viewModel.isAutoPlayPending, isFalse);
      expect(factory.controllers.single.snapshot.isPlaying, isTrue);
      viewModel.dispose();
    });
  });
}

VideoItem _video(String id) {
  return VideoItem(
    id: id,
    title: '视频 $id',
    coverUri: Uri.parse('https://example.com/$id.jpg'),
    streamUri: Uri.parse('https://example.com/$id.mp4'),
    hlsUri: Uri.parse('https://example.com/$id/index.m3u8'),
  );
}

class _FakePlaybackControllerFactory implements PlaybackControllerFactory {
  _FakePlaybackControllerFactory({this.playShouldFail = false, this.playGate, this.initializeGate});

  final bool playShouldFail;
  final Completer<void>? playGate;
  final Completer<void>? initializeGate;
  final List<_FakePlaybackController> controllers = [];
  final List<Uri?> hlsUris = [];

  @override
  PlaybackController create(Uri streamUri, {Uri? hlsUri}) {
    hlsUris.add(hlsUri);
    final controller = _FakePlaybackController(
      playShouldFail: playShouldFail,
      playGate: playGate,
      initializeGate: initializeGate,
    );
    controllers.add(controller);
    return controller;
  }
}

class _PreloadRetryFactory implements PlaybackControllerFactory {
  final Completer<void> firstPreloadGate = Completer<void>();
  int secondVideoCreateCount = 0;

  @override
  PlaybackController create(Uri streamUri, {Uri? hlsUri}) {
    final isSecondVideo = streamUri.path.endsWith('/2.mp4');
    if (isSecondVideo) {
      secondVideoCreateCount++;
    }
    return _FakePlaybackController(
      playShouldFail: false,
      playGate: null,
      initializeGate: isSecondVideo && secondVideoCreateCount == 1 ? firstPreloadGate : null,
    );
  }
}

class _FakePlaybackController extends PlaybackController {
  _FakePlaybackController({
    required this.playShouldFail,
    required this.playGate,
    required this.initializeGate,
  });

  final bool playShouldFail;
  final Completer<void>? playGate;
  final Completer<void>? initializeGate;
  int initializeCount = 0;
  int playCount = 0;
  int pauseCount = 0;
  Duration? lastSeek;
  final List<double> volumeChanges = [];
  Uri? posterUri;
  PlaybackSnapshot _snapshot = const PlaybackSnapshot.loading();

  @override
  PlaybackSnapshot get snapshot => _snapshot;

  @override
  Widget buildVideo() => const ColoredBox(color: Colors.blue);

  @override
  void setPoster(Uri posterUri) {
    this.posterUri = posterUri;
  }

  @override
  Future<void> initialize() async {
    initializeCount++;
    await initializeGate?.future;
    _snapshot = const PlaybackSnapshot(
      isInitialized: true,
      isPlaying: false,
      isBuffering: false,
      isCompleted: false,
      position: Duration.zero,
      duration: Duration(minutes: 2),
      size: Size(1920, 1080),
    );
    notifyListeners();
  }

  @override
  Future<void> pause() async {
    pauseCount++;
    _snapshot = _copySnapshot(isPlaying: false);
    notifyListeners();
  }

  @override
  Future<void> play() async {
    playCount++;
    await playGate?.future;
    if (playShouldFail) {
      throw StateError('浏览器禁止自动播放');
    }
    _snapshot = _copySnapshot(isPlaying: true);
    notifyListeners();
  }

  @override
  Future<void> setVolume(double volume) async {
    volumeChanges.add(volume);
  }

  @override
  Future<void> seekTo(Duration position) async {
    lastSeek = position;
    _snapshot = _copySnapshot(position: position);
    notifyListeners();
  }

  PlaybackSnapshot _copySnapshot({bool? isPlaying, Duration? position}) {
    return PlaybackSnapshot(
      isInitialized: _snapshot.isInitialized,
      isPlaying: isPlaying ?? _snapshot.isPlaying,
      isBuffering: _snapshot.isBuffering,
      isCompleted: _snapshot.isCompleted,
      position: position ?? _snapshot.position,
      duration: _snapshot.duration,
      size: _snapshot.size,
      errorMessage: _snapshot.errorMessage,
    );
  }
}
