/// 客户端运行配置。
class AppConfig {
  const AppConfig({required this.apiBaseUri});

  factory AppConfig.fromEnvironment() {
    const configuredBaseUrl = String.fromEnvironment('API_BASE_URL');
    final apiServerUrl = configuredBaseUrl.trim().isEmpty ? defaultApiServerUrl : configuredBaseUrl;
    return AppConfig.fromApiServerUrl(apiServerUrl);
  }

  factory AppConfig.fromApiServerUrl(String value) {
    return AppConfig(apiBaseUri: _normalizeApiBase(value));
  }

  static const defaultApiServerUrl = 'https://wx.jiayuntong.com:5172/server/';

  final Uri apiBaseUri;

  Uri resolveResource(String value) {
    final parsed = Uri.tryParse(value);
    if (parsed == null) {
      throw const FormatException('资源地址格式不正确');
    }
    if (parsed.hasScheme) {
      return parsed;
    }
    if (parsed.path.startsWith(_versionedApiRootPath)) {
      final relative = parsed.replace(path: parsed.path.substring(_versionedApiRootPath.length));
      return apiBaseUri.resolveUri(relative);
    }
    return apiBaseUri.resolve(value);
  }

  static const _versionedApiRootPath = '/api/v1/';

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
