import 'package:bobo_learning/domain/models/video_item.dart';
import 'package:bobo_learning/domain/repositories/video_repository.dart';
import 'package:bobo_learning/ui/core/app_theme.dart';
import 'package:bobo_learning/ui/features/home/view_models/home_view_model.dart';
import 'package:bobo_learning/ui/features/home/views/home_page.dart';
import 'package:bobo_learning/ui/features/player/services/playback_controller.dart';
import 'package:bobo_learning/ui/features/portal/views/portal_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('手机首页完整展示三个童趣分类且没有布局溢出', (tester) async {
    await _setViewSize(tester, const Size(390, 844));
    await tester.pumpWidget(_buildTestApp());

    expect(find.text('菠萝乐园'), findsOneWidget);
    expect(find.byKey(const Key('菠萝首页品牌图标')), findsOneWidget);
    expect(find.text('今天想去哪里玩？'), findsOneWidget);
    expect(find.text('选一个喜欢的小世界，开启今天的快乐发现。'), findsNothing);
    final promptFinder = find.byKey(const Key('菠萝首页主标题'));
    final prompt = tester.widget<Text>(promptFinder);
    final bodyFontSize = Theme.of(tester.element(promptFinder)).textTheme.bodyLarge?.fontSize;
    expect(prompt.style?.fontSize, bodyFontSize);
    expect(find.byKey(const Key('菠萝首页分类-菠萝早教')), findsOneWidget);
    expect(find.byKey(const Key('菠萝首页分类-菠萝视频')), findsOneWidget);
    expect(find.byKey(const Key('菠萝首页分类-菠萝相册')), findsOneWidget);
    expect(find.byKey(const Key('菠萝首页分类图标-菠萝早教')), findsOneWidget);
    expect(find.byKey(const Key('菠萝首页分类图标-菠萝视频')), findsOneWidget);
    expect(find.byKey(const Key('菠萝首页分类图标-菠萝相册')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('点击菠萝早教进入原视频书架并可返回总首页', (tester) async {
    await _setViewSize(tester, const Size(390, 844));
    await tester.pumpWidget(_buildTestApp());

    await tester.tap(find.byKey(const Key('菠萝首页分类-菠萝早教')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('首页滚动区域')), findsOneWidget);
    expect(find.byKey(const Key('菠萝早教返回首页按钮')), findsOneWidget);
    expect(find.byKey(const Key('菠萝早教子页面标题')), findsOneWidget);
    expect(find.byKey(const Key('菠萝早教品牌图标')), findsNothing);
    expect(find.text('发现一个好奇心满满的今天'), findsNothing);

    await tester.tap(find.byKey(const Key('菠萝早教返回首页按钮')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('菠萝首页滚动区域')), findsOneWidget);
    expect(find.text('今天想去哪里玩？'), findsOneWidget);
  });

  testWidgets('菠萝视频入口进入真实内容页面并可返回', (tester) async {
    await _setViewSize(tester, const Size(390, 844));
    await tester.pumpWidget(_buildTestApp());

    final videoEntry = find.byKey(const Key('菠萝首页分类-菠萝视频'));
    await tester.ensureVisible(videoEntry);
    await tester.tap(videoEntry);
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('菠萝视频子页面')), findsOneWidget);
    expect(find.byKey(const Key('菠萝视频子页面标题')), findsOneWidget);
    expect(find.text('菠萝视频'), findsOneWidget);
    expect(find.text('百度网盘视频内容'), findsOneWidget);
    expect(find.byKey(const Key('菠萝视频返回按钮')), findsOneWidget);

    await tester.tap(find.byKey(const Key('菠萝视频返回按钮')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('菠萝首页滚动区域')), findsOneWidget);
  });

  testWidgets('菠萝相册入口进入真实内容页面并可返回', (tester) async {
    await _setViewSize(tester, const Size(390, 844));
    await tester.pumpWidget(_buildTestApp());

    final albumEntry = find.byKey(const Key('菠萝首页分类-菠萝相册'));
    await tester.ensureVisible(albumEntry);
    await tester.tap(albumEntry);
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('菠萝相册子页面')), findsOneWidget);
    expect(find.byKey(const Key('菠萝相册子页面标题')), findsOneWidget);
    expect(find.text('菠萝相册'), findsOneWidget);
    expect(find.text('百度网盘相册内容'), findsOneWidget);
    expect(find.byKey(const Key('菠萝相册返回按钮')), findsOneWidget);

    await tester.tap(find.byKey(const Key('菠萝相册返回按钮')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('菠萝首页滚动区域')), findsOneWidget);
  });

  testWidgets('桌面宽屏三个分类保持同一行并等宽', (tester) async {
    await _setViewSize(tester, const Size(1912, 914));
    await tester.pumpWidget(_buildTestApp());

    final earlyRect = tester.getRect(find.byKey(const Key('菠萝首页分类-菠萝早教')));
    final videoRect = tester.getRect(find.byKey(const Key('菠萝首页分类-菠萝视频')));
    final albumRect = tester.getRect(find.byKey(const Key('菠萝首页分类-菠萝相册')));

    expect(videoRect.top, closeTo(earlyRect.top, 0.1));
    expect(albumRect.top, closeTo(earlyRect.top, 0.1));
    expect(videoRect.width, closeTo(earlyRect.width, 0.1));
    expect(albumRect.width, closeTo(earlyRect.width, 0.1));
    expect(tester.takeException(), isNull);
  });
}

Future<void> _setViewSize(WidgetTester tester, Size size) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

Widget _buildTestApp() {
  return MaterialApp(
    theme: AppTheme.light,
    home: PortalPage(
      earlyLearningPageBuilder: (_) => HomePage(
        showBackButton: true,
        viewModel: HomeViewModel(repository: const _EmptyVideoRepository()),
        playbackControllerFactory: const _UnusedPlaybackControllerFactory(),
      ),
      videoPageBuilder: (_) => const _StubSectionPage(title: '菠萝视频', content: '百度网盘视频内容'),
      albumPageBuilder: (_) => const _StubSectionPage(title: '菠萝相册', content: '百度网盘相册内容'),
    ),
  );
}

class _StubSectionPage extends StatelessWidget {
  const _StubSectionPage({required this.title, required this.content});

  final String title;
  final String content;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      key: Key('$title子页面'),
      appBar: AppBar(
        leading: IconButton(
          key: Key('$title返回按钮'),
          onPressed: () => Navigator.of(context).pop(),
          icon: const Icon(Icons.arrow_back_rounded),
        ),
        title: Text(title, key: Key('$title子页面标题')),
      ),
      body: Center(child: Text(content)),
    );
  }
}

class _EmptyVideoRepository implements VideoRepository {
  const _EmptyVideoRepository();

  @override
  Future<List<VideoItem>> fetchVideos() async => const [];
}

class _UnusedPlaybackControllerFactory implements PlaybackControllerFactory {
  const _UnusedPlaybackControllerFactory();

  @override
  PlaybackController create(Uri streamUri, {Uri? hlsUri}) {
    throw StateError('本测试不应创建播放器');
  }
}
