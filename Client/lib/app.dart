import 'package:bobo_learning/config/app_config.dart';
import 'package:bobo_learning/data/repositories/video_repository_impl.dart';
import 'package:bobo_learning/data/services/video_api_service.dart';
import 'package:bobo_learning/ui/core/app_theme.dart';
import 'package:bobo_learning/ui/features/home/view_models/home_view_model.dart';
import 'package:bobo_learning/ui/features/home/views/home_page.dart';
import 'package:bobo_learning/ui/features/player/services/playback_controller.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

/// 菠萝早教应用根节点，统一管理应用级依赖的生命周期。
class BoBoLearningApp extends StatefulWidget {
  const BoBoLearningApp({required this.config, super.key});

  final AppConfig config;

  @override
  State<BoBoLearningApp> createState() => _BoBoLearningAppState();
}

class _BoBoLearningAppState extends State<BoBoLearningApp> {
  late final http.Client _httpClient;
  late final HomeViewModel _homeViewModel;
  final PlaybackControllerFactory _playbackControllerFactory = const VideoPlayerControllerFactory();

  @override
  void initState() {
    super.initState();
    _httpClient = http.Client();
    final VideoApiService apiService = VideoApiService(
      client: _httpClient,
      apiBaseUri: widget.config.apiBaseUri,
    );
    _homeViewModel = HomeViewModel(
      repository: VideoRepositoryImpl(apiService: apiService, config: widget.config),
    );
  }

  @override
  void dispose() {
    _homeViewModel.dispose();
    _httpClient.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: '菠萝早教',
      theme: AppTheme.light,
      home: HomePage(
        playbackControllerFactory: _playbackControllerFactory,
        viewModel: _homeViewModel,
      ),
    );
  }
}
