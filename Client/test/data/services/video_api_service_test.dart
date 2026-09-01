import 'dart:convert';

import 'package:bobo_learning/data/services/video_api_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  group('VideoApiService', () {
    test('请求视频列表并解析 UTF-8 中文内容', () async {
      final client = MockClient((request) async {
        expect(request.method, 'GET');
        expect(request.url, Uri.parse('https://example.com/api/v1/videos'));
        return http.Response.bytes(
          utf8.encode(
            jsonEncode({
              'items': [
                {
                  'id': '1',
                  'title': '认识颜色',
                  'folderPath': '颜色启蒙',
                  'coverUrl': '/api/v1/videos/1/cover',
                  'streamUrl': '/api/v1/videos/1/stream',
                },
              ],
            }),
          ),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      });
      final service = VideoApiService(
        client: client,
        apiBaseUri: Uri.parse('https://example.com/api/v1/'),
      );

      final result = await service.fetchVideos();

      expect(result.single.title, '认识颜色');
      expect(result.single.folderPath, '颜色启蒙');
    });

    test('优先展示后端返回的中文错误', () async {
      final client = MockClient((request) async {
        return http.Response(
          jsonEncode({
            'error': {'code': 'service_busy', 'message': '视频服务正在休息'},
          }),
          503,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      });
      final service = VideoApiService(
        client: client,
        apiBaseUri: Uri.parse('https://example.com/api/v1/'),
      );

      await expectLater(
        service.fetchVideos(),
        throwsA(isA<VideoApiException>().having((error) => error.message, '错误信息', '视频服务正在休息')),
      );
    });
  });
}
