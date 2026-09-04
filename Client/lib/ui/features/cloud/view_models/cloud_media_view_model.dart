import 'package:bobo_learning/data/services/cloud_media_api_service.dart';
import 'package:bobo_learning/domain/models/cloud_media_item.dart';
import 'package:bobo_learning/domain/repositories/cloud_media_repository.dart';
import 'package:flutter/foundation.dart';

enum CloudMediaLoadState { initial, loading, ready, empty, error }

/// 菠萝视频或菠萝相册的加载与刷新状态。
class CloudMediaViewModel extends ChangeNotifier {
  CloudMediaViewModel({required this.repository, required this.kind});

  final CloudMediaRepository repository;
  final CloudMediaKind kind;

  CloudMediaLoadState _state = CloudMediaLoadState.initial;
  List<CloudMediaItem> _items = const [];
  String? _errorMessage;
  String? _transientMessage;
  bool _isRefreshing = false;
  bool _disposed = false;

  CloudMediaLoadState get state => _state;
  List<CloudMediaItem> get items => _items;
  String? get errorMessage => _errorMessage;
  String? get transientMessage => _transientMessage;
  bool get isRefreshing => _isRefreshing;

  Future<void> loadInitial() async {
    if (_state != CloudMediaLoadState.initial) {
      return;
    }
    _state = CloudMediaLoadState.loading;
    _notify();
    await _load(silent: false);
  }

  Future<void> retry() async {
    if (_state == CloudMediaLoadState.loading) {
      return;
    }
    _state = CloudMediaLoadState.loading;
    _errorMessage = null;
    _notify();
    await _load(silent: false);
  }

  Future<void> refresh({bool silent = false}) async {
    if (_isRefreshing || _state == CloudMediaLoadState.loading) {
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
      _items = List.unmodifiable(await repository.fetchMedia(kind));
      _errorMessage = null;
      _state = _items.isEmpty ? CloudMediaLoadState.empty : CloudMediaLoadState.ready;
    } on CloudMediaApiException catch (error) {
      _handleError(error.message, silent: silent);
    } on FormatException catch (error) {
      _handleError('云端地址格式不正确：${error.message}', silent: silent);
    } on Object {
      _handleError('暂时拿不到云端内容，请稍后再试', silent: silent);
    } finally {
      _isRefreshing = false;
      _notify();
    }
  }

  void _handleError(String message, {required bool silent}) {
    if (silent && _items.isNotEmpty) {
      _transientMessage = '$message，已保留当前内容';
      return;
    }
    _errorMessage = message;
    _state = CloudMediaLoadState.error;
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
