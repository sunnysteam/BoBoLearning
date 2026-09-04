import 'package:bobo_learning/config/app_config.dart';
import 'package:bobo_learning/data/repositories/app_update_repository_impl.dart';
import 'package:bobo_learning/data/repositories/cloud_media_repository_impl.dart';
import 'package:bobo_learning/data/repositories/video_repository_impl.dart';
import 'package:bobo_learning/data/services/app_update_api_service.dart';
import 'package:bobo_learning/data/services/cloud_media_api_service.dart';
import 'package:bobo_learning/data/services/video_api_service.dart';
import 'package:bobo_learning/domain/models/cloud_media_item.dart';
import 'package:bobo_learning/ui/core/app_theme.dart';
import 'package:bobo_learning/ui/features/cloud/view_models/cloud_media_view_model.dart';
import 'package:bobo_learning/ui/features/cloud/views/cloud_media_page.dart';
import 'package:bobo_learning/ui/features/home/view_models/home_view_model.dart';
import 'package:bobo_learning/ui/features/home/views/home_page.dart';
import 'package:bobo_learning/ui/features/player/services/playback_controller.dart';
import 'package:bobo_learning/ui/features/portal/views/portal_page.dart';
import 'package:bobo_learning/ui/features/update/services/app_update_platform.dart';
import 'package:bobo_learning/ui/features/update/view_models/app_update_view_model.dart';
import 'package:bobo_learning/ui/features/update/views/app_update_prompt_host.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

/// 菠萝乐园应用根节点，统一管理应用级依赖的生命周期。
class BoBoLearningApp extends StatefulWidget {
  const BoBoLearningApp({required this.config, super.key});

  final AppConfig config;

  @override
  State<BoBoLearningApp> createState() => _BoBoLearningAppState();
}

class _BoBoLearningAppState extends State<BoBoLearningApp> with WidgetsBindingObserver {
  late final http.Client _httpClient;
  late final HomeViewModel _homeViewModel;
  late final CloudMediaViewModel _cloudVideoViewModel;
  late final CloudMediaViewModel _cloudAlbumViewModel;
  late final AppUpdateViewModel _appUpdateViewModel;
  final PlaybackControllerFactory _playbackControllerFactory = const VideoPlayerControllerFactory();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _httpClient = http.Client();
    final VideoApiService apiService = VideoApiService(
      client: _httpClient,
      apiBaseUri: widget.config.apiBaseUri,
    );
    _homeViewModel = HomeViewModel(
      repository: VideoRepositoryImpl(apiService: apiService, config: widget.config),
    );
    final cloudRepository = CloudMediaRepositoryImpl(
      apiService: CloudMediaApiService(client: _httpClient, apiBaseUri: widget.config.apiBaseUri),
      config: widget.config,
    );
    _cloudVideoViewModel = CloudMediaViewModel(
      repository: cloudRepository,
      kind: CloudMediaKind.video,
    );
    _cloudAlbumViewModel = CloudMediaViewModel(
      repository: cloudRepository,
      kind: CloudMediaKind.photo,
    );
    _appUpdateViewModel = AppUpdateViewModel(
      repository: AppUpdateRepositoryImpl(
        apiService: AppUpdateApiService(client: _httpClient, apiBaseUri: widget.config.apiBaseUri),
        config: widget.config,
      ),
      platform: const MethodChannelAppUpdatePlatform(),
    );
    _appUpdateViewModel.start();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _appUpdateViewModel.onAppResumed();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _appUpdateViewModel.dispose();
    _cloudVideoViewModel.dispose();
    _cloudAlbumViewModel.dispose();
    _homeViewModel.dispose();
    _httpClient.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: '菠萝乐园',
      theme: AppTheme.light,
      home: AppUpdatePromptHost(
        viewModel: _appUpdateViewModel,
        child: PortalPage(
          earlyLearningPageBuilder: (_) => HomePage(
            showBackButton: true,
            playbackControllerFactory: _playbackControllerFactory,
            viewModel: _homeViewModel,
          ),
          videoPageBuilder: (_) => CloudVideoPage(
            viewModel: _cloudVideoViewModel,
            playbackControllerFactory: _playbackControllerFactory,
          ),
          albumPageBuilder: (_) => CloudAlbumPage(viewModel: _cloudAlbumViewModel),
        ),
      ),
    );
  }
}
