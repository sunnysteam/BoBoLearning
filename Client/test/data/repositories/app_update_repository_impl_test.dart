import 'dart:convert';

import 'package:bobo_learning/config/app_config.dart';
import 'package:bobo_learning/data/repositories/app_update_repository_impl.dart';
import 'package:bobo_learning/data/services/app_update_api_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  final config = AppConfig(apiBaseUri: Uri.parse('https://learning.example/server/api/v1/'));

  AppUpdateRepositoryImpl createRepository() {
    final client = MockClient(
      (request) async => http.Response(
        jsonEncode({
          'versionName': '0.2.0',
          'versionCode': 2,
          'downloadUrl': '/api/v1/app-updates/packages/bobo-learning-2.apk',
          'sha256': List.filled(64, 'a').join(),
          'sizeBytes': 1024,
          'releaseNotes': ['新增静默升级'],
          'publishedAt': '2026-09-03T00:00:00Z',
        }),
        200,
        headers: {'content-type': 'application/json; charset=utf-8'},
      ),
    );
    return AppUpdateRepositoryImpl(
      apiService: AppUpdateApiService(client: client, apiBaseUri: config.apiBaseUri),
      config: config,
    );
  }

  test('更高构建号映射为同源 APK 下载地址', () async {
    final result = await createRepository().findAvailableUpdate(currentVersionCode: 1);

    expect(result?.versionCode, 2);
    expect(
      result?.downloadUri,
      Uri.parse('https://learning.example/server/api/v1/app-updates/packages/bobo-learning-2.apk'),
    );
  });

  test('相同或更低构建号不触发升级', () async {
    expect(await createRepository().findAvailableUpdate(currentVersionCode: 2), isNull);
    expect(await createRepository().findAvailableUpdate(currentVersionCode: 3), isNull);
  });
}
