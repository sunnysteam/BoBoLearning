import 'dart:async';
import 'dart:ui' as ui;

import 'package:bobo_learning/domain/models/cloud_media_item.dart';
import 'package:bobo_learning/ui/core/app_theme.dart';
import 'package:bobo_learning/ui/core/immersive_viewer.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

typedef PhotoImageProvider = ImageProvider<Object> Function(Uri uri);

ImageProvider<Object> _networkImage(Uri uri) => NetworkImage(uri.toString());

/// 使用打开时的相册快照，避免列表刷新改变当前照片与相邻顺序。
class PhotoViewerPage extends StatefulWidget {
  PhotoViewerPage({
    required List<CloudMediaItem> items,
    required this.initialIndex,
    this.desktopNavigationEnabled = kIsWeb,
    this.imageProvider = _networkImage,
    super.key,
  }) : assert(items.isNotEmpty),
       assert(initialIndex >= 0 && initialIndex < items.length),
       items = List.unmodifiable(items);

  final List<CloudMediaItem> items;
  final int initialIndex;
  final bool desktopNavigationEnabled;
  final PhotoImageProvider imageProvider;

  @override
  State<PhotoViewerPage> createState() => _PhotoViewerPageState();
}

class _PhotoViewerPageState extends State<PhotoViewerPage> {
  late final PageController _pages = PageController(initialPage: widget.initialIndex);
  late int _index = widget.initialIndex;
  bool _zoomed = false;
  bool _pinching = false;
  final Set<int> _pointers = {};
  bool _controlsVisible = true;
  bool _navigating = false;
  final Set<String> _prefetched = {};

  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  void _changePage(int index) {
    setState(() {
      _index = index;
      _zoomed = false;
      _controlsVisible = true;
    });
  }

  void _pointerDown(PointerDownEvent event) {
    _pointers.add(event.pointer);
    // 第二根手指落下就暂停翻页，避免横向捏合被识别为单指翻页。
    if (_pointers.length > 1 && !_pinching) {
      setState(() => _pinching = true);
    }
  }

  void _pointerEnd(PointerEvent event) {
    _pointers.remove(event.pointer);
    // 双指操作结束前持续锁定，缩放后的平移由 _zoomed 接管。
    if (_pointers.isEmpty && _pinching) {
      setState(() => _pinching = false);
    }
  }

  Future<void> _navigate(int index) async {
    if (_navigating || index < 0 || index >= widget.items.length || !_pages.hasClients) {
      return;
    }
    _navigating = true;
    try {
      await _pages.animateToPage(
        index,
        duration: MediaQuery.disableAnimationsOf(context)
            ? Duration.zero
            : const Duration(milliseconds: 320),
        curve: Curves.easeOutCubic,
      );
    } finally {
      _navigating = false;
    }
  }

  void _photoReady(int index) {
    // 当前原图就绪后才预取下一张，避免与首张加载争抢带宽。
    if (!mounted || index != _index || index + 1 >= widget.items.length) {
      return;
    }
    final next = widget.items[index + 1];
    if (_prefetched.add(next.id)) {
      unawaited(precacheImage(widget.imageProvider(next.contentUri), context, onError: (_, _) {}));
    }
  }

