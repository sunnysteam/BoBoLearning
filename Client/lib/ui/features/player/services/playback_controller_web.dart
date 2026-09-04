import 'dart:async';
import 'dart:js_interop';
import 'dart:ui_web' as ui_web;

import 'package:bobo_learning/ui/features/player/services/playback_contract.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:web/web.dart' as web;

@JS('Hls')
extension type _Hls._(JSObject _) implements JSObject {
  external _Hls();

  external static bool isSupported();

  external void loadSource(String source);

  external void attachMedia(web.HTMLMediaElement media);

  external void destroy();
}

/// Web 端直接使用浏览器原生 video 元素，避免等待插件的 canplay 初始化门槛。
PlaybackController createPlatformPlaybackController(Uri streamUri, {Uri? hlsUri}) {
  return NativeWebPlaybackController(streamUri, hlsUri: hlsUri);
}

/// 可精细控制预加载和缓冲事件的 Web 原生播放器。
class NativeWebPlaybackController extends PlaybackController {
  NativeWebPlaybackController(this._streamUri, {this._hlsUri}) : _id = _nextId++ {
    _ensureViewFactoryRegistered();
    _elements[_id] = _videoElement;
    _videoElement
      ..autoplay = false
      ..controls = false
      ..playsInline = true
      ..preload = 'auto'
      ..disablePictureInPicture = true;
    _videoElement.setAttribute('controlsList', 'nodownload noremoteplayback noplaybackrate');
    _videoElement.setAttribute('disableRemotePlayback', 'true');
    _videoElement.style
      ..width = '100%'
      ..height = '100%'
      ..backgroundColor = '#000000'
      ..pointerEvents = 'none';
    _videoElement.style.setProperty('object-fit', 'contain');
    _ensurePreloadHost().appendChild(_videoElement);
    _attachListeners();
  }

  static const String _viewType = 'bobo-learning-native-video';
  static final Map<int, web.HTMLVideoElement> _elements = {};
  static int _nextId = 1;
  static bool _viewFactoryRegistered = false;
  static web.HTMLDivElement? _preloadHost;

  final Uri _streamUri;
  final Uri? _hlsUri;
  final int _id;
  final web.HTMLVideoElement _videoElement = web.HTMLVideoElement();
  final Map<String, web.EventListener> _listeners = {};
  final Completer<void> _viewAttachedCompleter = Completer<void>();

  Completer<void>? _playingCompleter;
  _Hls? _hls;
  bool _sourceAssigned = false;
  bool _isInitialized = false;
  bool _isPlaying = false;
  bool _isBuffering = false;
  bool _isCompleted = false;
  bool _playRequested = false;
  bool _disposed = false;
  String? _errorMessage;

  static void _ensureViewFactoryRegistered() {
    if (_viewFactoryRegistered) {
      return;
    }
    _viewFactoryRegistered = true;
    ui_web.platformViewRegistry.registerViewFactory(_viewType, (int viewId, {Object? params}) {
      final values = params! as Map<Object?, Object?>;
      final controllerId = values['controllerId']! as int;
      return _elements[controllerId] ?? web.HTMLDivElement();
    });
  }

  static web.HTMLDivElement _ensurePreloadHost() {
    final existing = _preloadHost;
    if (existing != null) {
      return existing;
    }
    final host = web.HTMLDivElement()..id = 'bobo-learning-video-preload-host';
    host.style
      ..position = 'fixed'
      ..left = '-10000px'
      ..top = '-10000px'
      ..width = '1px'
      ..height = '1px'
      ..overflow = 'hidden'
      ..opacity = '0'
      ..pointerEvents = 'none';
    web.document.body?.appendChild(host);
    _preloadHost = host;
    return host;
  }

  @override
  PlaybackSnapshot get snapshot {
    return PlaybackSnapshot(
      isInitialized: _isInitialized,
      isPlaying: _isPlaying,
      isBuffering: _isBuffering,
      isCompleted: _isCompleted,
      position: _durationFromSeconds(_videoElement.currentTime),
      duration: _durationFromSeconds(_videoElement.duration),
      size: Size(_videoElement.videoWidth.toDouble(), _videoElement.videoHeight.toDouble()),
      errorMessage: _errorMessage,
    );
  }

