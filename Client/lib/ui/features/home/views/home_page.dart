import 'package:bobo_learning/domain/models/video_item.dart';
import 'package:bobo_learning/ui/core/app_theme.dart';
import 'package:bobo_learning/ui/core/playful_backdrop.dart';
import 'package:bobo_learning/ui/features/home/view_models/home_view_model.dart';
import 'package:bobo_learning/ui/features/home/views/folder_page.dart';
import 'package:bobo_learning/ui/features/home/widgets/video_card.dart';
import 'package:bobo_learning/ui/features/player/services/playback_controller.dart';
import 'package:bobo_learning/ui/features/player/view_models/player_view_model.dart';
import 'package:bobo_learning/ui/features/player/views/player_page.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

class HomePage extends StatefulWidget {
  const HomePage({required this.viewModel, required this.playbackControllerFactory, super.key});

  final HomeViewModel viewModel;
  final PlaybackControllerFactory playbackControllerFactory;

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> with WidgetsBindingObserver {
  String? _lastTransientMessage;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    widget.viewModel.addListener(_showTransientMessage);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && widget.viewModel.state == HomeLoadState.initial) {
        widget.viewModel.loadInitial();
      }
    });
  }

  @override
  void didUpdateWidget(covariant HomePage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.viewModel != widget.viewModel) {
      oldWidget.viewModel.removeListener(_showTransientMessage);
      widget.viewModel.addListener(_showTransientMessage);
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && widget.viewModel.items.isNotEmpty) {
      widget.viewModel.refresh(silent: true);
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    widget.viewModel.removeListener(_showTransientMessage);
    super.dispose();
  }

  void _showTransientMessage() {
    final message = widget.viewModel.transientMessage;
    if (message == null || message == _lastTransientMessage) {
      return;
    }
    _lastTransientMessage = message;
    widget.viewModel.clearTransientMessage();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(message)));
    });
  }

  Future<void> _openPlayer(VideoFolderGroup group, int index) async {
    final playerViewModel = PlayerViewModel(
      items: group.items,
      initialIndex: index,
      controllerFactory: widget.playbackControllerFactory,
    );
    await Navigator.of(
      context,
    ).push<void>(MaterialPageRoute<void>(builder: (_) => PlayerPage(viewModel: playerViewModel)));
    if (mounted) {
      await widget.viewModel.refresh(silent: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: PlayfulBackdrop(
        child: SafeArea(
          bottom: false,
          child: LayoutBuilder(
            builder: (context, constraints) {
              final sidePadding = constraints.maxWidth > 1220
                  ? (constraints.maxWidth - 1180) / 2
                  : constraints.maxWidth >= 700
                  ? 32.0
                  : 16.0;
              return ListenableBuilder(
                listenable: widget.viewModel,
                builder: (context, _) {
                  return RefreshIndicator(
                    color: AppColors.teal,
                    backgroundColor: AppColors.paper,
                    onRefresh: widget.viewModel.refresh,
                    child: CustomScrollView(
                      key: const Key('首页滚动区域'),
                      physics: const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics()),
                      slivers: [
                        SliverPadding(
                          padding: EdgeInsets.fromLTRB(sidePadding, 24, sidePadding, 22),
                          sliver: SliverToBoxAdapter(
                            child: _HomeHeader(
                              videoCount: widget.viewModel.items.length,
                              isRefreshing: widget.viewModel.isRefreshing,
                              onRefresh: () => widget.viewModel.refresh(silent: true),
                            ),
                          ),
                        ),
                        ..._buildContent(sidePadding),
                        const SliverToBoxAdapter(child: SizedBox(height: 32)),
                      ],
                    ),
                  );
                },
              );
            },
          ),
        ),
      ),
    );
  }

  List<Widget> _buildContent(double sidePadding) {
    switch (widget.viewModel.state) {
      case HomeLoadState.initial:
      case HomeLoadState.loading:
        return [_LoadingGrid(sidePadding: sidePadding)];
      case HomeLoadState.empty:
        return [const SliverFillRemaining(hasScrollBody: false, child: _EmptyState())];
      case HomeLoadState.error:
        return [
          SliverFillRemaining(
            hasScrollBody: false,
            child: _ErrorState(
              message: widget.viewModel.errorMessage ?? '暂时拿不到视频',
              onRetry: widget.viewModel.loadInitial,
            ),
          ),
        ];
      case HomeLoadState.ready:
        return [
          for (final (groupIndex, group) in widget.viewModel.groups.indexed) ...[
            SliverPadding(
              padding: EdgeInsets.fromLTRB(sidePadding, groupIndex == 0 ? 0 : 32, sidePadding, 14),
              sliver: SliverToBoxAdapter(child: _FolderHeader(group: group)),
            ),
            SliverPadding(
              padding: EdgeInsets.symmetric(horizontal: sidePadding),
              sliver: SliverGrid(
                gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                  maxCrossAxisExtent: 270,
                  childAspectRatio: 0.82,
                  crossAxisSpacing: 16,
                  mainAxisSpacing: 18,
                ),
                delegate: SliverChildBuilderDelegate(
                  (context, index) => _VideoCard(
                    key: ValueKey(group.items[index].id),
                    video: group.items[index],
                    colorIndex: groupIndex * 3 + index,
                    onTap: () => _openPlayer(group, index),
                  ),
                  childCount: group.items.length,
                ),
              ),
            ),
          ],
        ];
    }
  }
}

