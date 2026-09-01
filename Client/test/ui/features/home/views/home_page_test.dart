import 'dart:async';

import 'package:bobo_learning/domain/models/video_item.dart';
import 'package:bobo_learning/domain/repositories/video_repository.dart';
import 'package:bobo_learning/ui/core/app_theme.dart';
import 'package:bobo_learning/ui/features/home/view_models/home_view_model.dart';
import 'package:bobo_learning/ui/features/home/views/home_page.dart';
import 'package:bobo_learning/ui/features/player/services/playback_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('首次加载期间展示文件夹书架骨架屏', (tester) async {
    final repository = _DeferredVideoRepository();
    final viewModel = HomeViewModel(repository: repository);

    await tester.pumpWidget(_TestApp(viewModel: viewModel));
    await tester.pump();

    expect(find.byKey(const Key('分类骨架屏')), findsOneWidget);
    expect(find.byKey(const Key('分类骨架分区-0')), findsOneWidget);
    expect(find.byKey(const Key('骨架视频卡片-0-0')), findsOneWidget);

    repository.complete([_video('1', '第一课', folderPath: 'JYT')]);
    await tester.pump();
    await tester.pump();

    expect(find.byKey(const Key('分类骨架屏')), findsNothing);
    expect(find.text('JYT'), findsOneWidget);
  });

  testWidgets('首页用块状封面展示视频', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final viewModel = HomeViewModel(
      repository: _FixedVideoRepository([
        _video('1', '认识小动物', folderPath: 'JYT'),
        _video('2', '快乐学数字', folderPath: 'JYT'),
        _video('3', '英语单词', folderPath: 'test'),
      ]),
    );
    await viewModel.loadInitial();

    await tester.pumpWidget(_TestApp(viewModel: viewModel));
    await tester.pump();

    expect(find.text('菠萝早教'), findsOneWidget);
    expect(find.byKey(const Key('菠萝早教品牌图标')), findsOneWidget);
    expect(find.text('3 个快乐视频'), findsOneWidget);
    expect(find.text('JYT'), findsOneWidget);
    expect(find.text('test'), findsOneWidget);
    expect(find.text('2 个视频'), findsOneWidget);
    expect(find.text('1 个视频'), findsOneWidget);
    expect(find.text('认识小动物'), findsOneWidget);
    expect(find.text('快乐学数字'), findsOneWidget);
    expect(find.byKey(const Key('视频卡片-1')), findsOneWidget);
    expect(find.byKey(const Key('小屏顶部操作区')), findsOneWidget);
  });

  testWidgets('小屏首页使用紧凑统计栏并将分类数量放到名称下方', (tester) async {
    const folderName = '佩奇教你说英语 幼儿早教英语启蒙动画（全23集）【中英双语】';
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final viewModel = HomeViewModel(
      repository: _FixedVideoRepository([_video('1', '第一课', folderPath: folderName)]),
    );
    await viewModel.loadInitial();

    await tester.pumpWidget(_TestApp(viewModel: viewModel));
    await tester.pump();

    expect(find.byKey(const Key('小屏顶部操作区')), findsOneWidget);
    final refreshSize = tester.getSize(find.byKey(const Key('首页刷新按钮')));
    expect(refreshSize.width, greaterThanOrEqualTo(56));
    expect(refreshSize.height, greaterThanOrEqualTo(56));

    final titleRect = tester.getRect(find.byKey(const Key('分类名称-$folderName')));
    final countRect = tester.getRect(find.byKey(const Key('分类数量-$folderName')));
    expect(countRect.top, greaterThan(titleRect.bottom));
    expect(tester.takeException(), isNull);
  });

  testWidgets('点击卡片后播放器只包含当前文件夹的视频', (tester) async {
    final factory = _RecordingPlaybackControllerFactory();
    final viewModel = HomeViewModel(
      repository: _FixedVideoRepository([
        _video('1', 'JYT 第一课', folderPath: 'JYT'),
        _video('2', 'JYT 第二课', folderPath: 'JYT'),
        _video('3', '测试视频', folderPath: 'test'),
      ]),
    );
    await viewModel.loadInitial();

    await tester.pumpWidget(_TestApp(viewModel: viewModel, factory: factory));
    await tester.tap(find.byKey(const Key('视频卡片-1')));
    await tester.pump();
    await tester.pump();

    expect(find.text('1 / 2'), findsOneWidget);
    expect(factory.createdUris, isNotEmpty);
    expect(factory.createdUris.every((uri) => uri.path.contains('/JYT/')), isTrue);
  });

  testWidgets('文件夹不超过四个视频时全部放入横向书架且不显示查看更多', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final viewModel = HomeViewModel(
      repository: _FixedVideoRepository([
        for (var index = 1; index <= 4; index++) _video('$index', '第 $index 课', folderPath: 'JYT'),
      ]),
    );
    await viewModel.loadInitial();
    await tester.pumpWidget(_TestApp(viewModel: viewModel));

    final strip = find.byKey(const Key('分类横向书架-JYT'));
    expect(strip, findsOneWidget);
    expect(find.byKey(const Key('查看更多-JYT')), findsNothing);

    await tester.drag(strip, const Offset(-900, 0));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('视频卡片-4')), findsOneWidget);
  });

  testWidgets('超过四个视频时第五位进入完整文件夹页面并可返回', (tester) async {
    const folderName = '佩奇教你说英语 幼儿早教英语启蒙动画（全23集）【中英双语】';
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final viewModel = HomeViewModel(
      repository: _FixedVideoRepository([
        for (var index = 1; index <= 5; index++)
          _video('$index', '第 $index 课', folderPath: folderName),
      ]),
    );
    await viewModel.loadInitial();
    await tester.pumpWidget(_TestApp(viewModel: viewModel));

    final strip = find.byKey(const Key('分类横向书架-$folderName'));
    await tester.drag(strip, const Offset(-900, 0));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('查看更多-$folderName')), findsOneWidget);
    expect(find.text('还有 1 个视频'), findsOneWidget);
    expect(find.byKey(const Key('视频卡片-5')), findsNothing);

    await tester.tap(find.byKey(const Key('查看更多-$folderName')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('文件夹详情页')), findsOneWidget);
    expect(find.byKey(const Key('文件夹详情返回按钮')), findsOneWidget);
    expect(find.byKey(const Key('文件夹详情标题')), findsOneWidget);
    expect(find.text(folderName), findsWidgets);
    final detailTitle = tester.widget<Text>(find.byKey(const Key('文件夹详情标题')));
    expect(detailTitle.maxLines, isNull);
    expect(find.byType(SliverGrid), findsOneWidget);

    final detailScroll = find.descendant(
      of: find.byKey(const Key('文件夹详情滚动区域')),
      matching: find.byType(Scrollable),
    );
    await tester.scrollUntilVisible(find.byKey(const Key('视频卡片-5')), 420, scrollable: detailScroll);
    expect(find.byKey(const Key('视频卡片-5')), findsOneWidget);

    await tester.drag(detailScroll, const Offset(0, 1200));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('文件夹详情返回按钮')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('文件夹详情页')), findsNothing);
    expect(find.text('菠萝早教'), findsOneWidget);
  });

  testWidgets('空目录展示资源投放引导', (tester) async {
    final viewModel = HomeViewModel(repository: const _FixedVideoRepository([]));
    await viewModel.loadInitial();

    await tester.pumpWidget(_TestApp(viewModel: viewModel));
    await tester.pump();

    expect(find.text('故事正在赶来的路上'), findsOneWidget);
    expect(find.textContaining('同名封面'), findsOneWidget);
  });
}

