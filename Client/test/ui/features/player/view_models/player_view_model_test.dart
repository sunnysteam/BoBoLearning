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
      expect(factory.controllers[0].playCount, 1);
      expect(factory.controllers[1].initializeCount, 1);
      expect(factory.controllers, hasLength(2));
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
  );
}

class _FakePlaybackControllerFactory implements PlaybackControllerFactory {
  _FakePlaybackControllerFactory({this.playShouldFail = false});

  final bool playShouldFail;
  final List<_FakePlaybackController> controllers = [];

  @override
  PlaybackController create(Uri streamUri) {
    final controller = _FakePlaybackController(playShouldFail: playShouldFail);
    controllers.add(controller);
    return controller;
  }
}

class _FakePlaybackController extends PlaybackController {
  _FakePlaybackController({required this.playShouldFail});

  final bool playShouldFail;
  int initializeCount = 0;
  int playCount = 0;
  int pauseCount = 0;
  Duration? lastSeek;
  PlaybackSnapshot _snapshot = const PlaybackSnapshot.loading();

  @override
  PlaybackSnapshot get snapshot => _snapshot;

  @override
  Widget buildVideo() => const ColoredBox(color: Colors.blue);

  @override
  Future<void> initialize() async {
    initializeCount++;
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
    if (playShouldFail) {
      throw StateError('浏览器禁止自动播放');
    }
    _snapshot = _copySnapshot(isPlaying: true);
    notifyListeners();
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
