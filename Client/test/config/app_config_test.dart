import 'package:bobo_learning/config/app_config.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('APK 与 Web 默认使用正式服务入口', () {
    final config = AppConfig.fromEnvironment();

    expect(config.apiBaseUri, Uri.parse('https://wx.jiayuntong.com:5172/server/api/v1/'));
  });

  test('服务根地址会自动补齐版本化接口路径', () {
    final config = AppConfig.fromApiServerUrl('https://wx.jiayuntong.com:5172/server/');

    expect(config.apiBaseUri, Uri.parse('https://wx.jiayuntong.com:5172/server/api/v1/'));
  });

  test('完整接口地址不会重复追加路径', () {
    final config = AppConfig.fromApiServerUrl('https://example.com/gateway/api/v1/');

    expect(config.apiBaseUri, Uri.parse('https://example.com/gateway/api/v1/'));
  });

  test('后端根路径资源地址保留网关前缀', () {
    final config = AppConfig.fromApiServerUrl('https://wx.jiayuntong.com:5172/server/');

    expect(
      config.resolveResource('/api/v1/videos/video-1/stream'),
      Uri.parse('https://wx.jiayuntong.com:5172/server/api/v1/videos/video-1/stream'),
    );
  });
}
