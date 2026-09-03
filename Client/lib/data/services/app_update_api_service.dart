import 'dart:async';
import 'dart:convert';

import 'package:bobo_learning/data/models/app_update_api_model.dart';
import 'package:http/http.dart' as http;

class AppUpdateApiException implements Exception {
  const AppUpdateApiException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// 只负责访问升级清单接口，不处理版本比较或下载。
class AppUpdateApiService {
  const AppUpdateApiService({required this.client, required this.apiBaseUri});

  final http.Client client;
  final Uri apiBaseUri;

  Future<AppUpdateApiModel?> fetchLatest() async {
    try {
      final response = await client
          .get(
            apiBaseUri.resolve('app-updates/latest'),
            headers: const {'Accept': 'application/json'},
          )
          .timeout(const Duration(seconds: 8));
      if (response.statusCode == 204) {
        return null;
      }
      if (response.statusCode != 200) {
        throw AppUpdateApiException(_extractErrorMessage(response));
      }

      final decoded = jsonDecode(utf8.decode(response.bodyBytes));
      if (decoded is! Map<String, Object?>) {
        throw const AppUpdateApiException('升级清单格式不正确');
      }
      return AppUpdateApiModel.fromJson(decoded);
    } on TimeoutException {
      throw const AppUpdateApiException('检查更新超时，将在稍后自动重试');
    } on http.ClientException {
      throw const AppUpdateApiException('暂时无法连接升级服务，将在稍后自动重试');
    } on FormatException catch (error) {
      throw AppUpdateApiException('升级清单解析失败：${error.message}');
    }
  }

  String _extractErrorMessage(http.Response response) {
    try {
      final decoded = jsonDecode(utf8.decode(response.bodyBytes));
      if (decoded is Map<String, Object?>) {
        final error = decoded['error'];
        if (error is Map<String, Object?> && error['message'] is String) {
          return error['message']! as String;
        }
      }
    } on FormatException {
      // 非 JSON 错误响应统一映射为稳定的中文提示。
    }
    return '升级服务返回异常状态：${response.statusCode}';
  }
}
