import 'dart:async';
import 'dart:convert';

import 'package:bobo_learning/data/models/video_api_model.dart';
import 'package:http/http.dart' as http;

/// 后端接口调用失败。
class VideoApiException implements Exception {
  const VideoApiException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// 视频目录 HTTP 服务。
class VideoApiService {
  const VideoApiService({required this._client, required this._apiBaseUri});

  final http.Client _client;
  final Uri _apiBaseUri;

  Future<List<VideoApiModel>> fetchVideos() async {
    try {
      final response = await _client
          .get(_apiBaseUri.resolve('videos'))
          .timeout(const Duration(seconds: 12));
      if (response.statusCode != 200) {
        throw VideoApiException(_extractErrorMessage(response));
      }

      final Object? decoded = jsonDecode(utf8.decode(response.bodyBytes));
      if (decoded is! Map<String, dynamic>) {
        throw const VideoApiException('视频列表格式不正确');
      }
      final map = Map<String, Object?>.from(decoded);
      final rawItems = map['items'];
      if (rawItems is! List<dynamic>) {
        throw const VideoApiException('视频列表缺少 items 字段');
      }

      return rawItems
          .map((Object? item) {
            if (item is! Map<String, dynamic>) {
              throw const VideoApiException('视频条目格式不正确');
            }
            return VideoApiModel.fromJson(Map<String, Object?>.from(item));
          })
          .toList(growable: false);
    } on TimeoutException {
      throw const VideoApiException('连接超时啦，请检查网络后再试');
    } on http.ClientException {
      throw const VideoApiException('暂时连接不到视频服务，请稍后再试');
    } on FormatException catch (error) {
      throw VideoApiException('视频数据解析失败：${error.message}');
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
    return '视频服务开小差了（${response.statusCode}）';
  }
}
