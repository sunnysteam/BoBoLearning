import 'dart:async';

import 'package:bobo_learning/domain/models/video_item.dart';
import 'package:bobo_learning/ui/features/player/services/playback_controller.dart';
import 'package:flutter/foundation.dart';

/// 播放页状态、控制器生命周期和顺序切换逻辑。
class PlayerViewModel extends ChangeNotifier {
  PlayerViewModel({
    required List<VideoItem> items,
    required int initialIndex,
    required this._controllerFactory,
    bool? useMutedWebAutoPlay,
    this.initializationTimeout = const Duration(seconds: 20),
  }) : assert(items.isNotEmpty),
       assert(initialIndex >= 0 && initialIndex < items.length),
       items = List.unmodifiable(items),
       _currentIndex = initialIndex,
       _useMutedWebAutoPlay = useMutedWebAutoPlay ?? kIsWeb;

  final List<VideoItem> items;
  final PlaybackControllerFactory _controllerFactory;
  final bool _useMutedWebAutoPlay;
  final Duration initializationTimeout;
  final Map<int, PlaybackController> _controllers = {};
  final Map<int, Future<void>> _initializations = {};
  final Map<int, String> _initializationErrors = {};

  int _currentIndex;
  int _activationVersion = 0;
  bool _isAutoPlayPending = false;
  bool _requiresUserPlay = false;
  bool _isMutedForAutoPlay = false;
  bool _resumeAfterSeek = false;
  bool _disposed = false;

  int get currentIndex => _currentIndex;
  VideoItem get currentItem => items[_currentIndex];
  bool get isAutoPlayPending => _isAutoPlayPending;
  bool get requiresUserPlay => _requiresUserPlay;
  bool get isMutedForAutoPlay => _isMutedForAutoPlay;
  PlaybackController? get currentController => _controllers[_currentIndex];
  PlaybackSnapshot get currentSnapshot =>
      currentController?.snapshot ?? const PlaybackSnapshot.loading();
  String? get currentErrorMessage =>
      _initializationErrors[_currentIndex] ?? currentController?.snapshot.errorMessage;

  PlaybackController? controllerAt(int index) => _controllers[index];

  Future<void> initialize() => _activate(_currentIndex, autoPlay: true);

  Future<void> changePage(int index) async {
    if (index < 0 || index >= items.length || index == _currentIndex) {
      return;
    }
    await _activate(index, autoPlay: true);
  }

  Future<void> togglePlayback() async {
    final controller = currentController;
    if (_isAutoPlayPending || controller == null || !controller.snapshot.isInitialized) {
      return;
    }
    if (controller.snapshot.isPlaying) {
      await controller.pause();
      _requiresUserPlay = false;
    } else {
      if (controller.snapshot.isCompleted) {
        await controller.seekTo(Duration.zero);
      }
      await _playWithFallback(controller);
    }
    _notify();
  }

  /// 在用户明确点击后恢复 Web 自动播放视频的声音。
  Future<void> enableSound() async {
    final controller = currentController;
    if (!_isMutedForAutoPlay || controller == null || !controller.snapshot.isInitialized) {
      return;
    }
    try {
      await controller.setVolume(1);
      _isMutedForAutoPlay = false;
    } on Object {
      // 恢复声音失败时保持静音状态，避免中断正在播放的视频。
    }
    _notify();
  }

  Future<void> beginSeek() async {
    final controller = currentController;
    if (controller == null || !controller.snapshot.isInitialized) {
      return;
    }
    _resumeAfterSeek = controller.snapshot.isPlaying;
    if (_resumeAfterSeek) {
      await controller.pause();
    }
  }

  Future<void> completeSeek(Duration position) async {
    final controller = currentController;
    if (controller == null || !controller.snapshot.isInitialized) {
      return;
    }
    final duration = controller.snapshot.duration;
    final target = position < Duration.zero
        ? Duration.zero
        : position > duration
        ? duration
        : position;
    await controller.seekTo(target);
    if (_resumeAfterSeek) {
      await _playWithFallback(controller);
    }
    _resumeAfterSeek = false;
    _notify();
  }

  Future<void> retryCurrent() async {
    final old = _controllers.remove(_currentIndex);
    _initializations.remove(_currentIndex);
    old?.dispose();
    _initializationErrors.remove(_currentIndex);
    _requiresUserPlay = false;
    _isMutedForAutoPlay = false;
    await _activate(_currentIndex, autoPlay: true);
  }

