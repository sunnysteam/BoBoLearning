import 'dart:async';

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

  testWidgets('首次进入和上下切换的自动播放等待期间不显示播放按钮', (tester) async {
    final firstPlayGate = Completer<void>();
    final secondPlayGate = Completer<void>();
    final firstPauseGate = Completer<void>();
    final factory = _SequencePlaybackControllerFactory(
      playGates: [firstPlayGate, secondPlayGate],
      pauseGates: [firstPauseGate, null],
    );
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

    expect(viewModel.isAutoPlayPending, isTrue);
    expect(find.byKey(const Key('中央播放按钮')), findsNothing);

    firstPlayGate.complete();
    await tester.pump();
    await tester.pump();

    expect(viewModel.isAutoPlayPending, isFalse);
    expect(factory.controllers[0].snapshot.isPlaying, isTrue);
    expect(find.byKey(const Key('中央播放按钮')), findsNothing);

    await tester.drag(find.byKey(const Key('纵向视频列表')), const Offset(0, -520));
    await tester.pump(const Duration(milliseconds: 600));

    expect(viewModel.currentIndex, 1);
    expect(viewModel.isAutoPlayPending, isTrue);
    expect(find.byKey(const Key('中央播放按钮')), findsNothing);

    firstPauseGate.complete();
    await tester.pump();

    expect(viewModel.isAutoPlayPending, isTrue);
    expect(find.byKey(const Key('中央播放按钮')), findsNothing);

    secondPlayGate.complete();
    await tester.pumpAndSettle();

    expect(viewModel.isAutoPlayPending, isFalse);
    expect(factory.controllers[1].snapshot.isPlaying, isTrue);
    expect(find.byKey(const Key('中央播放按钮')), findsNothing);
  });

  testWidgets('大屏 Web 左右按钮会按照前后视频边界显示并切换', (tester) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final factory = _SequencePlaybackControllerFactory();
    final viewModel = PlayerViewModel(
      items: [_video('1', '第一条'), _video('2', '第二条'), _video('3', '第三条')],
      initialIndex: 0,
      controllerFactory: factory,
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: PlayerPage(viewModel: viewModel, desktopNavigationEnabled: true),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('上一个视频按钮')), findsNothing);
    expect(find.byKey(const Key('下一个视频按钮')), findsOneWidget);

    await tester.tap(find.byKey(const Key('下一个视频按钮')));
    await tester.pumpAndSettle();

    expect(viewModel.currentIndex, 1);
    expect(find.byKey(const Key('上一个视频按钮')), findsOneWidget);
    expect(find.byKey(const Key('下一个视频按钮')), findsOneWidget);

    await tester.tap(find.byKey(const Key('下一个视频按钮')));
    await tester.pumpAndSettle();

    expect(viewModel.currentIndex, 2);
    expect(find.byKey(const Key('上一个视频按钮')), findsOneWidget);
    expect(find.byKey(const Key('下一个视频按钮')), findsNothing);
  });

  testWidgets('手机宽度不显示大屏左右切换按钮', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final viewModel = PlayerViewModel(
      items: [_video('1', '第一条'), _video('2', '第二条')],
      initialIndex: 0,
      controllerFactory: _SequencePlaybackControllerFactory(),
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: PlayerPage(viewModel: viewModel, desktopNavigationEnabled: true),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('上一个视频按钮')), findsNothing);
    expect(find.byKey(const Key('下一个视频按钮')), findsNothing);
  });

  testWidgets('连续缓冲八秒后显示慢网络提示和重新加载入口', (tester) async {
    final controller = _ControllablePlaybackController();
    final viewModel = PlayerViewModel(
      items: [_video('1', '认识花朵')],
      initialIndex: 0,
      controllerFactory: _FixedPlaybackControllerFactory(controller),
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: PlayerPage(viewModel: viewModel),
      ),
    );
    await tester.pumpAndSettle();
    controller.setBuffering(true);
    await tester.pump();

    expect(find.text('正在缓冲，请稍候'), findsOneWidget);
    expect(find.byKey(const Key('缓冲重新加载按钮')), findsNothing);

    await tester.pump(const Duration(seconds: 8));

    expect(find.text('网络有点慢，仍在努力加载'), findsOneWidget);
    expect(find.byKey(const Key('缓冲重新加载按钮')), findsOneWidget);
  });

  testWidgets('Web 静音自动播放后显示开启声音入口', (tester) async {
    final controller = _ControllablePlaybackController();
    final viewModel = PlayerViewModel(
      items: [_video('1', '认识花朵')],
      initialIndex: 0,
      controllerFactory: _FixedPlaybackControllerFactory(controller),
      useMutedWebAutoPlay: true,
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: PlayerPage(viewModel: viewModel),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('开启声音按钮')), findsOneWidget);
    await tester.tap(find.byKey(const Key('开启声音按钮')));
    await tester.pump();

    expect(find.byKey(const Key('开启声音按钮')), findsNothing);
    expect(controller.volumeChanges, [0, 1]);
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
  PlaybackController create(Uri streamUri, {Uri? hlsUri}) => controller;
}

class _SequencePlaybackControllerFactory implements PlaybackControllerFactory {
  _SequencePlaybackControllerFactory({this.playGates = const [], this.pauseGates = const []});

  final List<Completer<void>?> playGates;
  final List<Completer<void>?> pauseGates;
  final List<_ControllablePlaybackController> controllers = [];

  @override
  PlaybackController create(Uri streamUri, {Uri? hlsUri}) {
    final index = controllers.length;
    final controller = _ControllablePlaybackController(
      playGate: index < playGates.length ? playGates[index] : null,
      pauseGate: index < pauseGates.length ? pauseGates[index] : null,
    );
    controllers.add(controller);
    return controller;
  }
}

class _ControllablePlaybackController extends PlaybackController {
  _ControllablePlaybackController({this.playGate, this.pauseGate});

  final Completer<void>? playGate;
  final Completer<void>? pauseGate;
  PlaybackSnapshot _snapshot = const PlaybackSnapshot.loading();
  final List<double> volumeChanges = [];

  @override
  PlaybackSnapshot get snapshot => _snapshot;

  @override
  Widget buildVideo() => const ColoredBox(color: Colors.black);

  void complete() {
    _snapshot = _copySnapshot(isPlaying: false, isCompleted: true);
    notifyListeners();
  }

  void setBuffering(bool isBuffering) {
    _snapshot = _copySnapshot(isBuffering: isBuffering);
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
    await pauseGate?.future;
  }

  @override
  Future<void> play() async {
    await playGate?.future;
    _snapshot = _copySnapshot(isPlaying: true, isCompleted: false);
    notifyListeners();
  }

  @override
  Future<void> setVolume(double volume) async {
    volumeChanges.add(volume);
  }

  @override
  Future<void> seekTo(Duration position) async {
    _snapshot = _copySnapshot(position: position);
    notifyListeners();
  }

  PlaybackSnapshot _copySnapshot({
    bool? isPlaying,
    bool? isBuffering,
    bool? isCompleted,
    Duration? position,
  }) {
    return PlaybackSnapshot(
      isInitialized: _snapshot.isInitialized,
      isPlaying: isPlaying ?? _snapshot.isPlaying,
      isBuffering: isBuffering ?? _snapshot.isBuffering,
      isCompleted: isCompleted ?? _snapshot.isCompleted,
      position: position ?? _snapshot.position,
      duration: _snapshot.duration,
      size: _snapshot.size,
      errorMessage: _snapshot.errorMessage,
    );
  }
}