class _HomeHeader extends StatelessWidget {
  const _HomeHeader({
    required this.videoCount,
    required this.isRefreshing,
    required this.onRefresh,
  });

  final int videoCount;
  final bool isRefreshing;
  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 650;
        final brand = Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const _BrandMark(),
            const SizedBox(width: 14),
            Flexible(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'BoBo Learning',
                    style: Theme.of(context).textTheme.headlineMedium
                        ?.copyWith(fontSize: compact ? 26 : 32, letterSpacing: -0.8),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    '发现一个好奇心满满的今天',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontSize: 15),
                  ),
                ],
              ),
            ),
          ],
        );

        final countPill = DecoratedBox(
          decoration: BoxDecoration(
            color: AppColors.paper.withValues(alpha: 0.9),
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: AppColors.teal.withValues(alpha: 0.18)),
            boxShadow: [
              BoxShadow(
                color: AppColors.ink.withValues(alpha: 0.06),
                blurRadius: 18,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(18, 8, 8, 8),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  videoCount == 0 ? '等待新故事' : '$videoCount 个快乐视频',
                  style: Theme.of(context).textTheme.labelLarge
                      ?.copyWith(color: AppColors.tealDark),
                ),
                const SizedBox(width: 6),
                IconButton(
                  key: const Key('首页刷新按钮'),
                  tooltip: '刷新视频',
                  onPressed: isRefreshing ? null : onRefresh,
                  icon: isRefreshing
                      ? const SizedBox.square(
                          dimension: 22,
                          child: CircularProgressIndicator(strokeWidth: 2.5),
                        )
                      : const Icon(Icons.refresh_rounded),
                ),
              ],
            ),
          ),
        );

        if (compact) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [brand, const SizedBox(height: 20), countPill],
          );
        }
        return Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Expanded(child: brand),
            const SizedBox(width: 24),
            countPill,
          ],
        );
      },
    );
  }
}

