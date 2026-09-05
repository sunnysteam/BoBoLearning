import 'dart:async';
import 'dart:ui' as ui;

import 'package:bobo_learning/domain/models/cloud_media_item.dart';
import 'package:bobo_learning/ui/core/app_theme.dart';
import 'package:bobo_learning/ui/features/cloud/views/photo_viewer_page.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late ui.Image image;

  setUp(() async {
    image = await createTestImage(width: 120, height: 160);
  });

  tearDown(() {
    PaintingBinding.instance.imageCache.clear();
    PaintingBinding.instance.imageCache.clearLiveImages();
    image.dispose();
  });

  List<CloudMediaItem> photos() => List.generate(
    3,
    (index) => CloudMediaItem(
      id: '$index',
      fileName: '照片$index.jpg',
      kind: CloudMediaKind.photo,
      sizeBytes: 100,
      modifiedAt: 0,
      thumbnailUri: Uri.parse('https://test.invalid/thumb/$index'),
      contentUri: Uri.parse('https://test.invalid/photo/$index'),
    ),
  );

  Future<void> open(
    WidgetTester tester,
    _Images images, {
    Size size = const Size(390, 844),
    int initialIndex = 0,
    List<CloudMediaItem>? items,
    double textScale = 1,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(textScale)),
          child: child!,
        ),
        home: PhotoViewerPage(
          items: items ?? photos(),
          initialIndex: initialIndex,
          desktopNavigationEnabled: true,
          imageProvider: images.provider,
        ),
      ),
    );
    await tester.pump();
  }

  String currentFile(WidgetTester tester) =>
      tester.widget<Text>(find.byKey(const Key('照片文件名'))).data!;

  testWidgets('从选中项开始，手机左滑下一张、右滑上一张且首尾不循环', (tester) async {
    await open(tester, _Images(image), initialIndex: 1);
    await tester.pumpAndSettle();
    expect(currentFile(tester), '照片1.jpg');
    expect(find.text('2 / 3'), findsOneWidget);
    expect(find.text('左右滑动切换 · 双击放大'), findsOneWidget);
    expect(find.byKey(const Key('下一张照片按钮')), findsNothing);

    await tester.drag(find.byKey(const Key('照片手势-1')), const Offset(-280, 0));
    await tester.pumpAndSettle();
    expect(currentFile(tester), '照片2.jpg');
    await tester.drag(find.byKey(const Key('照片手势-2')), const Offset(-280, 0));
    await tester.pumpAndSettle();
    expect(currentFile(tester), '照片2.jpg');

    await tester.drag(find.byKey(const Key('照片手势-2')), const Offset(280, 0));
    await tester.pumpAndSettle();
    expect(currentFile(tester), '照片1.jpg');
    await tester.drag(find.byKey(const Key('照片手势-1')), const Offset(280, 0));
    await tester.pumpAndSettle();
    expect(currentFile(tester), '照片0.jpg');
    await tester.drag(find.byKey(const Key('照片手势-0')), const Offset(280, 0));
    await tester.pumpAndSettle();
    expect(currentFile(tester), '照片0.jpg');
    expect(tester.takeException(), isNull);
  });

  testWidgets('上下滑动和上下方向键不切换照片', (tester) async {
    await open(tester, _Images(image), initialIndex: 1);
    await tester.pumpAndSettle();
    final gesture = find.byKey(const Key('照片手势-1'));
    await tester.drag(gesture, const Offset(0, -520));
    await tester.pumpAndSettle();
    expect(currentFile(tester), '照片1.jpg');
    await tester.drag(gesture, const Offset(0, 520));
    await tester.pumpAndSettle();
    expect(currentFile(tester), '照片1.jpg');
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.pumpAndSettle();
    expect(currentFile(tester), '照片1.jpg');
  });

  testWidgets('桌面左右按钮和方向键按照相册边界切换', (tester) async {
    await open(tester, _Images(image), size: const Size(1912, 914));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('上一张照片按钮')), findsNothing);
    await tester.tap(find.byKey(const Key('下一张照片按钮')));
    await tester.pumpAndSettle();
    expect(currentFile(tester), '照片1.jpg');
    expect(find.byKey(const Key('上一张照片按钮')), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pumpAndSettle();
    expect(currentFile(tester), '照片2.jpg');
    expect(find.byKey(const Key('下一张照片按钮')), findsNothing);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.pumpAndSettle();
    expect(currentFile(tester), '照片1.jpg');
  });

  testWidgets('双击放大后的拖动不切页，还原后恢复左右滑', (tester) async {
    await open(tester, _Images(image));
    await tester.pumpAndSettle();
    final gesture = find.byKey(const Key('照片手势-0'));
    await tester.tap(gesture);
    await tester.pump(const Duration(milliseconds: 80));
    await tester.tap(gesture);
    await tester.pumpAndSettle();
    expect(find.text('拖动查看细节 · 双击还原'), findsOneWidget);
    await tester.drag(gesture, const Offset(-280, 0));
    await tester.pumpAndSettle();
    expect(currentFile(tester), '照片0.jpg');
    await tester.tap(gesture);
    await tester.pump(const Duration(milliseconds: 80));
    await tester.tap(gesture);
    await tester.pumpAndSettle();
    await tester.drag(gesture, const Offset(-280, 0));
    await tester.pumpAndSettle();
    expect(currentFile(tester), '照片1.jpg');
  });

  testWidgets('原图等待时保持缩略图，解码完成后渐入并仅预取下一张', (tester) async {
    final gate = Completer<ImageInfo>();
    final images = _Images(image)..responses['/photo/0'] = () => gate.future;
    await open(tester, images);
    expect(find.byKey(const Key('照片预览-0')), findsOneWidget);
    expect(find.text('正在加载清晰照片…'), findsOneWidget);
    expect(images.loads('/photo/1'), 0);
    expect(tester.widget<AnimatedOpacity>(find.byKey(const Key('原图渐入-0'))).opacity, 0);

    gate.complete(ImageInfo(image: image.clone()));
    await tester.pump();
    await tester.pump();
    expect(tester.widget<AnimatedOpacity>(find.byKey(const Key('原图渐入-0'))).opacity, 1);
    await tester.pumpAndSettle();
    expect(find.text('正在加载清晰照片…'), findsNothing);
    expect(images.loads('/photo/1'), 1);
    expect(images.loads('/photo/2'), 0);
  });

  testWidgets('原图加载失败保留预览并可在当前页重试', (tester) async {
    var attempt = 0;
    final images = _Images(image)
      ..responses['/photo/0'] = () => ++attempt == 1
          ? Future<ImageInfo>.error(StateError('测试图片加载失败'))
          : SynchronousFuture(ImageInfo(image: image.clone()));
    await open(tester, images);
    await tester.pumpAndSettle();
    expect(find.text('清晰照片加载失败'), findsOneWidget);
    expect(find.byKey(const Key('照片预览-0')), findsOneWidget);
    await tester.tap(find.byKey(const Key('重试照片-0')));
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pumpAndSettle();
    expect(find.text('清晰照片加载失败'), findsNothing);
    expect(attempt, 2);
    expect(currentFile(tester), '照片0.jpg');
  });

  testWidgets('慢加载和超时有反馈，切页后旧请求完成不会覆盖当前项', (tester) async {
    final gate = Completer<ImageInfo>();
    final images = _Images(image)..responses['/photo/0'] = () => gate.future;
    await open(tester, images);
    await tester.pump(const Duration(seconds: 8));
    expect(find.text('网络有点慢，照片还在加载'), findsOneWidget);
    await tester.pump(const Duration(seconds: 22));
    expect(find.text('清晰照片加载失败'), findsOneWidget);
    await tester.drag(find.byKey(const Key('照片手势-0')), const Offset(-280, 0));
    await tester.pumpAndSettle();
    gate.complete(ImageInfo(image: image.clone()));
    await tester.pumpAndSettle();
    expect(currentFile(tester), '照片1.jpg');
    expect(tester.takeException(), isNull);
  });

  testWidgets('连续横向触屏拖动能切页，不被图片缩放识别器拦截', (tester) async {
    await open(tester, _Images(image));
    await tester.pumpAndSettle();
    final touch = await tester.startGesture(const Offset(340, 420));
    for (var step = 1; step <= 12; step++) {
      await touch.moveTo(Offset(340 - step * 24, 420));
      await tester.pump(const Duration(milliseconds: 35));
    }
    await touch.up();
    await tester.pumpAndSettle();
    expect(currentFile(tester), '照片1.jpg');
  });

  testWidgets('双指缩放不会触发相邻照片切换', (tester) async {
    await open(tester, _Images(image), initialIndex: 1);
    await tester.pumpAndSettle();
    final gesture = find.byKey(const Key('照片手势-1'));
    final center = tester.getCenter(gesture);
    final first = await tester.startGesture(center - const Offset(40, 0), pointer: 1);
    final second = await tester.startGesture(center + const Offset(40, 0), pointer: 2);
    await tester.pump();
    await first.moveTo(center - const Offset(60, 0));
    await second.moveTo(center + const Offset(60, 0));
    await tester.pump();
    await first.moveTo(center - const Offset(100, 0));
    await second.moveTo(center + const Offset(100, 0));
    await tester.pump();
    await first.up();
    await second.up();
    await tester.pumpAndSettle();
    expect(currentFile(tester), '照片1.jpg');
    expect(find.text('拖动查看细节 · 双击还原'), findsOneWidget);
    await tester.drag(gesture, const Offset(-280, 0));
    await tester.pumpAndSettle();
    expect(currentFile(tester), '照片1.jpg');
    await tester.tap(gesture);
    await tester.pump(const Duration(milliseconds: 80));
    await tester.tap(gesture);
    await tester.pumpAndSettle();
    await tester.drag(gesture, const Offset(-280, 0));
    await tester.pumpAndSettle();
    expect(currentFile(tester), '照片2.jpg');
  });

  testWidgets('双指未缩放就抬起或取消后恢复左右翻页', (tester) async {
    await open(tester, _Images(image));
    await tester.pumpAndSettle();
    final first = await tester.startGesture(const Offset(150, 420), pointer: 1);
    final second = await tester.startGesture(const Offset(240, 420), pointer: 2);
    await tester.pump();
    await first.up();
    await second.cancel();
    await tester.pumpAndSettle();
    await tester.drag(find.byKey(const Key('照片手势-0')), const Offset(-280, 0));
    await tester.pumpAndSettle();
    expect(currentFile(tester), '照片1.jpg');
  });

  testWidgets('单张照片和窄屏大字体无溢出且没有切换按钮', (tester) async {
    await open(
      tester,
      _Images(image),
      size: const Size(320, 600),
      items: [photos()[0]],
      textScale: 1.8,
    );
    await tester.pumpAndSettle();
    expect(find.text('1 / 1'), findsOneWidget);
    expect(find.byKey(const Key('上一张照片按钮')), findsNothing);
    expect(find.byKey(const Key('下一张照片按钮')), findsNothing);
    expect(tester.takeException(), isNull);
  });
}

/// 用可控制的图片解码结果测试等待、失败与恢复，不依赖真实网络。
class _Images {
  _Images(this.image);
  final ui.Image image;
  final Map<String, Future<ImageInfo> Function()> responses = {};
  final Map<String, _TestImageProvider> _providers = {};

  ImageProvider<Object> provider(Uri uri) => _providers.putIfAbsent(
    uri.path,
    () => _TestImageProvider(
      () => responses[uri.path]?.call() ?? SynchronousFuture(ImageInfo(image: image.clone())),
    ),
  );

  int loads(String path) => _providers[path]?.loads ?? 0;
}

class _TestImageProvider extends ImageProvider<_TestImageProvider> {
  _TestImageProvider(this.response);
  final Future<ImageInfo> Function() response;
  int loads = 0;

  @override
  Future<_TestImageProvider> obtainKey(ImageConfiguration configuration) => SynchronousFuture(this);

  @override
  ImageStreamCompleter loadImage(_TestImageProvider key, ImageDecoderCallback decode) {
    loads++;
    return OneFrameImageStreamCompleter(response());
  }
}
