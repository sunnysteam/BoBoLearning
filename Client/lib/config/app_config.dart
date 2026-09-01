import 'package:flutter/foundation.dart';

/// 客户端运行配置。
class AppConfig {
  const AppConfig({required this.apiBaseUri});

  factory AppConfig.fromEnvironment() {
    const configuredBaseUrl = String.fromEnvironment('API_BASE_URL');
    if (configuredBaseUrl.trim().isNotEmpty) {
      return AppConfig(apiBaseUri: _normalizeApiBase(configuredBaseUrl));
    }

    if (kIsWeb) {
      return AppConfig(apiBaseUri: Uri.base.resolve('/api/v1/'));
    }

    // Android 模拟器默认通过 10.0.2.2 访问宿主机；真机必须使用 dart-define 指定地址。
    return AppConfig(apiBaseUri: Uri.parse('http://10.0.2.2:8080/api/v1/'));
  }

  final Uri apiBaseUri;

  Uri resolveResource(String value) {
    final parsed = Uri.tryParse(value);
    if (parsed == null) {
      throw const FormatException('资源地址格式不正确');
    }
    if (parsed.hasScheme) {
      return parsed;
    }
    return apiBaseUri.resolve(value);
  }

  static Uri _normalizeApiBase(String value) {
    final uri = Uri.tryParse(value.trim());
    if (uri == null || !uri.hasScheme || uri.host.isEmpty) {
      throw const FormatException('API_BASE_URL 必须是包含协议和主机的完整地址');
    }

    var path = uri.path.replaceAll(RegExp(r'/+$'), '');
    if (!path.endsWith('/api/v1')) {
      path = '$path/api/v1';
    }
    return uri.replace(path: '$path/');
  }
}