  Future<void> _activate(int index, {required bool autoPlay}) async {
    final version = ++_activationVersion;
    final previous = _controllers[_currentIndex];
    _currentIndex = index;
    _isAutoPlayPending = autoPlay;
    _requiresUserPlay = false;
    _isMutedForAutoPlay = false;
    _notify();

    try {
      if (previous?.snapshot.isPlaying ?? false) {
        try {
          await previous?.pause();
        } on Object {
          // 旧视频暂停失败不应阻断新页面的初始化和自动播放。
        }
      }
      if (_disposed || version != _activationVersion || index != _currentIndex) {
        return;
      }
      _pruneControllers();
      final controller = await _ensureInitialized(index, retryFailedPreload: true);
      if (_disposed || version != _activationVersion || index != _currentIndex) {
        return;
      }
      if (autoPlay) {
        await _playWithFallback(controller, isAutomatic: true);
      }
      _notify();
      unawaited(_preload(index - 1));
      unawaited(_preload(index + 1));
    } on Object {
      if (!_disposed && version == _activationVersion) {
        _notify();
      }
    } finally {
      if (!_disposed && version == _activationVersion && index == _currentIndex) {
        _isAutoPlayPending = false;
        _notify();
      }
    }
  }

  Future<PlaybackController> _ensureInitialized(
    int index, {
    bool retryFailedPreload = false,
  }) async {
    final controller = _controllers.putIfAbsent(index, () {
      final created = _controllerFactory.create(
        items[index].streamUri,
        hlsUri: items[index].hlsUri,
      );
      created.setPoster(items[index].coverUri);
      _notify();
      return created;
    });
    if (controller.snapshot.isInitialized) {
      return controller;
    }

    final existing = _initializations[index];
    if (existing != null) {
      try {
        await existing;
        return controller;
      } on Object {
        if (!retryFailedPreload ||
            _disposed ||
            index != _currentIndex ||
            !identical(_controllers[index], controller)) {
          rethrow;
        }
        // 切页撞上后台预加载失败时丢弃旧实例，只自动重试一次。
        _disposeController(index);
        return _ensureInitialized(index);
      }
    }

    _initializationErrors.remove(index);
    final initialization = controller.initialize().timeout(
      initializationTimeout,
      onTimeout: () {
        throw TimeoutException('视频初始化超时', initializationTimeout);
      },
    );
    _initializations[index] = initialization;
    try {
      await initialization;
      return controller;
    } on TimeoutException {
      _initializationErrors[index] = '视频加载超时，请检查网络后重新加载';
      _notify();
      rethrow;
    } on Object {
      _initializationErrors.putIfAbsent(index, () => '视频加载失败，请检查网络后重新加载');
      _notify();
      rethrow;
    } finally {
      _initializations.remove(index);
    }
  }

  Future<void> _preload(int index) async {
    if (_disposed || index < 0 || index >= items.length) {
      return;
    }
    try {
      await _ensureInitialized(index);
    } on Object {
      // 相邻视频预加载失败不影响当前视频，切换后仍可主动重试。
      if (index != _currentIndex) {
        _disposeController(index);
      }
    } finally {
      if (!_isAdjacent(index)) {
        _disposeController(index);
      }
    }
  }

  Future<void> _playWithFallback(PlaybackController controller, {bool isAutomatic = false}) async {
    try {
      if (isAutomatic && _useMutedWebAutoPlay) {
        await controller.setVolume(0);
        _isMutedForAutoPlay = true;
      }
      await controller.play();
      _requiresUserPlay = false;
    } on Object {
      _requiresUserPlay = true;
      _isMutedForAutoPlay = false;
    }
  }

  bool _isAdjacent(int index) => (index - _currentIndex).abs() <= 1;

  void _pruneControllers() {
    final indexes = _controllers.keys.toList(growable: false);
    for (final index in indexes) {
      if (!_isAdjacent(index) && !_initializations.containsKey(index)) {
        _disposeController(index);
      }
    }
  }

  void _disposeController(int index) {
    _initializations.remove(index);
    _initializationErrors.remove(index);
    _controllers.remove(index)?.dispose();
  }

  void _notify() {
    if (!_disposed) {
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _activationVersion++;
    for (final controller in _controllers.values) {
      controller.dispose();
    }
    _controllers.clear();
    _initializations.clear();
    _initializationErrors.clear();
    super.dispose();
  }
}
