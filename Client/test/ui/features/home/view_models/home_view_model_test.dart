import 'package:bobo_learning/data/services/video_api_service.dart';
import 'package:bobo_learning/domain/models/video_item.dart';
import 'package:bobo_learning/domain/repositories/video_repository.dart';
import 'package:bobo_learning/ui/features/home/view_models/home_view_model.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('HomeViewModel', () {
    test('初次加载成功后进入就绪状态', () async {
      final repository = _FakeVideoRepository()..result = [_video('1')];
      final viewModel = HomeViewModel(repository: repository);

      await viewModel.loadInitial();

      expect(viewModel.state, HomeLoadState.ready);
      expect(viewModel.items.single.title, '视频 1');
      expect(viewModel.errorMessage, isNull);
    });

    test('按文件夹形成分区并将根目录视频归入未分类', () async {
      final repository = _FakeVideoRepository()
        ..result = [
          _video('1', folderPath: ''),
          _video('2', folderPath: 'JYT'),
          _video('3', folderPath: 'JYT'),
          _video('4', folderPath: '启蒙/英语'),
        ];
      final viewModel = HomeViewModel(repository: repository);

      await viewModel.loadInitial();

      expect(viewModel.groups.map((group) => group.displayName), ['未分类', 'JYT', '启蒙/英语']);
      expect(viewModel.groups.map((group) => group.items.length), [1, 2, 1]);
    });

    test('空目录进入空状态', () async {
      final viewModel = HomeViewModel(repository: _FakeVideoRepository());

      await viewModel.loadInitial();

      expect(viewModel.state, HomeLoadState.empty);
      expect(viewModel.items, isEmpty);
    });

    test('静默刷新失败时保留已有内容', () async {
      final repository = _FakeVideoRepository()..result = [_video('1')];
      final viewModel = HomeViewModel(repository: repository);
      await viewModel.loadInitial();
      repository.error = const VideoApiException('网络暂时不可用');

      await viewModel.refresh(silent: true);

      expect(viewModel.state, HomeLoadState.ready);
      expect(viewModel.items.single.id, '1');
      expect(viewModel.transientMessage, contains('已保留当前内容'));
      expect(viewModel.isRefreshing, isFalse);
    });

    test('初次加载失败时进入错误状态', () async {
      final repository = _FakeVideoRepository()..error = const VideoApiException('服务暂时不可用');
      final viewModel = HomeViewModel(repository: repository);

      await viewModel.loadInitial();

      expect(viewModel.state, HomeLoadState.error);
      expect(viewModel.errorMessage, '服务暂时不可用');
    });
  });
}

VideoItem _video(String id, {String folderPath = ''}) {
  return VideoItem(
    id: id,
    title: '视频 $id',
    folderPath: folderPath,
    coverUri: Uri.parse('https://example.com/$id.jpg'),
    streamUri: Uri.parse('https://example.com/$id.mp4'),
  );
}

class _FakeVideoRepository implements VideoRepository {
  List<VideoItem> result = const [];
  Object? error;

  @override
  Future<List<VideoItem>> fetchVideos() async {
    final currentError = error;
    if (currentError != null) {
      throw currentError;
    }
    return result;
  }
}
