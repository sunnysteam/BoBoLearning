import 'package:bobo_learning/domain/models/video_item.dart';
import 'package:bobo_learning/ui/core/app_theme.dart';
import 'package:bobo_learning/ui/features/player/services/playback_controller.dart';
import 'package:bobo_learning/ui/features/player/view_models/player_view_model.dart';
import 'package:bobo_learning/ui/features/player/views/player_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('播放完成后重新显示返回按钮和进度控制层', (tester) async {
    final controller = _ControllablePlaybackController();
    final viewModel = PlayerViewModel(
      items: [
        VideoItem(
          id: '1',
          title: '认识花朵',
          coverUri: Uri.parse('https://invalid.example/cover.png'),
          streamUri: Uri.parse('https://invalid.example/video.mp4'),
        ),
      ],
      initialIndex: 0,
      controllerFactory: _FixedPlaybackControllerFactory(controller),
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: PlayerPage(viewModel: viewModel),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(seconds: 4));

    expect(_topControlsOpacity(tester), 0);

    controller.complete();
    await tester.pump();

    expect(_topControlsOpacity(tester), 1);
    expect(find.byKey(const Key('中央播放按钮')), findsOneWidget);
  });

  testWidgets('向上滑动会按顺序切换并播放下一个视频', (tester) async {
    final factory = _SequencePlaybackControllerFactory();
    final viewModel = PlayerViewModel(
      items: [_video('1', '认识花朵'), _video('2', '观察自然')],
      initialIndex: 0,
      controllerFactory: factory,
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: PlayerPage(viewModel: viewModel),
      ),
    );
    await tester.pump();
    expect(find.text('认识花朵'), findsOneWidget);

    await tester.drag(find.byKey(const Key('纵向视频列表')), const Offset(0, -520));
    await tester.pumpAndSettle();

    expect(find.text('观察自然'), findsOneWidget);
    expect(viewModel.currentIndex, 1);
    expect(factory.controllers[0].snapshot.isPlaying, isFalse);
    expect(factory.controllers[1].snapshot.isPlaying, isTrue);
  });
}

VideoItem _video(String id, String title) {
  return VideoItem(
    id: id,
    title: title,
    coverUri: Uri.parse('https://invalid.example/$id.png'),
    streamUri: Uri.parse('https://invalid.example/$id.mp4'),
  );
}

double _topControlsOpacity(WidgetTester tester) {
  final opacityFinder = find.ancestor(
    of: find.byKey(const Key('返回首页按钮')),
    matching: find.byType(AnimatedOpacity),
  );
  return tester.widget<AnimatedOpacity>(opacityFinder).opacity;
}

class _FixedPlaybackControllerFactory implements PlaybackControllerFactory {
  const _FixedPlaybackControllerFactory(this.controller);

  final PlaybackController controller;

  @override
  PlaybackController create(Uri streamUri) => controller;
}

class _SequencePlaybackControllerFactory implements PlaybackControllerFactory {
  final List<_ControllablePlaybackController> controllers = [];

  @override
  PlaybackController create(Uri streamUri) {
    final controller = _ControllablePlaybackController();
    controllers.add(controller);
    return controller;
  }
}

class _ControllablePlaybackController extends PlaybackController {
  PlaybackSnapshot _snapshot = const PlaybackSnapshot.loading();

  @override
  PlaybackSnapshot get snapshot => _snapshot;

  @override
  Widget buildVideo() => const ColoredBox(color: Colors.black);

  void complete() {
    _snapshot = _copySnapshot(isPlaying: false, isCompleted: true);
    notifyListeners();
  }

  @override
  Future<void> initialize() async {
    _snapshot = const PlaybackSnapshot(
      isInitialized: true,
      isPlaying: false,
      isBuffering: false,
      isCompleted: false,
      position: Duration.zero,
      duration: Duration(minutes: 1),
      size: Size(1920, 1080),
    );
    notifyListeners();
  }

  @override
  Future<void> pause() async {
    _snapshot = _copySnapshot(isPlaying: false);
    notifyListeners();
  }

  @override
  Future<void> play() async {
    _snapshot = _copySnapshot(isPlaying: true, isCompleted: false);
    notifyListeners();
  }

  @override
  Future<void> seekTo(Duration position) async {
    _snapshot = _copySnapshot(position: position);
    notifyListeners();
  }

  PlaybackSnapshot _copySnapshot({bool? isPlaying, bool? isCompleted, Duration? position}) {
    return PlaybackSnapshot(
      isInitialized: _snapshot.isInitialized,
      isPlaying: isPlaying ?? _snapshot.isPlaying,
      isBuffering: _snapshot.isBuffering,
      isCompleted: isCompleted ?? _snapshot.isCompleted,
      position: position ?? _snapshot.position,
      duration: _snapshot.duration,
      size: _snapshot.size,
      errorMessage: _snapshot.errorMessage,
    );
  }
}