  @override
  Widget build(BuildContext context) {
    final item = widget.items[_index];
    return Scaffold(
      key: const Key('相册大图页'),
      backgroundColor: const Color(0xFF151B22),
      body: CallbackShortcuts(
        bindings: {
          const SingleActivator(LogicalKeyboardKey.arrowLeft): () => _navigate(_index - 1),
          const SingleActivator(LogicalKeyboardKey.arrowRight): () => _navigate(_index + 1),
          const SingleActivator(LogicalKeyboardKey.escape): () => Navigator.of(context).maybePop(),
        },
        child: Focus(
          autofocus: true,
          child: LayoutBuilder(
            builder: (context, constraints) {
              final desktop = widget.desktopNavigationEnabled && constraints.maxWidth >= 1024;
              return Stack(
                fit: StackFit.expand,
                children: [
                  ExcludeSemantics(
                    child: AnimatedSwitcher(
                      duration: MediaQuery.disableAnimationsOf(context)
                          ? Duration.zero
                          : const Duration(milliseconds: 420),
                      child: SizedBox.expand(
                        key: ValueKey(item.id),
                        child: ImageFiltered(
                          imageFilter: ui.ImageFilter.blur(sigmaX: 28, sigmaY: 28),
                          child: Image(
                            image: widget.imageProvider(item.thumbnailUri),
                            fit: BoxFit.cover,
                            color: Colors.black.withValues(alpha: 0.76),
                            colorBlendMode: BlendMode.darken,
                            errorBuilder: (_, _, _) => const SizedBox.expand(),
                          ),
                        ),
                      ),
                    ),
                  ),
                  SafeArea(
                    child: Listener(
                      onPointerDown: _pointerDown,
                      onPointerUp: _pointerEnd,
                      onPointerCancel: _pointerEnd,
                      child: PageView.builder(
                        key: const Key('横向照片列表'),
                        controller: _pages,
                        scrollDirection: Axis.horizontal,
                        physics: _zoomed || _pinching
                            ? const NeverScrollableScrollPhysics()
                            : const ClampingScrollPhysics(),
                        itemCount: widget.items.length,
                        onPageChanged: _changePage,
                        itemBuilder: (context, index) => _PhotoPage(
                          key: ValueKey(widget.items[index].id),
                          item: widget.items[index],
                          active: index == _index,
                          desktop: desktop,
                          imageProvider: widget.imageProvider,
                          onReady: () => _photoReady(index),
                          onZoomChanged: (zoomed) {
                            if (index == _index && zoomed != _zoomed) {
                              setState(() => _zoomed = zoomed);
                            }
                          },
                          onTap: () => setState(() => _controlsVisible = !_controlsVisible),
                        ),
                      ),
                    ),
                  ),
                  if (desktop && _index > 0)
                    Positioned(
                      left: 28,
                      top: 0,
                      bottom: 0,
                      child: Center(
                        child: ViewerButton(
                          key: const Key('上一张照片按钮'),
                          label: '上一张照片',
                          icon: Icons.chevron_left_rounded,
                          large: true,
                          onPressed: () => _navigate(_index - 1),
                        ),
                      ),
                    ),
                  if (desktop && _index < widget.items.length - 1)
                    Positioned(
                      right: 28,
                      top: 0,
                      bottom: 0,
                      child: Center(
                        child: ViewerButton(
                          key: const Key('下一张照片按钮'),
                          label: '下一张照片',
                          icon: Icons.chevron_right_rounded,
                          large: true,
                          onPressed: () => _navigate(_index + 1),
                        ),
                      ),
                    ),
                  Positioned(
                    top: 0,
                    left: 0,
                    right: 0,
                    child: ViewerChrome(
                      visible: _controlsVisible,
                      child: SafeArea(
                        bottom: false,
                        child: Padding(
                          padding: EdgeInsets.fromLTRB(
                            desktop ? 32 : 16,
                            12,
                            desktop ? 32 : 20,
                            24,
                          ),
                          child: Row(
                            children: [
                              ViewerButton(
                                key: const Key('返回相册按钮'),
                                label: '返回相册',
                                icon: Icons.arrow_back_rounded,
                                onPressed: () => Navigator.of(context).pop(),
                              ),
                              const SizedBox(width: 14),
                              const Expanded(
                                child: Text(
                                  '菠萝相册',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 16,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                                decoration: BoxDecoration(
                                  color: Colors.white.withValues(alpha: 0.09),
                                  borderRadius: BorderRadius.circular(24),
                                  border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
                                ),
                                child: Text(
                                  '${_index + 1} / ${widget.items.length}',
                                  key: const Key('照片序号'),
                                  semanticsLabel: '第 ${_index + 1} 张，共 ${widget.items.length} 张',
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 0,
                    child: ViewerChrome(
                      visible: _controlsVisible,
                      bottom: true,
                      child: SafeArea(
                        top: false,
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(28, 24, 28, 20),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                item.fileName,
                                key: const Key('照片文件名'),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: Colors.white70,
                                  fontSize: 13,
                                  height: 1.5,
                                ),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                _zoomed
                                    ? '拖动查看细节 · 双击还原'
                                    : widget.items.length == 1
                                    ? '双击放大 · 轻触隐藏界面'
                                    : desktop
                                    ? '左右切换 · 双击放大'
                                    : '左右滑动切换 · 双击放大',
                                style: TextStyle(
                                  color: Colors.white.withValues(alpha: 0.42),
                                  fontSize: 11,
                                  letterSpacing: 0.5,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

class _PhotoPage extends StatefulWidget {
  const _PhotoPage({
    required this.item,
    required this.active,
    required this.desktop,
    required this.imageProvider,
    required this.onReady,
    required this.onZoomChanged,
    required this.onTap,
    super.key,
  });

  final CloudMediaItem item;
  final bool active;
  final bool desktop;
  final PhotoImageProvider imageProvider;
  final VoidCallback onReady;
  final ValueChanged<bool> onZoomChanged;
  final VoidCallback onTap;

  @override
  State<_PhotoPage> createState() => _PhotoPageState();
}

class _PhotoPageState extends State<_PhotoPage> {
  final _transform = TransformationController();
  bool _zoomed = false;
  Offset _doubleTapPosition = Offset.zero;

  @override
  void didUpdateWidget(covariant _PhotoPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.active && !widget.active) {
      _transform.value = Matrix4.identity();
      _zoomed = false;
    }
  }

  @override
  void dispose() {
    _transform.dispose();
    super.dispose();
  }

  void _syncZoom() {
    final zoomed = _transform.value.getMaxScaleOnAxis() > 1.01;
    if (zoomed != _zoomed) {
      setState(() => _zoomed = zoomed);
      widget.onZoomChanged(zoomed);
    }
  }

  void _toggleZoom() {
    _transform.value = _zoomed
        ? Matrix4.identity()
        : (Matrix4.identity()
            ..translateByDouble(-_doubleTapPosition.dx, -_doubleTapPosition.dy, 0, 1)
            ..scaleByDouble(2, 2, 1, 1));
    _syncZoom();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      key: Key('照片手势-${widget.item.id}'),
      behavior: HitTestBehavior.opaque,
      onTap: widget.onTap,
      onDoubleTapDown: (details) => _doubleTapPosition = details.localPosition,
      onDoubleTap: _toggleZoom,
      child: MediaQuery(
        // InteractiveViewer 即使禁用平移也会抢占单指拖动。
        // 原始比例时只允许它通过双指缩放认领手势，单指交给外层翻页；
        // 放大后恢复系统阈值，以便拖动查看照片细节。
        data: MediaQuery.of(context).copyWith(
          gestureSettings: _zoomed
              ? MediaQuery.gestureSettingsOf(context)
              : const DeviceGestureSettings(touchSlop: double.infinity),
        ),
        child: InteractiveViewer(
          transformationController: _transform,
          minScale: 1,
          maxScale: 5,
          panEnabled: _zoomed,
          onInteractionUpdate: (_) => _syncZoom(),
          child: Padding(
            padding: EdgeInsets.fromLTRB(
              widget.desktop ? 112 : 12,
              80,
              widget.desktop ? 112 : 12,
              96,
            ),
            child: ProgressivePhoto(
              item: widget.item,
              loadOriginal: widget.active,
              imageProvider: widget.imageProvider,
              onReady: widget.onReady,
            ),
          ),
        ),
      ),
    );
  }
}

/// 保留已显示的缩略图，原图解码后淡入；失败和超时均可就地重试。
class ProgressivePhoto extends StatefulWidget {
  const ProgressivePhoto({
    required this.item,
    required this.loadOriginal,
    required this.imageProvider,
    required this.onReady,
    super.key,
  });

  final CloudMediaItem item;
  final bool loadOriginal;
  final PhotoImageProvider imageProvider;
  final VoidCallback onReady;

  @override
  State<ProgressivePhoto> createState() => _ProgressivePhotoState();
}

class _ProgressivePhotoState extends State<ProgressivePhoto> {
  bool _ready = false;
  bool _failed = false;
  bool _slow = false;
  int _attempt = 0;
  Timer? _slowTimer;
  Timer? _timeoutTimer;

  @override
  void initState() {
    super.initState();
    _startTimers();
  }

  @override
  void didUpdateWidget(covariant ProgressivePhoto oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.loadOriginal != oldWidget.loadOriginal) {
      _stopTimers();
      if (widget.loadOriginal && !_ready && !_failed) {
        _startTimers();
      }
    }
  }

  void _startTimers() {
    if (!widget.loadOriginal) return;
    _slowTimer = Timer(const Duration(seconds: 8), () {
      if (mounted && !_ready && !_failed) setState(() => _slow = true);
    });
    _timeoutTimer = Timer(const Duration(seconds: 30), () {
      if (mounted && !_ready) setState(() => _failed = true);
    });
  }

  void _stopTimers() {
    _slowTimer?.cancel();
    _timeoutTimer?.cancel();
  }

  void _finish(int attempt, {required bool success}) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || attempt != _attempt || _ready || _failed) return;
      _stopTimers();
      setState(() {
        _ready = success;
        _failed = !success;
      });
      if (success) widget.onReady();
    });
  }

  Future<void> _retry() async {
    _stopTimers();
    final attempt = ++_attempt;
    await widget.imageProvider(widget.item.contentUri).evict();
    if (!mounted || attempt != _attempt) return;
    setState(() {
      _failed = false;
      _ready = false;
      _slow = false;
    });
    _startTimers();
  }

  @override
  void dispose() {
    _stopTimers();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final attempt = _attempt;
    return Stack(
      fit: StackFit.expand,
      children: [
        AnimatedOpacity(
          opacity: _ready ? 0 : 1,
          duration: MediaQuery.disableAnimationsOf(context)
              ? Duration.zero
              : const Duration(milliseconds: 360),
          child: Stack(
            fit: StackFit.expand,
            children: [
              const Center(child: Icon(Icons.photo_outlined, color: Color(0x33FFFFFF), size: 46)),
              Image(
                key: Key('照片预览-${widget.item.id}'),
                image: widget.imageProvider(widget.item.thumbnailUri),
                fit: BoxFit.contain,
                excludeFromSemantics: true,
                errorBuilder: (_, _, _) => const SizedBox.expand(),
              ),
            ],
          ),
        ),
        if ((widget.loadOriginal || _ready) && !_failed)
          Image(
            key: ValueKey('原图-${widget.item.id}-$attempt'),
            image: widget.imageProvider(widget.item.contentUri),
            fit: BoxFit.contain,
            semanticLabel: widget.item.fileName,
            frameBuilder: (context, child, frame, synchronous) {
              final visible = frame != null;
              if (visible && !_ready) _finish(attempt, success: true);
              return AnimatedOpacity(
                key: Key('原图渐入-${widget.item.id}'),
                opacity: visible ? 1 : 0,
                duration: synchronous || MediaQuery.disableAnimationsOf(context)
                    ? Duration.zero
                    : const Duration(milliseconds: 360),
                curve: Curves.easeOutCubic,
                child: child,
              );
            },
            errorBuilder: (_, _, _) {
              _finish(attempt, success: false);
              return const SizedBox.expand();
            },
          ),
        if (!_ready && widget.loadOriginal)
          Align(
            alignment: Alignment.bottomCenter,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Material(
                color: const Color(0xDD20262D),
                borderRadius: BorderRadius.circular(20),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (!_failed) ...[
                            const SizedBox.square(
                              dimension: 14,
                              child: CircularProgressIndicator(
                                color: AppColors.sunshine,
                                strokeWidth: 1.8,
                              ),
                            ),
                            const SizedBox(width: 10),
                          ],
                          Flexible(
                            child: Text(
                              _failed
                                  ? '清晰照片加载失败'
                                  : _slow
                                  ? '网络有点慢，照片还在加载'
                                  : '正在加载清晰照片…',
                              key: Key('照片加载状态-${widget.item.id}'),
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 12,
                                height: 1.5,
                              ),
                            ),
                          ),
                        ],
                      ),
                      if (_failed || _slow)
                        TextButton.icon(
                          key: Key('重试照片-${widget.item.id}'),
                          onPressed: _retry,
                          icon: const Icon(Icons.refresh_rounded, size: 18),
                          label: const Text('重新加载'),
                          style: TextButton.styleFrom(foregroundColor: AppColors.sunshine),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}
