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
  }) : assert(items.isNotEmpty),
       assert(initialIndex >= 0 && initialIndex < items.length),
       items = List.unmodifiable(items),
       _currentIndex = initialIndex;

  final List<VideoItem> items;
  final PlaybackControllerFactory _controllerFactory;
  final Map<int, PlaybackController> _controllers = {};
  final Map<int, Future<void>> _initializations = {};

  int _currentIndex;
  int _activationVersion = 0;
  bool _requiresUserPlay = false;
  bool _resumeAfterSeek = false;
  bool _disposed = false;

  int get currentIndex => _currentIndex;
  VideoItem get currentItem => items[_currentIndex];
  bool get requiresUserPlay => _requiresUserPlay;
  PlaybackController? get currentController => _controllers[_currentIndex];
  PlaybackSnapshot get currentSnapshot =>
      currentController?.snapshot ?? const PlaybackSnapshot.loading();

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
    if (controller == null || !controller.snapshot.isInitialized) {
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
    _requiresUserPlay = false;
    await _activate(_currentIndex, autoPlay: true);
  }

  Future<void> _activate(int index, {required bool autoPlay}) async {
    final version = ++_activationVersion;
    final previous = _controllers[_currentIndex];
    if (previous?.snapshot.isPlaying ?? false) {
      await previous?.pause();
    }

    _currentIndex = index;
    _requiresUserPlay = false;
    _pruneControllers();
    _notify();

    try {
      final controller = await _ensureInitialized(index);
      if (_disposed || version != _activationVersion || index != _currentIndex) {
        return;
      }
      if (autoPlay) {
        await _playWithFallback(controller);
      }
      _notify();
      unawaited(_preload(index - 1));
      unawaited(_preload(index + 1));
    } on Object {
      if (!_disposed && version == _activationVersion) {
        _notify();
      }
    }
  }

  Future<PlaybackController> _ensureInitialized(int index) async {
    final controller = _controllers.putIfAbsent(index, () {
      final created = _controllerFactory.create(items[index].streamUri);
      _notify();
      return created;
    });
    if (controller.snapshot.isInitialized) {
      return controller;
    }

    final existing = _initializations[index];
    if (existing != null) {
      await existing;
      return controller;
    }

    final initialization = controller.initialize();
    _initializations[index] = initialization;
    try {
      await initialization;
      return controller;
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
    } finally {
      if (!_isAdjacent(index)) {
        _disposeController(index);
      }
    }
  }

  Future<void> _playWithFallback(PlaybackController controller) async {
    try {
      await controller.play();
      _requiresUserPlay = false;
    } on Object {
      _requiresUserPlay = true;
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
    super.dispose();
  }
}
