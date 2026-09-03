import 'dart:convert';

import 'package:bobo_learning/data/services/app_update_api_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  group('AppUpdateApiService', () {
    test('204 表示当前没有发布升级包', () async {
      final service = AppUpdateApiService(
        client: MockClient((request) async => http.Response('', 204)),
        apiBaseUri: Uri.parse('https://learning.example/api/v1/'),
      );

      expect(await service.fetchLatest(), isNull);
    });

    test('解析强类型中文升级清单', () async {
      final client = MockClient((request) async {
        expect(request.url, Uri.parse('https://learning.example/api/v1/app-updates/latest'));
        return http.Response.bytes(
          utf8.encode(
            jsonEncode({
              'versionName': '0.2.0',
              'versionCode': 2,
              'downloadUrl': '/api/v1/app-updates/packages/bobo-learning-2.apk',
              'sha256': List.filled(64, 'a').join(),
              'sizeBytes': 1024,
              'releaseNotes': ['新增静默升级', '提升播放稳定性'],
              'publishedAt': '2026-09-03T00:00:00Z',
            }),
          ),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      });
      final service = AppUpdateApiService(
        client: client,
        apiBaseUri: Uri.parse('https://learning.example/api/v1/'),
      );

      final result = await service.fetchLatest();

      expect(result?.versionCode, 2);
      expect(result?.releaseNotes.first, '新增静默升级');
    });

    test('非法清单返回明确中文异常', () async {
      final service = AppUpdateApiService(
        client: MockClient((request) async => http.Response('{}', 200)),
        apiBaseUri: Uri.parse('https://learning.example/api/v1/'),
      );

      await expectLater(
        service.fetchLatest(),
        throwsA(
          isA<AppUpdateApiException>().having(
            (error) => error.message,
            '错误信息',
            contains('升级清单解析失败'),
          ),
        ),
      );
    });
  });
}
