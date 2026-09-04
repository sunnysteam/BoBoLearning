import 'dart:async';
import 'dart:convert';

import 'package:bobo_learning/data/models/cloud_media_api_model.dart';
import 'package:bobo_learning/domain/models/cloud_media_item.dart';
import 'package:http/http.dart' as http;

/// 百度网盘内容接口调用失败。
class CloudMediaApiException implements Exception {
  const CloudMediaApiException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// 后端百度网盘只读 HTTP 服务。
class CloudMediaApiService {
  const CloudMediaApiService({required this.client, required this.apiBaseUri});

  final http.Client client;
  final Uri apiBaseUri;

  Future<List<CloudMediaApiModel>> fetchMedia(CloudMediaKind kind) async {
    final path = kind == CloudMediaKind.video ? 'cloud/videos' : 'cloud/photos';
    try {
      final response = await client
          .get(apiBaseUri.resolve(path))
          .timeout(const Duration(seconds: 15));
      if (response.statusCode != 200) {
        throw CloudMediaApiException(_extractErrorMessage(response));
      }

      final Object? decoded = jsonDecode(utf8.decode(response.bodyBytes));
      if (decoded is! Map<String, dynamic>) {
        throw const CloudMediaApiException('云端内容列表格式不正确');
      }
      final rawItems = decoded['items'];
      if (rawItems is! List<dynamic>) {
        throw const CloudMediaApiException('云端内容列表缺少 items 字段');
      }
      return rawItems
          .map((Object? item) {
            if (item is! Map<String, dynamic>) {
              throw const CloudMediaApiException('云端内容条目格式不正确');
            }
            return CloudMediaApiModel.fromJson(Map<String, Object?>.from(item));
          })
          .toList(growable: false);
    } on TimeoutException {
      throw const CloudMediaApiException('连接百度网盘超时啦，请稍后再试');
    } on http.ClientException {
      throw const CloudMediaApiException('暂时连接不到百度网盘，请稍后再试');
    } on FormatException catch (error) {
      throw CloudMediaApiException('云端内容解析失败：${error.message}');
    }
  }

  String _extractErrorMessage(http.Response response) {
    try {
      final Object? decoded = jsonDecode(utf8.decode(response.bodyBytes));
      if (decoded is Map<String, dynamic>) {
        final error = decoded['error'];
        if (error is Map<String, dynamic>) {
          final message = error['message'];
          if (message is String && message.trim().isNotEmpty) {
            return message;
          }
        }
      }
    } on FormatException {
      // 非 JSON 错误响应使用统一中文提示。
    }
    return '百度网盘服务开小差了（${response.statusCode}）';
  }
}
