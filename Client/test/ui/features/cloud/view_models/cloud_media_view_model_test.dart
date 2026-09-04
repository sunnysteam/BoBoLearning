import 'package:bobo_learning/data/services/cloud_media_api_service.dart';
import 'package:bobo_learning/domain/models/cloud_media_item.dart';
import 'package:bobo_learning/domain/repositories/cloud_media_repository.dart';
import 'package:bobo_learning/ui/features/cloud/view_models/cloud_media_view_model.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('云端内容首次加载成功并保留指定类型', () async {
    final item = _item('2', '照片2.jpg');
    final viewModel = CloudMediaViewModel(
      repository: _FakeRepository(result: [item]),
      kind: CloudMediaKind.photo,
    );

    await viewModel.loadInitial();

    expect(viewModel.state, CloudMediaLoadState.ready);
    expect(viewModel.items, [item]);
    viewModel.dispose();
  });

  test('云端内容加载失败显示后端中文原因', () async {
    final viewModel = CloudMediaViewModel(
      repository: const _FakeRepository(error: CloudMediaApiException('百度网盘授权已失效')),
      kind: CloudMediaKind.video,
    );

    await viewModel.loadInitial();

    expect(viewModel.state, CloudMediaLoadState.error);
    expect(viewModel.errorMessage, '百度网盘授权已失效');
    viewModel.dispose();
  });
}

CloudMediaItem _item(String id, String fileName) {
  return CloudMediaItem(
    id: id,
    fileName: fileName,
    kind: CloudMediaKind.photo,
    sizeBytes: 10,
    modifiedAt: 20,
    thumbnailUri: Uri.parse('https://example.test/thumb/$id'),
    contentUri: Uri.parse('https://example.test/content/$id'),
  );
}

class _FakeRepository implements CloudMediaRepository {
  const _FakeRepository({this.result = const [], this.error});

  final List<CloudMediaItem> result;
  final Object? error;

  @override
  Future<List<CloudMediaItem>> fetchMedia(CloudMediaKind kind) async {
    if (error != null) {
      throw error!;
    }
    return result;
  }
}