class _BrandMark extends StatelessWidget {
  const _BrandMark();

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'BoBo Learning 标志',
      child: SizedBox.square(
        dimension: 64,
        child: Stack(
          alignment: Alignment.center,
          children: [
            Transform.rotate(
              angle: -0.12,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: AppColors.teal,
                  borderRadius: BorderRadius.circular(21),
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.teal.withValues(alpha: 0.24),
                      blurRadius: 18,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                child: const SizedBox.square(dimension: 56),
              ),
            ),
            const Icon(Icons.auto_stories_rounded, color: Colors.white, size: 31),
            const Positioned(
              right: 1,
              top: 1,
              child: DecoratedBox(
                decoration: BoxDecoration(color: AppColors.sunshine, shape: BoxShape.circle),
                child: SizedBox.square(dimension: 17),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FolderHeader extends StatelessWidget {
  const _FolderHeader({required this.group});

  final VideoFolderGroup group;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      header: true,
      child: Row(
        key: Key('分类标题-${group.displayName}'),
        children: [
          DecoratedBox(
            decoration: BoxDecoration(
              color: AppColors.teal.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(15),
            ),
            child: const SizedBox.square(
              dimension: 44,
              child: Icon(Icons.folder_rounded, color: AppColors.tealDark, size: 26),
            ),
          ),
          const SizedBox(width: 12),
          Flexible(
            child: Text(
              group.displayName,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.titleLarge
                  ?.copyWith(color: AppColors.ink, fontWeight: FontWeight.w900),
            ),
          ),
          const SizedBox(width: 10),
          DecoratedBox(
            decoration: BoxDecoration(
              color: AppColors.sunshine.withValues(alpha: 0.28),
              borderRadius: BorderRadius.circular(999),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
              child: Text(
                '${group.items.length} 个视频',
                style: Theme.of(context).textTheme.labelMedium
                    ?.copyWith(color: AppColors.ink, fontWeight: FontWeight.w800),
              ),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(child: Divider(color: AppColors.teal.withValues(alpha: 0.14), thickness: 1.4)),
        ],
      ),
    );
  }
}

class _VideoCard extends StatelessWidget {
  const _VideoCard({required this.video, required this.colorIndex, required this.onTap, super.key});

  final VideoItem video;
  final int colorIndex;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    const accentColors = [AppColors.teal, AppColors.coral, AppColors.sky, AppColors.sunshine];
    final accent = accentColors[colorIndex % accentColors.length];
    return Semantics(
      button: true,
      label: '播放${video.title}',
      child: Material(
        color: AppColors.paper,
        elevation: 0,
        shadowColor: AppColors.ink.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(26),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          key: Key('视频卡片-${video.id}'),
          onTap: onTap,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    Hero(
                      tag: '封面-${video.id}',
                      child: Image.network(
                        video.coverUri.toString(),
                        fit: BoxFit.cover,
                        loadingBuilder: (context, child, progress) {
                          if (progress == null) {
                            return child;
                          }
                          return _CoverPlaceholder(accent: accent, loading: true);
                        },
                        errorBuilder: (context, error, stackTrace) {
                          return _CoverPlaceholder(accent: accent, loading: false);
                        },
                      ),
                    ),
                    Positioned(
                      right: 12,
                      bottom: 12,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.94),
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                              color: AppColors.ink.withValues(alpha: 0.15),
                              blurRadius: 12,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        child: Padding(
                          padding: const EdgeInsets.all(10),
                          child: Icon(Icons.play_arrow_rounded, color: accent, size: 28),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 14, 15),
                child: Row(
                  children: [
                    DecoratedBox(
                      decoration: BoxDecoration(color: accent, shape: BoxShape.circle),
                      child: const SizedBox.square(dimension: 9),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        video.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CoverPlaceholder extends StatelessWidget {
  const _CoverPlaceholder({required this.accent, required this.loading});

  final Color accent;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [accent.withValues(alpha: 0.22), accent.withValues(alpha: 0.08)],
        ),
      ),
      child: Center(
        child: loading
            ? CircularProgressIndicator(color: accent, strokeWidth: 3)
            : Icon(Icons.image_not_supported_rounded, color: accent, size: 42),
      ),
    );
  }
}

class _LoadingGrid extends StatelessWidget {
  const _LoadingGrid({required this.sidePadding});

  final double sidePadding;

  @override
  Widget build(BuildContext context) {
    return SliverPadding(
      padding: EdgeInsets.symmetric(horizontal: sidePadding),
      sliver: SliverGrid(
        gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
          maxCrossAxisExtent: 270,
          childAspectRatio: 0.82,
          crossAxisSpacing: 16,
          mainAxisSpacing: 18,
        ),
        delegate: SliverChildBuilderDelegate(
          (context, index) => DecoratedBox(
            decoration: BoxDecoration(
              color: AppColors.paper.withValues(alpha: 0.84),
              borderRadius: BorderRadius.circular(26),
            ),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: AppColors.teal.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(18),
                      ),
                      child: const SizedBox.expand(),
                    ),
                  ),
                  const SizedBox(height: 14),
                  FractionallySizedBox(
                    widthFactor: 0.68,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: AppColors.ink.withValues(alpha: 0.09),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const SizedBox(height: 17),
                    ),
                  ),
                ],
              ),
            ),
          ),
          childCount: 8,
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 440),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(28, 20, 28, 80),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const _ToyShelfIcon(icon: Icons.video_library_rounded, accent: AppColors.sunshine),
              const SizedBox(height: 28),
              Text('故事正在赶来的路上', style: Theme.of(context).textTheme.headlineMedium),
              const SizedBox(height: 12),
              Text(
                '把视频和同名封面放进资源文件夹，\n它们很快就会出现在这里。',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyLarge?.copyWith(color: AppColors.mutedInk),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(28, 20, 28, 80),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const _ToyShelfIcon(icon: Icons.wifi_off_rounded, accent: AppColors.coral),
              const SizedBox(height: 28),
              Text('连接迷路啦', style: Theme.of(context).textTheme.headlineMedium),
              const SizedBox(height: 12),
              Text(
                message,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyLarge?.copyWith(color: AppColors.mutedInk),
              ),
              const SizedBox(height: 24),
              FilledButton.icon(
                key: const Key('重试按钮'),
                onPressed: onRetry,
                icon: const Icon(Icons.refresh_rounded),
                label: const Text('再试一次'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ToyShelfIcon extends StatelessWidget {
  const _ToyShelfIcon({required this.icon, required this.accent});

  final IconData icon;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 152,
      height: 118,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Positioned(
            left: 4,
            bottom: 4,
            child: Transform.rotate(
              angle: -0.08,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: AppColors.sky.withValues(alpha: 0.65),
                  borderRadius: BorderRadius.circular(24),
                ),
                child: const SizedBox(width: 72, height: 72),
              ),
            ),
          ),
          Positioned(
            right: 6,
            bottom: 0,
            child: Transform.rotate(
              angle: 0.08,
              child: DecoratedBox(
                decoration: BoxDecoration(color: accent, borderRadius: BorderRadius.circular(26)),
                child: SizedBox(
                  width: 92,
                  height: 92,
                  child: Icon(icon, size: 46, color: AppColors.ink.withValues(alpha: 0.76)),
                ),
              ),
            ),
          ),
          const Positioned(
            top: 0,
            right: 24,
            child: Icon(Icons.auto_awesome_rounded, color: AppColors.coral, size: 27),
          ),
        ],
      ),
    );
  }
}
