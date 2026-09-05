import 'dart:async';

import 'package:bobo_learning/domain/models/video_item.dart';
import 'package:bobo_learning/ui/core/immersive_viewer.dart';
import 'package:bobo_learning/ui/features/player/services/playback_controller.dart';
import 'package:bobo_learning/ui/features/player/view_models/player_view_model.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

class PlayerPage extends StatefulWidget {
  const PlayerPage({
    required this.viewModel,
    this.title = '菠萝早教',
    this.desktopNavigationEnabled = kIsWeb,
    super.key,
  });

  final PlayerViewModel viewModel;
  final String title;
  final bool desktopNavigationEnabled;

  @override
  State<PlayerPage> createState() => _PlayerPageState();
}

class _PlayerPageState extends State<PlayerPage> {
  late final PageController _pageController;
  PlaybackController? _observedController;
  Timer? _hideControlsTimer;
  Timer? _slowBufferingTimer;
  bool _controlsVisible = true;
  bool _isBufferingSlow = false;
  Duration? _dragPosition;
  DateTime? _lastBoundaryMessageAt;

  @override
  void initState() {
    super.initState();
    _pageController = PageController(initialPage: widget.viewModel.currentIndex);
    widget.viewModel.addListener(_syncPlaybackController);
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await widget.viewModel.initialize();
      if (mounted) {
        _scheduleControlsHide();
      }
    });
  }

  @override
  void dispose() {
    _hideControlsTimer?.cancel();
    _slowBufferingTimer?.cancel();
    widget.viewModel.removeListener(_syncPlaybackController);
    _observedController?.removeListener(_handlePlaybackChanged);
    _pageController.dispose();
    widget.viewModel.dispose();
    super.dispose();
  }

  void _syncPlaybackController() {
    final current = widget.viewModel.currentController;
    if (identical(current, _observedController)) {
      return;
    }
    _observedController?.removeListener(_handlePlaybackChanged);
    _observedController = current;
    _observedController?.addListener(_handlePlaybackChanged);
    _handlePlaybackChanged();
  }

  void _handlePlaybackChanged() {
    final snapshot = _observedController?.snapshot;
    if (!mounted || snapshot == null) {
      return;
    }
    _syncSlowBufferingState(snapshot);
    if (_controlsVisible) {
      return;
    }
    final shouldKeepControls =
        snapshot.errorMessage != null ||
        snapshot.isBuffering ||
        (snapshot.isInitialized && !snapshot.isPlaying);
    if (shouldKeepControls) {
      _hideControlsTimer?.cancel();
      setState(() => _controlsVisible = true);
    }
  }

  void _syncSlowBufferingState(PlaybackSnapshot snapshot) {
    final isBuffering = snapshot.isBuffering && snapshot.errorMessage == null;
    if (isBuffering) {
      _slowBufferingTimer ??= Timer(const Duration(seconds: 8), () {
        if (mounted && (_observedController?.snapshot.isBuffering ?? false)) {
          setState(() => _isBufferingSlow = true);
        }
      });
      return;
    }
    _slowBufferingTimer?.cancel();
    _slowBufferingTimer = null;
    if (_isBufferingSlow) {
      setState(() => _isBufferingSlow = false);
    }
  }

  void _showControls() {
    _hideControlsTimer?.cancel();
    if (!_controlsVisible) {
      setState(() => _controlsVisible = true);
    }
    _scheduleControlsHide();
  }

  void _scheduleControlsHide() {
    _hideControlsTimer?.cancel();
    _hideControlsTimer = Timer(const Duration(seconds: 3), () {
      if (mounted &&
          widget.viewModel.currentSnapshot.isPlaying &&
          !widget.viewModel.currentSnapshot.isBuffering &&
          _dragPosition == null &&
          widget.viewModel.currentErrorMessage == null) {
        setState(() => _controlsVisible = false);
      }
    });
  }

  Future<void> _togglePlayback() async {
    _showControls();
    await widget.viewModel.togglePlayback();
    if (mounted) {
      _scheduleControlsHide();
    }
  }

  Future<void> _changePage(int index) async {
    _slowBufferingTimer?.cancel();
    _slowBufferingTimer = null;
    setState(() {
      _dragPosition = null;
      _controlsVisible = true;
      _isBufferingSlow = false;
    });
    await widget.viewModel.changePage(index);
    if (mounted) {
      _scheduleControlsHide();
    }
  }

  Future<void> _navigateToPage(int index) async {
    if (index < 0 || index >= widget.viewModel.items.length || !_pageController.hasClients) {
      return;
    }
    _showControls();
    await _pageController.animateToPage(
      index,
      duration: const Duration(milliseconds: 320),
      curve: Curves.easeOutCubic,
    );
  }

  bool _handleScrollNotification(ScrollNotification notification) {
    if (notification is! OverscrollNotification) {
      return false;
    }
    final atStart = notification.metrics.pixels <= notification.metrics.minScrollExtent;
    final atEnd = notification.metrics.pixels >= notification.metrics.maxScrollExtent;
    if ((atStart && notification.overscroll < 0) || (atEnd && notification.overscroll > 0)) {
      final now = DateTime.now();
      if (_lastBoundaryMessageAt == null ||
          now.difference(_lastBoundaryMessageAt!) > const Duration(milliseconds: 900)) {
        _lastBoundaryMessageAt = now;
        final message = atStart ? '已经是第一个啦' : '已经是最后一个啦';
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(
            SnackBar(duration: const Duration(milliseconds: 900), content: Text(message)),
          );
      }
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF151B22),
      body: ListenableBuilder(
        listenable: widget.viewModel,
        builder: (context, _) => LayoutBuilder(
          builder: (context, constraints) {
            final desktop = widget.desktopNavigationEnabled && constraints.maxWidth >= 1024;
            final compact = constraints.maxHeight < 500;
            final textExtra = (MediaQuery.textScalerOf(context).scale(14) - 14).clamp(0, 60);
            return Stack(
              fit: StackFit.expand,
              children: [
                AnimatedSwitcher(
                  duration: MediaQuery.disableAnimationsOf(context)
                      ? Duration.zero
                      : const Duration(milliseconds: 420),
                  child: SizedBox.expand(
                    key: ValueKey(widget.viewModel.currentItem.id),
                    child: ViewerBackdrop(
                      image: NetworkImage(widget.viewModel.currentItem.coverUri.toString()),
                    ),
                  ),
                ),
                SafeArea(
                  child: NotificationListener<ScrollNotification>(
                    onNotification: _handleScrollNotification,
                    child: PageView.builder(
                      key: const Key('纵向视频列表'),
                      controller: _pageController,
                      scrollDirection: Axis.vertical,
                      itemCount: widget.viewModel.items.length,
                      allowImplicitScrolling: true,
                      onPageChanged: _changePage,
                      itemBuilder: (context, index) => _VideoPage(
                        video: widget.viewModel.items[index],
                        controller: widget.viewModel.controllerAt(index),
                        errorMessage: index == widget.viewModel.currentIndex
                            ? widget.viewModel.currentErrorMessage
                            : widget.viewModel.controllerAt(index)?.snapshot.errorMessage,
                        padding: EdgeInsets.fromLTRB(
                          desktop ? 100 : 0,
                          compact ? 64 : 80,
                          desktop ? 100 : 0,
                          (compact ? 112 : 144) + textExtra * 2,
                        ),
                        onTap: _togglePlayback,
                        onRetry: index == widget.viewModel.currentIndex
                            ? widget.viewModel.retryCurrent
                            : null,
                      ),
                    ),
                  ),
                ),
                if (desktop) ..._buildDesktopNavigation(),
                _buildTopControls(desktop),
                _buildBottomControls(desktop, compact),
                _buildCenterFeedback(),
              ],
            );
          },
        ),
      ),
    );
  }

  List<Widget> _buildDesktopNavigation() {
    final index = widget.viewModel.currentIndex;
    return [
      if (index > 0)
        Positioned(
          left: 28,
          top: 0,
          bottom: 0,
          child: Center(
            child: ViewerButton(
              key: const Key('上一个视频按钮'),
              label: '上一个视频',
              icon: Icons.chevron_left_rounded,
              large: true,
              onPressed: () => _navigateToPage(index - 1),
            ),
          ),
        ),
      if (index < widget.viewModel.items.length - 1)
        Positioned(
          right: 28,
          top: 0,
          bottom: 0,
          child: Center(
            child: ViewerButton(
              key: const Key('下一个视频按钮'),
              label: '下一个视频',
              icon: Icons.chevron_right_rounded,
              large: true,
              onPressed: () => _navigateToPage(index + 1),
            ),
          ),
        ),
    ];
  }

  Widget _buildTopControls(bool desktop) => Positioned(
    top: 0,
    left: 0,
    right: 0,
    child: ViewerChrome(
      visible: _controlsVisible,
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: EdgeInsets.fromLTRB(desktop ? 32 : 16, 12, desktop ? 32 : 20, 24),
          child: Row(
            children: [
              ViewerButton(
                key: const Key('返回首页按钮'),
                label: '返回列表',
                icon: Icons.arrow_back_rounded,
                onPressed: () => Navigator.of(context).pop(),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Text(
                  widget.title,
                  key: const Key('视频来源标题'),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.09),
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
                ),
                child: Text(
                  '${widget.viewModel.currentIndex + 1} / ${widget.viewModel.items.length}',
                  key: const Key('视频序号'),
                  semanticsLabel:
                      '第 ${widget.viewModel.currentIndex + 1} 个，共 ${widget.viewModel.items.length} 个视频',
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
  );

  Widget _buildBottomControls(bool desktop, bool compact) {
    final controller = widget.viewModel.currentController;
    return Positioned(
      left: 0,
      right: 0,
      bottom: 0,
      child: ViewerChrome(
        visible: _controlsVisible || widget.viewModel.isMutedForAutoPlay,
        bottom: true,
        child: SafeArea(
          top: false,
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 960),
              child: Padding(
                padding: EdgeInsets.fromLTRB(
                  desktop ? 28 : 16,
                  16,
                  desktop ? 28 : 16,
                  compact ? 8 : 18,
                ),
                child: ListenableBuilder(
                  listenable: controller ?? widget.viewModel,
                  builder: (context, _) {
                    final snapshot = widget.viewModel.currentSnapshot;
                    final durationMs = snapshot.duration.inMilliseconds;
                    final position = _dragPosition ?? snapshot.position;
                    final positionMs = position.inMilliseconds.clamp(
                      0,
                      durationMs > 0 ? durationMs : 1,
                    );
                    final canControl =
                        snapshot.isInitialized && widget.viewModel.currentErrorMessage == null;
                    return Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        ConstrainedBox(
                          constraints: const BoxConstraints(minHeight: 48),
                          child: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  widget.viewModel.currentItem.title,
                                  key: const Key('视频文件名'),
                                  textAlign: TextAlign.center,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    color: Colors.white70,
                                    fontSize: 13,
                                    height: 1.5,
                                  ),
                                ),
                              ),
                              if (widget.viewModel.isMutedForAutoPlay && snapshot.isPlaying) ...[
                                const SizedBox(width: 12),
                                TextButton.icon(
                                  key: const Key('开启声音按钮'),
                                  onPressed: () {
                                    _showControls();
                                    widget.viewModel.enableSound();
                                  },
                                  style: TextButton.styleFrom(
                                    foregroundColor: Colors.white,
                                    backgroundColor: Colors.white.withValues(alpha: 0.08),
                                    minimumSize: const Size(48, 48),
                                    padding: const EdgeInsets.symmetric(horizontal: 14),
                                    textStyle: const TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                  icon: const Icon(Icons.volume_up_rounded, size: 18),
                                  label: const Text('点击开启声音'),
                                ),
                              ],
                            ],
                          ),
                        ),
                        Row(
                          children: [
                            IconButton(
                              key: const Key('底部播放按钮'),
                              tooltip: snapshot.isPlaying
                                  ? '暂停视频'
                                  : snapshot.isCompleted
                                  ? '重新播放'
                                  : '播放视频',
                              onPressed: canControl && !widget.viewModel.isAutoPlayPending
                                  ? _togglePlayback
                                  : null,
                              icon: Icon(
                                snapshot.isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                              ),
                              color: Colors.white,
                              disabledColor: Colors.white30,
                              constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
                            ),
                            _TimeLabel(_formatDuration(position)),
                            Expanded(
                              child: SliderTheme(
                                data: SliderTheme.of(context).copyWith(
                                  activeTrackColor: Colors.white.withValues(alpha: 0.9),
                                  inactiveTrackColor: Colors.white.withValues(alpha: 0.18),
                                  thumbColor: Colors.white,
                                  overlayColor: Colors.white.withValues(alpha: 0.12),
                                  trackHeight: 3,
                                  thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 5),
                                  overlayShape: const RoundSliderOverlayShape(overlayRadius: 18),
                                ),
                                child: Slider(
                                  key: const Key('视频进度条'),
                                  semanticFormatterCallback: (value) =>
                                      '播放位置 ${_formatDuration(Duration(milliseconds: value.round()))}',
                                  value: positionMs.toDouble(),
                                  max: (durationMs > 0 ? durationMs : 1).toDouble(),
                                  onChangeStart: canControl
                                      ? (value) {
                                          _showControls();
                                          _hideControlsTimer?.cancel();
                                          setState(
                                            () => _dragPosition = Duration(
                                              milliseconds: value.round(),
                                            ),
                                          );
                                          widget.viewModel.beginSeek();
                                        }
                                      : null,
                                  onChanged: canControl
                                      ? (value) {
                                          setState(
                                            () => _dragPosition = Duration(
                                              milliseconds: value.round(),
                                            ),
                                          );
                                        }
                                      : null,
                                  onChangeEnd: canControl
                                      ? (value) async {
                                          await widget.viewModel.completeSeek(
                                            Duration(milliseconds: value.round()),
                                          );
                                          if (mounted) {
                                            setState(() => _dragPosition = null);
                                            _scheduleControlsHide();
                                          }
                                        }
                                      : null,
                                ),
                              ),
                            ),
                            _TimeLabel(_formatDuration(snapshot.duration)),
                          ],
                        ),
                        if (!compact) ...[
                          const SizedBox(height: 6),
                          Text(
                            widget.viewModel.items.length == 1
                                ? '点击画面播放或暂停'
                                : desktop
                                ? '左右切换 · 点击画面暂停'
                                : '上下滑动切换 · 点击画面暂停',
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.42),
                              fontSize: 11,
                              letterSpacing: 0.5,
                            ),
                          ),
                        ],
                      ],
                    );
                  },
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildCenterFeedback() {
    final controller = widget.viewModel.currentController;
    if (controller == null) {
      return const IgnorePointer(
        child: Center(child: _LoadingFeedback(message: '正在准备视频…')),
      );
    }
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final snapshot = controller.snapshot;
        if (widget.viewModel.currentErrorMessage != null) {
          return const SizedBox.shrink();
        }
        if (!snapshot.isInitialized || snapshot.isBuffering) {
          return Center(
            child: _LoadingFeedback(
              message: !snapshot.isInitialized
                  ? '正在准备视频…'
                  : _isBufferingSlow
                  ? '网络有点慢，仍在努力加载'
                  : '正在缓冲，请稍候',
              onRetry: snapshot.isBuffering && _isBufferingSlow
                  ? widget.viewModel.retryCurrent
                  : null,
            ),
          );
        }
        if (widget.viewModel.isAutoPlayPending ||
            (snapshot.isPlaying && !widget.viewModel.requiresUserPlay)) {
          return const SizedBox.shrink();
        }
        return Center(
          child: Semantics(
            button: true,
            label: snapshot.isCompleted ? '重新播放' : '播放视频',
            child: Material(
              color: Colors.black.withValues(alpha: 0.42),
              shape: CircleBorder(side: BorderSide(color: Colors.white.withValues(alpha: 0.24))),
              child: InkWell(
                key: const Key('中央播放按钮'),
                customBorder: const CircleBorder(),
                onTap: _togglePlayback,
                child: SizedBox.square(
                  dimension: 72,
                  child: Icon(
                    snapshot.isCompleted ? Icons.replay_rounded : Icons.play_arrow_rounded,
                    color: Colors.white,
                    size: 36,
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  String _formatDuration(Duration duration) {
    final totalSeconds = duration.inSeconds.clamp(0, 359999);
    final hours = totalSeconds ~/ 3600;
    final minutes = (totalSeconds % 3600) ~/ 60;
    final seconds = totalSeconds % 60;
    if (hours > 0) {
      return '$hours:${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
    }
    return '$minutes:${seconds.toString().padLeft(2, '0')}';
  }
}

class _VideoPage extends StatelessWidget {
  const _VideoPage({
    required this.video,
    required this.controller,
    required this.errorMessage,
    required this.padding,
    required this.onTap,
    required this.onRetry,
  });
  final VideoItem video;
  final PlaybackController? controller;
  final String? errorMessage;
  final EdgeInsets padding;
  final VoidCallback onTap;
  final Future<void> Function()? onRetry;

  @override
  Widget build(BuildContext context) => GestureDetector(
    behavior: HitTestBehavior.opaque,
    onTap: onTap,
    child: Padding(
      padding: padding,
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1440),
          child: controller == null
              ? _cover()
              : ListenableBuilder(
                  listenable: controller!,
                  builder: (context, _) {
                    final snapshot = controller!.snapshot;
                    final resolvedError = errorMessage ?? snapshot.errorMessage;
                    if (resolvedError != null) {
                      return _VideoError(message: resolvedError, onRetry: onRetry);
                    }
                    if (!snapshot.isInitialized) {
                      return _cover();
                    }
                    return Center(
                      child: AspectRatio(
                        key: Key('视频画面-${video.id}'),
                        aspectRatio: snapshot.aspectRatio,
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(4),
                          child: ColoredBox(color: Colors.black, child: controller!.buildVideo()),
                        ),
                      ),
                    );
                  },
                ),
        ),
      ),
    ),
  );

  Widget _cover() => Image.network(
    video.coverUri.toString(),
    fit: BoxFit.contain,
    errorBuilder: (_, _, _) => const SizedBox.expand(),
  );
}

class _TimeLabel extends StatelessWidget {
  const _TimeLabel(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Text(
    text,
    style: const TextStyle(
      color: Colors.white60,
      fontSize: 11,
      fontWeight: FontWeight.w500,
      fontFeatures: [FontFeature.tabularFigures()],
    ),
  );
}

class _LoadingFeedback extends StatelessWidget {
  const _LoadingFeedback({required this.message, this.onRetry});
  final String message;
  final Future<void> Function()? onRetry;

  @override
  Widget build(BuildContext context) => Container(
    constraints: const BoxConstraints(maxWidth: 300),
    margin: const EdgeInsets.symmetric(horizontal: 24),
    padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 18),
    decoration: BoxDecoration(
      color: const Color(0xD91A1D21),
      borderRadius: BorderRadius.circular(18),
      border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
    ),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const SizedBox.square(
          dimension: 24,
          child: CircularProgressIndicator(color: Colors.white70, strokeWidth: 2),
        ),
        const SizedBox(height: 12),
        Text(
          message,
          textAlign: TextAlign.center,
          style: const TextStyle(color: Colors.white70, fontSize: 13, height: 1.5),
        ),
        if (onRetry != null) ...[
          const SizedBox(height: 8),
          TextButton.icon(
            key: const Key('缓冲重新加载按钮'),
            onPressed: onRetry,
            style: TextButton.styleFrom(foregroundColor: Colors.white),
            icon: const Icon(Icons.refresh_rounded, size: 18),
            label: const Text('重新加载'),
          ),
        ],
      ],
    ),
  );
}

class _VideoError extends StatelessWidget {
  const _VideoError({required this.message, required this.onRetry});
  final String message;
  final Future<void> Function()? onRetry;

  @override
  Widget build(BuildContext context) => Center(
    child: SingleChildScrollView(
      child: Container(
        constraints: const BoxConstraints(maxWidth: 340),
        margin: const EdgeInsets.all(20),
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: const Color(0xD91A1D21),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.videocam_off_outlined, color: Colors.white54, size: 32),
            const SizedBox(height: 16),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white70, fontSize: 14, height: 1.6),
            ),
            const SizedBox(height: 16),
            TextButton.icon(
              key: const Key('视频错误重试按钮'),
              onPressed: onRetry,
              style: TextButton.styleFrom(foregroundColor: Colors.white),
              icon: const Icon(Icons.refresh_rounded, size: 18),
              label: const Text('重新加载'),
            ),
          ],
        ),
      ),
    ),
  );
}
