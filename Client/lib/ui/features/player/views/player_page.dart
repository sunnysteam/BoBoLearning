import 'dart:async';

import 'package:bobo_learning/domain/models/video_item.dart';
import 'package:bobo_learning/ui/core/app_theme.dart';
import 'package:bobo_learning/ui/features/player/services/playback_controller.dart';
import 'package:bobo_learning/ui/features/player/view_models/player_view_model.dart';
import 'package:flutter/material.dart';

class PlayerPage extends StatefulWidget {
  const PlayerPage({required this.viewModel, super.key});

  final PlayerViewModel viewModel;

  @override
  State<PlayerPage> createState() => _PlayerPageState();
}

class _PlayerPageState extends State<PlayerPage> {
  late final PageController _pageController;
  PlaybackController? _observedController;
  Timer? _hideControlsTimer;
  bool _controlsVisible = true;
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
    if (!mounted || snapshot == null || _controlsVisible) {
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
      if (mounted && widget.viewModel.currentSnapshot.isPlaying) {
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
    setState(() {
      _dragPosition = null;
      _controlsVisible = true;
    });
    await widget.viewModel.changePage(index);
    if (mounted) {
      _scheduleControlsHide();
    }
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
      backgroundColor: AppColors.player,
      body: SafeArea(
        child: ListenableBuilder(
          listenable: widget.viewModel,
          builder: (context, _) {
            return Stack(
              fit: StackFit.expand,
              children: [
                NotificationListener<ScrollNotification>(
                  onNotification: _handleScrollNotification,
                  child: PageView.builder(
                    key: const Key('纵向视频列表'),
                    controller: _pageController,
                    scrollDirection: Axis.vertical,
                    itemCount: widget.viewModel.items.length,
                    allowImplicitScrolling: true,
                    onPageChanged: _changePage,
                    itemBuilder: (context, index) {
                      return _VideoPage(
                        video: widget.viewModel.items[index],
                        controller: widget.viewModel.controllerAt(index),
                        onTap: _togglePlayback,
                        onRetry: index == widget.viewModel.currentIndex
                            ? widget.viewModel.retryCurrent
                            : null,
                      );
                    },
                  ),
                ),
                _buildTopControls(),
                _buildBottomControls(),
                _buildCenterFeedback(),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _buildTopControls() {
    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      child: IgnorePointer(
        ignoring: !_controlsVisible,
        child: AnimatedOpacity(
          opacity: _controlsVisible ? 1 : 0,
          duration: const Duration(milliseconds: 220),
          child: DecoratedBox(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Color(0xC810263A), Color(0x0010263A)],
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 16, 32),
              child: Row(
                children: [
                  _RoundControlButton(
                    key: const Key('返回首页按钮'),
                    tooltip: '返回首页',
                    icon: Icons.arrow_back_rounded,
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      widget.viewModel.currentItem.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        color: Colors.white,
                        shadows: const [Shadow(color: Colors.black38, blurRadius: 12)],
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  DecoratedBox(
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.14),
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(color: Colors.white.withValues(alpha: 0.16)),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 9),
                      child: Text(
                        '${widget.viewModel.currentIndex + 1} / ${widget.viewModel.items.length}',
                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildBottomControls() {
    final controller = widget.viewModel.currentController;
    return Positioned(
      left: 0,
      right: 0,
      bottom: 0,
      child: IgnorePointer(
        ignoring: !_controlsVisible,
        child: AnimatedOpacity(
          opacity: _controlsVisible ? 1 : 0,
          duration: const Duration(milliseconds: 220),
          child: DecoratedBox(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.bottomCenter,
                end: Alignment.topCenter,
                colors: [Color(0xE610263A), Color(0x0010263A)],
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 42, 20, 18),
              child: controller == null
                  ? const SizedBox(height: 52)
                  : ListenableBuilder(
                      listenable: controller,
                      builder: (context, _) {
                        final snapshot = controller.snapshot;
                        final durationMs = snapshot.duration.inMilliseconds;
                        final positionMs = (_dragPosition ?? snapshot.position).inMilliseconds
                            .clamp(0, durationMs > 0 ? durationMs : 1);
                        return Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            SliderTheme(
                              data: SliderTheme.of(context).copyWith(
                                activeTrackColor: AppColors.sunshine,
                                inactiveTrackColor: Colors.white24,
                                thumbColor: Colors.white,
                                overlayColor: AppColors.sunshine.withValues(alpha: 0.2),
                                trackHeight: 6,
                                thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 10),
                                overlayShape: const RoundSliderOverlayShape(overlayRadius: 22),
                              ),
                              child: Slider(
                                key: const Key('视频进度条'),
                                value: positionMs.toDouble(),
                                max: (durationMs > 0 ? durationMs : 1).toDouble(),
                                onChangeStart: snapshot.isInitialized
                                    ? (value) {
                                        _showControls();
                                        setState(
                                          () =>
                                              _dragPosition = Duration(milliseconds: value.round()),
                                        );
                                        widget.viewModel.beginSeek();
                                      }
                                    : null,
                                onChanged: snapshot.isInitialized
                                    ? (value) {
                                        setState(
                                          () =>
                                              _dragPosition = Duration(milliseconds: value.round()),
                                        );
                                      }
                                    : null,
                                onChangeEnd: snapshot.isInitialized
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
                            Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 8),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Text(
                                    _formatDuration(_dragPosition ?? snapshot.position),
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                  Text(
                                    _formatDuration(snapshot.duration),
                                    style: const TextStyle(
                                      color: Colors.white70,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        );
                      },
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
      return const Center(child: CircularProgressIndicator(color: AppColors.sunshine));
    }
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final snapshot = controller.snapshot;
        if (snapshot.isBuffering && snapshot.errorMessage == null) {
          return const IgnorePointer(
            child: Center(child: CircularProgressIndicator(color: AppColors.sunshine)),
          );
        }
        if (snapshot.errorMessage != null) {
          return const SizedBox.shrink();
        }
        if (snapshot.isPlaying && !widget.viewModel.requiresUserPlay) {
          return const SizedBox.shrink();
        }

        return Center(
          child: Semantics(
            button: true,
            label: snapshot.isCompleted ? '重新播放' : '播放视频',
            child: Material(
              color: AppColors.sunshine,
              shape: const CircleBorder(),
              elevation: 12,
              shadowColor: Colors.black45,
              child: InkWell(
                key: const Key('中央播放按钮'),
                customBorder: const CircleBorder(),
                onTap: _togglePlayback,
                child: SizedBox.square(
                  dimension: 88,
                  child: Icon(
                    snapshot.isCompleted ? Icons.replay_rounded : Icons.play_arrow_rounded,
                    color: AppColors.ink,
                    size: 48,
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
    required this.onTap,
    required this.onRetry,
  });

  final VideoItem video;
  final PlaybackController? controller;
  final VoidCallback onTap;
  final Future<void> Function()? onRetry;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1440),
          child: controller == null
              ? _VideoLoadingCover(video: video)
              : ListenableBuilder(
                  listenable: controller!,
                  builder: (context, _) {
                    final snapshot = controller!.snapshot;
                    if (snapshot.errorMessage != null) {
                      return _VideoError(message: snapshot.errorMessage!, onRetry: onRetry);
                    }
                    if (!snapshot.isInitialized) {
                      return _VideoLoadingCover(video: video);
                    }
                    return Center(
                      child: AspectRatio(
                        aspectRatio: snapshot.aspectRatio,
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(18),
                          child: ColoredBox(color: Colors.black, child: controller!.buildVideo()),
                        ),
                      ),
                    );
                  },
                ),
        ),
      ),
    );
  }
}

class _VideoLoadingCover extends StatelessWidget {
  const _VideoLoadingCover({required this.video});

  final VideoItem video;

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        Center(
          child: AspectRatio(
            aspectRatio: 16 / 9,
            child: Hero(
              tag: '封面-${video.id}',
              child: Image.network(
                video.coverUri.toString(),
                fit: BoxFit.cover,
                errorBuilder: (context, error, stackTrace) {
                  return const ColoredBox(color: AppColors.player);
                },
              ),
            ),
          ),
        ),
        ColoredBox(color: AppColors.player.withValues(alpha: 0.52)),
        const Center(child: CircularProgressIndicator(color: AppColors.sunshine)),
      ],
    );
  }
}

class _VideoError extends StatelessWidget {
  const _VideoError({required this.message, required this.onRetry});

  final String message;
  final Future<void> Function()? onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 380),
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.sentiment_dissatisfied_rounded, color: AppColors.coral, size: 64),
              const SizedBox(height: 18),
              Text(
                message,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.titleLarge?.copyWith(color: Colors.white),
              ),
              const SizedBox(height: 20),
              FilledButton.icon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh_rounded),
                label: const Text('重新加载'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RoundControlButton extends StatelessWidget {
  const _RoundControlButton({
    required this.tooltip,
    required this.icon,
    required this.onPressed,
    super.key,
  });

  final String tooltip;
  final IconData icon;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return IconButton.filledTonal(
      tooltip: tooltip,
      onPressed: onPressed,
      style: IconButton.styleFrom(
        backgroundColor: Colors.white.withValues(alpha: 0.16),
        foregroundColor: Colors.white,
        side: BorderSide(color: Colors.white.withValues(alpha: 0.16)),
      ),
      icon: Icon(icon),
    );
  }
}
