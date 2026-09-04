import 'dart:convert';

import 'package:bobo_learning/config/app_config.dart';
import 'package:bobo_learning/data/repositories/cloud_media_repository_impl.dart';
import 'package:bobo_learning/data/services/cloud_media_api_service.dart';
import 'package:bobo_learning/domain/models/cloud_media_item.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  test('百度媒体仓储按文件名倒序并解析为本站同源地址', () async {
    final client = MockClient((request) async {
      expect(request.url.toString(), 'https://example.test/server/api/v1/cloud/videos');
      return http.Response.bytes(
        utf8.encode('''
          {"items":[
            {"id":"1","title":"A.mp4","fileName":"A.mp4","kind":"video","sizeBytes":10,"modifiedAt":20,"thumbnailUrl":"/api/v1/cloud/media/1/thumbnail","contentUrl":"/api/v1/cloud/media/1/content"},
            {"id":"2","title":"C.mp4","fileName":"C.mp4","kind":"video","sizeBytes":30,"modifiedAt":40,"thumbnailUrl":"/api/v1/cloud/media/2/thumbnail","contentUrl":"/api/v1/cloud/media/2/content"}
          ]}
        '''),
        200,
        headers: {'content-type': 'application/json; charset=utf-8'},
      );
    });
    final config = AppConfig.fromApiServerUrl('https://example.test/server/');
    final repository = CloudMediaRepositoryImpl(
      apiService: CloudMediaApiService(client: client, apiBaseUri: config.apiBaseUri),
      config: config,
    );

    final items = await repository.fetchMedia(CloudMediaKind.video);

    expect(items.map((item) => item.fileName), ['C.mp4', 'A.mp4']);
    expect(
      items.first.contentUri.toString(),
      'https://example.test/server/api/v1/cloud/media/2/content',
    );
  });

  test('百度媒体接口优先展示后端中文错误', () async {
    final client = MockClient(
      (_) async => http.Response(
        '{"error":{"code":"baidu_unauthorized","message":"百度网盘授权已失效，请重新授权"}}',
        503,
        headers: {'content-type': 'application/json; charset=utf-8'},
      ),
    );
    final service = CloudMediaApiService(
      client: client,
      apiBaseUri: Uri.parse('https://example.test/api/v1/'),
    );

    expect(
      () => service.fetchMedia(CloudMediaKind.photo),
      throwsA(
        isA<CloudMediaApiException>().having((error) => error.message, '中文消息', '百度网盘授权已失效，请重新授权'),
      ),
    );
  });
}