  @override
  Widget buildVideo() {
    return HtmlElementView(
      viewType: _viewType,
      creationParams: <String, int>{'controllerId': _id},
      hitTestBehavior: PlatformViewHitTestBehavior.transparent,
      onPlatformViewCreated: (_) {
        Future<void>.delayed(Duration.zero, () {
          if (!_disposed && !_viewAttachedCompleter.isCompleted) {
            _viewAttachedCompleter.complete();
          }
        });
      },
    );
  }

  @override
  void setPoster(Uri posterUri) {
    if (!_disposed) {
      _videoElement.poster = posterUri.toString();
    }
  }

  @override
  Future<void> initialize() {
    if (_disposed) {
      return Future<void>.error(StateError('播放器已释放，无法继续初始化'));
    }
    if (_isInitialized) {
      return Future<void>.value();
    }

    if (!_sourceAssigned) {
      _sourceAssigned = true;
      _errorMessage = null;
      _assignSource();
    }
    // Web 初始化只负责完成元素和资源绑定，立即播放会让浏览器提升媒体请求优先级。
    _markInitialized();
    return Future<void>.value();
  }

  void _assignSource() {
    final hlsUri = _hlsUri;
    if (hlsUri != null && _supportsNativeHls()) {
      _videoElement.src = hlsUri.toString();
      _videoElement.load();
      return;
    }
    if (hlsUri != null && _supportsHlsJs()) {
      final hls = _Hls();
      _hls = hls;
      hls.loadSource(hlsUri.toString());
      hls.attachMedia(_videoElement);
      return;
    }
    _videoElement.src = _streamUri.toString();
    _videoElement.load();
  }

  bool _supportsNativeHls() {
    return _videoElement.canPlayType('application/vnd.apple.mpegurl').isNotEmpty;
  }

  bool _supportsHlsJs() {
    try {
      return _Hls.isSupported();
    } on Object {
      return false;
    }
  }

  @override
  Future<void> play() async {
    if (!_isInitialized) {
      await initialize();
    }
    await _viewAttachedCompleter.future.timeout(
      const Duration(seconds: 3),
      onTimeout: () {
        // 页面暂未挂载时仍允许浏览器尝试在离屏预加载容器内播放。
      },
    );
    _playRequested = true;
    _isCompleted = false;
    _setBuffering(true);
    final playingCompleter = Completer<void>();
    _playingCompleter = playingCompleter;
    try {
      await _videoElement.play().toDart;
      if (_isPlaying && !playingCompleter.isCompleted) {
        playingCompleter.complete();
      }
      await playingCompleter.future;
    } on Object catch (error) {
      _playRequested = false;
      _isPlaying = false;
      _isBuffering = false;
      if (!_isAutoPlayRestriction(error)) {
        _errorMessage = '视频播放失败，请重新加载后再试';
      }
      _notify();
      rethrow;
    } finally {
      if (identical(_playingCompleter, playingCompleter)) {
        _playingCompleter = null;
      }
    }
  }

  @override
  Future<void> pause() async {
    if (_disposed) {
      return;
    }
    _playRequested = false;
    _videoElement.pause();
    _isPlaying = false;
    _isBuffering = false;
    _notify();
  }

  @override
  Future<void> setVolume(double volume) async {
    if (_disposed) {
      return;
    }
    final resolved = volume.clamp(0, 1).toDouble();
    _videoElement.muted = resolved == 0;
    if (resolved > 0) {
      _videoElement.volume = resolved;
    }
  }

  @override
  Future<void> seekTo(Duration position) async {
    if (!_isInitialized) {
      await initialize();
    }
    _isCompleted = false;
    _videoElement.currentTime = position.inMilliseconds / 1000;
    _notify();
  }

