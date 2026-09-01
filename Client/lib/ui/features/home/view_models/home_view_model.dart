import 'package:bobo_learning/data/services/video_api_service.dart';
import 'package:bobo_learning/domain/models/video_item.dart';
import 'package:bobo_learning/domain/repositories/video_repository.dart';
import 'package:flutter/foundation.dart';

enum HomeLoadState { initial, loading, ready, empty, error }

/// 首页按媒体文件夹形成的只读视频分区。
class VideoFolderGroup {
  const VideoFolderGroup({required this.folderPath, required this.items});

  final String folderPath;
  final List<VideoItem> items;

  String get displayName => folderPath.isEmpty ? '未分类' : folderPath;
}

/// 首页展示状态与刷新行为。
class HomeViewModel extends ChangeNotifier {
  HomeViewModel({required this._repository});

  final VideoRepository _repository;

  HomeLoadState _state = HomeLoadState.initial;
  List<VideoItem> _items = const [];
  List<VideoFolderGroup> _groups = const [];
  String? _errorMessage;
  String? _transientMessage;
  bool _isRefreshing = false;
  bool _disposed = false;

  HomeLoadState get state => _state;
  List<VideoItem> get items => _items;
  List<VideoFolderGroup> get groups => _groups;
  String? get errorMessage => _errorMessage;
  String? get transientMessage => _transientMessage;
  bool get isRefreshing => _isRefreshing;

  Future<void> loadInitial() async {
    if (_state == HomeLoadState.loading) {
      return;
    }
    _state = HomeLoadState.loading;
    _errorMessage = null;
    _notify();
    await _load(silent: false);
  }

  Future<void> refresh({bool silent = false}) async {
    if (_isRefreshing || _state == HomeLoadState.loading) {
      return;
    }
    _isRefreshing = true;
    _notify();
    await _load(silent: silent && _items.isNotEmpty);
  }

  void clearTransientMessage() {
    _transientMessage = null;
  }

  Future<void> _load({required bool silent}) async {
    try {
      final result = await _repository.fetchVideos();
      _items = List.unmodifiable(result);
      _groups = _groupByFolder(_items);
      _errorMessage = null;
      _state = _items.isEmpty ? HomeLoadState.empty : HomeLoadState.ready;
    } on VideoApiException catch (error) {
      _handleError(error.message, silent: silent);
    } on FormatException catch (error) {
      _handleError('视频地址格式不正确：${error.message}', silent: silent);
    } on Object {
      _handleError('暂时拿不到视频，请稍后再试', silent: silent);
    } finally {
      _isRefreshing = false;
      _notify();
    }
  }

  List<VideoFolderGroup> _groupByFolder(List<VideoItem> items) {
    final grouped = <String, List<VideoItem>>{};
    for (final item in items) {
      grouped.putIfAbsent(item.folderPath, () => <VideoItem>[]).add(item);
    }
    return List.unmodifiable(
      grouped.entries.map(
        (entry) => VideoFolderGroup(folderPath: entry.key, items: List.unmodifiable(entry.value)),
      ),
    );
  }

  void _handleError(String message, {required bool silent}) {
    if (silent && _items.isNotEmpty) {
      _transientMessage = '$message，已保留当前内容';
      return;
    }
    _errorMessage = message;
    _state = HomeLoadState.error;
  }

  void _notify() {
    if (!_disposed) {
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