VideoItem _video(String id, String title, {String folderPath = ''}) {
  return VideoItem(
    id: id,
    title: title,
    folderPath: folderPath,
    coverUri: Uri.parse('https://invalid.example/$folderPath/$id.jpg'),
    streamUri: Uri.parse('https://invalid.example/$folderPath/$id.mp4'),
  );
}

class _TestApp extends StatelessWidget {
  const _TestApp({
    required this.viewModel,
    this.factory = const _UnusedPlaybackControllerFactory(),
  });

  final HomeViewModel viewModel;
  final PlaybackControllerFactory factory;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      theme: AppTheme.light,
      home: HomePage(viewModel: viewModel, playbackControllerFactory: factory),
    );
  }
}

class _FixedVideoRepository implements VideoRepository {
  const _FixedVideoRepository(this.items);

  final List<VideoItem> items;

  @override
  Future<List<VideoItem>> fetchVideos() async => items;
}

class _DeferredVideoRepository implements VideoRepository {
  final Completer<List<VideoItem>> _completer = Completer<List<VideoItem>>();

  void complete(List<VideoItem> items) => _completer.complete(items);

  @override
  Future<List<VideoItem>> fetchVideos() => _completer.future;
}

class _UnusedPlaybackControllerFactory implements PlaybackControllerFactory {
  const _UnusedPlaybackControllerFactory();

  @override
  PlaybackController create(Uri streamUri) {
    throw StateError('本测试不应创建播放器');
  }
}

class _RecordingPlaybackControllerFactory implements PlaybackControllerFactory {
  final List<Uri> createdUris = [];

  @override
  PlaybackController create(Uri streamUri) {
    createdUris.add(streamUri);
    return _ReadyPlaybackController();
  }
}

class _ReadyPlaybackController extends PlaybackController {
  PlaybackSnapshot _snapshot = const PlaybackSnapshot.loading();

  @override
  PlaybackSnapshot get snapshot => _snapshot;

  @override
  Widget buildVideo() => const ColoredBox(color: Colors.black);

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
  Future<void> pause() async {}

  @override
  Future<void> play() async {
    _snapshot = PlaybackSnapshot(
      isInitialized: _snapshot.isInitialized,
      isPlaying: true,
      isBuffering: false,
      isCompleted: false,
      position: _snapshot.position,
      duration: _snapshot.duration,
      size: _snapshot.size,
    );
    notifyListeners();
  }

  @override
  Future<void> seekTo(Duration position) async {}
}
