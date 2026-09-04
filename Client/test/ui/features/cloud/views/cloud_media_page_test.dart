import 'package:bobo_learning/domain/models/cloud_media_item.dart';
import 'package:bobo_learning/domain/repositories/cloud_media_repository.dart';
import 'package:bobo_learning/ui/core/app_theme.dart';
import 'package:bobo_learning/ui/features/cloud/view_models/cloud_media_view_model.dart';
import 'package:bobo_learning/ui/features/cloud/views/cloud_media_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('菠萝相册显示网盘图片并可进入大图页', (tester) async {
    final item = CloudMediaItem(
      id: '123',
      fileName: '快乐时光.jpg',
      kind: CloudMediaKind.photo,
      sizeBytes: 10,
      modifiedAt: 20,
      thumbnailUri: Uri.parse('https://example.invalid/thumb'),
      contentUri: Uri.parse('https://example.invalid/content'),
    );
    final viewModel = CloudMediaViewModel(
      repository: _PhotoRepository(item),
      kind: CloudMediaKind.photo,
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: CloudAlbumPage(viewModel: viewModel),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.byKey(const Key('菠萝相册子页面')), findsOneWidget);
    expect(find.text('快乐时光.jpg'), findsOneWidget);
    expect(find.text('1 项 · 文件名倒序'), findsOneWidget);

    await tester.tap(find.byKey(const Key('相册图片-123')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('相册大图页')), findsOneWidget);

    viewModel.dispose();
  });
}

class _PhotoRepository implements CloudMediaRepository {
  const _PhotoRepository(this.item);

  final CloudMediaItem item;

  @override
  Future<List<CloudMediaItem>> fetchMedia(CloudMediaKind kind) async => [item];
}
