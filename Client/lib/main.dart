import 'package:bobo_learning/app.dart';
import 'package:bobo_learning/config/app_config.dart';
import 'package:flutter/material.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(BoBoLearningApp(config: AppConfig.fromEnvironment()));
}
