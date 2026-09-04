import 'dart:io';

void main(List<String> arguments) {
  if (arguments.isEmpty || arguments.length > 2) {
    _fail('用法：dart stamp-web-build.dart <Web 构建目录> [14 位构建时间戳]');
  }

  final buildDirectory = Directory(arguments.first);
  if (!buildDirectory.existsSync()) {
    _fail('Web 构建目录不存在：${buildDirectory.path}');
  }

  final buildTimestamp = arguments.length == 2 && arguments[1].trim().isNotEmpty
      ? arguments[1].trim()
      : _formatTimestamp(DateTime.now());
  if (!RegExp(r'^\d{14}$').hasMatch(buildTimestamp)) {
    _fail('构建时间戳必须是 yyyyMMddHHmmss 格式的 14 位数字');
  }

  final indexFile = File(
    '${buildDirectory.path}${Platform.pathSeparator}index.html',
  );
  final bootstrapFile = File(
    '${buildDirectory.path}${Platform.pathSeparator}flutter_bootstrap.js',
  );
  if (!indexFile.existsSync() || !bootstrapFile.existsSync()) {
    _fail('Web 构建产物缺少 index.html 或 flutter_bootstrap.js');
  }

  final stampedIndex = indexFile.readAsStringSync().replaceFirst(
    RegExp(r'flutter_bootstrap\.js(?:\?v=\d{14})?'),
    'flutter_bootstrap.js?v=$buildTimestamp',
  );
  final stampedBootstrap = bootstrapFile.readAsStringSync().replaceFirst(
    RegExp(r'"mainJsPath":"main\.dart\.js(?:\?v=\d{14})?"'),
    '"mainJsPath":"main.dart.js?v=$buildTimestamp"',
  );

  if (!stampedIndex.contains('flutter_bootstrap.js?v=$buildTimestamp')) {
    _fail('未能在 index.html 中写入启动脚本时间戳');
  }
  if (!stampedBootstrap.contains(
    '"mainJsPath":"main.dart.js?v=$buildTimestamp"',
  )) {
    _fail('未能在 flutter_bootstrap.js 中写入主程序时间戳');
  }

  indexFile.writeAsStringSync(stampedIndex);
  bootstrapFile.writeAsStringSync(stampedBootstrap);
  stdout.writeln('Web 构建时间戳写入完成：$buildTimestamp');
}

String _formatTimestamp(DateTime value) {
  String twoDigits(int number) => number.toString().padLeft(2, '0');
  return '${value.year.toString().padLeft(4, '0')}'
      '${twoDigits(value.month)}'
      '${twoDigits(value.day)}'
      '${twoDigits(value.hour)}'
      '${twoDigits(value.minute)}'
      '${twoDigits(value.second)}';
}

Never _fail(String message) {
  stderr.writeln(message);
  exit(1);
}