  void _attachListeners() {
    _listen('loadedmetadata', (_) => _markInitialized());
    _listen('durationchange', (_) {
      if (_videoElement.readyState >= web.HTMLMediaElement.HAVE_METADATA) {
        _markInitialized();
      } else {
        _notify();
      }
    });
    _listen('loadeddata', (_) => _setBuffering(false));
    _listen('canplay', (_) => _setBuffering(false));
    _listen('play', (_) {
      _playRequested = true;
      _isPlaying = true;
      _isCompleted = false;
      _notify();
    });
    _listen('playing', (_) {
      _isPlaying = true;
      final playingCompleter = _playingCompleter;
      if (playingCompleter != null && !playingCompleter.isCompleted) {
        playingCompleter.complete();
      }
      _setBuffering(false);
    });
    _listen('waiting', (_) {
      if (_playRequested) {
        _setBuffering(true);
      }
    });
    _listen('stalled', (_) {
      // stalled 只表示浏览器暂时没有继续取到网络数据；当本地缓冲仍足够播放时，
      // Chromium 不一定再次触发 playing，不能据此一直显示缓冲遮罩。
      if (_playRequested && _videoElement.readyState < web.HTMLMediaElement.HAVE_FUTURE_DATA) {
        _setBuffering(true);
      }
    });
    _listen('pause', (_) {
      if (!_videoElement.ended) {
        _isPlaying = false;
        _notify();
      }
    });
    _listen('ended', (_) {
      _playRequested = false;
      _isPlaying = false;
      _isBuffering = false;
      _isCompleted = true;
      _notify();
    });
    _listen('timeupdate', (_) => _handlePlaybackProgress());
    _listen('progress', (_) => _handlePlaybackProgress());
    _listen('seeking', (_) {
      if (_playRequested) {
        _setBuffering(true);
      }
    });
    _listen('seeked', (_) => _setBuffering(false));
    _listen('error', (_) => _handleMediaError());
  }

  void _listen(String eventName, void Function(web.Event event) callback) {
    final listener = callback.toJS;
    _listeners[eventName] = listener;
    _videoElement.addEventListener(eventName, listener);
  }

  void _markInitialized() {
    if (_disposed) {
      return;
    }
    final changed = !_isInitialized;
    _isInitialized = true;
    if (changed || _videoElement.readyState >= web.HTMLMediaElement.HAVE_METADATA) {
      _notify();
    }
  }

  void _setBuffering(bool value) {
    if (_disposed || _isBuffering == value) {
      return;
    }
    _isBuffering = value;
    _notify();
  }

  void _handlePlaybackProgress() {
    if (_disposed) {
      return;
    }
    if (_playRequested &&
        !_videoElement.paused &&
        _videoElement.readyState >= web.HTMLMediaElement.HAVE_FUTURE_DATA) {
      _isPlaying = true;
      _isBuffering = false;
    }
    // timeupdate 同时驱动进度条，因此即使缓冲状态没有变化也要通知界面。
    _notify();
  }

  void _handleMediaError() {
    if (_disposed) {
      return;
    }
    final mediaError = _videoElement.error;
    _errorMessage = switch (mediaError?.code) {
      web.MediaError.MEDIA_ERR_ABORTED => '视频加载已取消，请重新加载后再试',
      web.MediaError.MEDIA_ERR_NETWORK => '视频连接中断，请检查网络后重新加载',
      web.MediaError.MEDIA_ERR_DECODE => '当前视频暂时无法解码播放',
      web.MediaError.MEDIA_ERR_SRC_NOT_SUPPORTED => '当前浏览器不支持这个视频格式',
      _ => '视频加载失败，请重新加载后再试',
    };
    _playRequested = false;
    _isPlaying = false;
    _isBuffering = false;
    final playingCompleter = _playingCompleter;
    if (playingCompleter != null && !playingCompleter.isCompleted) {
      playingCompleter.completeError(StateError(_errorMessage!));
    }
    _notify();
  }

  bool _isAutoPlayRestriction(Object error) {
    final normalized = error.toString().toLowerCase();
    return normalized.contains('notallowederror') ||
        normalized.contains('not allowed') ||
        normalized.contains('user gesture');
  }

  Duration _durationFromSeconds(double seconds) {
    if (!seconds.isFinite || seconds <= 0) {
      return Duration.zero;
    }
    return Duration(milliseconds: (seconds * 1000).round());
  }

  void _notify() {
    if (!_disposed) {
      notifyListeners();
    }
  }

  @override
  void dispose() {
    if (_disposed) {
      return;
    }
    _disposed = true;
    final playingCompleter = _playingCompleter;
    if (playingCompleter != null && !playingCompleter.isCompleted) {
      playingCompleter.completeError(StateError('播放器已释放，播放请求已取消'));
    }
    for (final entry in _listeners.entries) {
      _videoElement.removeEventListener(entry.key, entry.value);
    }
    _listeners.clear();
    _hls?.destroy();
    _hls = null;
    _videoElement.pause();
    _videoElement.removeAttribute('src');
    _videoElement.load();
    _videoElement.remove();
    _elements.remove(_id);
    super.dispose();
  }
}
