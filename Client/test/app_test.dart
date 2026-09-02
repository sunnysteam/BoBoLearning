import 'package:bobo_learning/app.dart';
import 'package:bobo_learning/config/app_config.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('应用显示名统一为菠萝乐园', (tester) async {
    await tester.pumpWidget(
      BoBoLearningApp(config: AppConfig(apiBaseUri: Uri.parse('http://127.0.0.1:5171/api/v1/'))),
    );

    final app = tester.widget<MaterialApp>(find.byType(MaterialApp));
    expect(app.title, '菠萝乐园');
  });
}
