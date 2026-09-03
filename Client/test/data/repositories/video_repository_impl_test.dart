import 'dart:convert';

import 'package:bobo_learning/config/app_config.dart';
import 'package:bobo_learning/data/repositories/video_repository_impl.dart';
import 'package:bobo_learning/data/services/video_api_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  test('Repository 将相对资源地址解析为同源完整地址', () async {
    final client = MockClient((request) async {
      return http.Response(
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
        200,
        headers: {'content-type': 'application/json; charset=utf-8'},
      );
    });
    final config = AppConfig(apiBaseUri: Uri.parse('https://learning.example/server/api/v1/'));
    final repository = VideoRepositoryImpl(
      apiService: VideoApiService(client: client, apiBaseUri: config.apiBaseUri),
      config: config,
    );

    final result = await repository.fetchVideos();

    expect(
      result.single.coverUri,
      Uri.parse('https://learning.example/server/api/v1/videos/1/cover'),
    );
    expect(
      result.single.streamUri,
      Uri.parse('https://learning.example/server/api/v1/videos/1/stream'),
    );
    expect(result.single.folderPath, '颜色启蒙');
  });
}
