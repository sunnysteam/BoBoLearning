import 'package:bobo_learning/data/models/video_api_model.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('VideoApiModel', () {
    test('可以解析完整的视频条目', () {
      final model = VideoApiModel.fromJson(const {
        'id': 'video-1',
        'title': '认识小动物',
        'folderPath': '动物世界/幼儿班',
        'coverUrl': '/api/v1/videos/video-1/cover',
        'streamUrl': '/api/v1/videos/video-1/stream',
        'hlsUrl': '/api/v1/videos/video-1/hls/v1/index.m3u8',
      });

      expect(model.id, 'video-1');
      expect(model.title, '认识小动物');
      expect(model.folderPath, '动物世界/幼儿班');
      expect(model.coverUrl, '/api/v1/videos/video-1/cover');
      expect(model.streamUrl, '/api/v1/videos/video-1/stream');
      expect(model.hlsUrl, '/api/v1/videos/video-1/hls/v1/index.m3u8');
    });

    test('兼容旧服务缺少文件夹字段', () {
      final model = VideoApiModel.fromJson(const {
        'id': 'video-1',
        'title': '认识小动物',
        'coverUrl': '/cover',
        'streamUrl': '/stream',
      });

      expect(model.folderPath, isEmpty);
      expect(model.hlsUrl, isNull);
    });

    test('字段缺失时给出明确错误', () {
      expect(
        () => VideoApiModel.fromJson(const {
          'id': 'video-1',
          'title': '',
          'coverUrl': '/cover',
          'streamUrl': '/stream',
        }),
        throwsA(isA<FormatException>().having((error) => error.message, '错误信息', contains('title'))),
      );
    });
  });
}
