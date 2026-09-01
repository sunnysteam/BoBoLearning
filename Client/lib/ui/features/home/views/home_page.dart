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

  Future<void> _openFolder(VideoFolderGroup group) async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => FolderPage(
          folderName: group.displayName,
          items: group.items,
          playbackControllerFactory: widget.playbackControllerFactory,
        ),
      ),
    );
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
              final compact = constraints.maxWidth < 600;
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
                          padding: EdgeInsets.fromLTRB(
                            sidePadding,
                            compact ? 20 : 24,
                            sidePadding,
                            compact ? 18 : 22,
                          ),
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
        return [_LoadingSections(sidePadding: sidePadding)];
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
              sliver: SliverToBoxAdapter(
                child: _FolderVideoStrip(
                  group: group,
                  colorOffset: groupIndex * 3,
                  onVideoTap: (index) => _openPlayer(group, index),
                  onViewMore: () => _openFolder(group),
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
        final compact = constraints.maxWidth < 600;
        final countLabel = videoCount == 0 ? '等待新故事' : '$videoCount 个快乐视频';
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
                    '菠萝早教',
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
                  countLabel,
                  key: const Key('首页视频总数'),
                  style: Theme.of(context).textTheme.labelLarge
                      ?.copyWith(color: AppColors.tealDark),
                ),
                const SizedBox(width: 6),
                _buildRefreshButton(),
              ],
            ),
          ),
        );

        if (compact) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              brand,
              const SizedBox(height: 14),
              Row(
                key: const Key('小屏顶部操作区'),
                children: [
                  Expanded(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: AppColors.teal.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(color: AppColors.teal.withValues(alpha: 0.13)),
                      ),
                      child: SizedBox(
                        height: 56,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          child: Row(
                            children: [
                              const Icon(
                                Icons.video_collection_rounded,
                                color: AppColors.tealDark,
                                size: 22,
                              ),
                              const SizedBox(width: 9),
                              Text(
                                countLabel,
                                key: const Key('首页视频总数'),
                                style: Theme.of(context).textTheme.labelLarge
                                    ?.copyWith(color: AppColors.tealDark),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  _buildRefreshButton(standalone: true),
                ],
              ),
            ],
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

  Widget _buildRefreshButton({bool standalone = false}) {
    return IconButton(
      key: const Key('首页刷新按钮'),
      tooltip: '刷新视频',
      onPressed: isRefreshing ? null : onRefresh,
      style: standalone
          ? IconButton.styleFrom(
              minimumSize: const Size.square(56),
              maximumSize: const Size.square(56),
              backgroundColor: AppColors.paper.withValues(alpha: 0.92),
              foregroundColor: AppColors.tealDark,
              side: BorderSide(color: AppColors.teal.withValues(alpha: 0.16)),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
            )
          : null,
      icon: isRefreshing
          ? const SizedBox.square(dimension: 22, child: CircularProgressIndicator(strokeWidth: 2.5))
          : const Icon(Icons.refresh_rounded),
    );
  }
}

class _BrandMark extends StatelessWidget {
  const _BrandMark();

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: '菠萝早教标志',
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: AppColors.sunshine.withValues(alpha: 0.3)),
          boxShadow: [
            BoxShadow(
              color: AppColors.sunshine.withValues(alpha: 0.22),
              blurRadius: 18,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(19),
          child: Image.asset(
            'assets/branding/pineapple_icon.png',
            key: const Key('菠萝早教品牌图标'),
            width: 64,
            height: 64,
            fit: BoxFit.cover,
            filterQuality: FilterQuality.high,
            excludeFromSemantics: true,
          ),
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
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth < 600;
          final folderIcon = DecoratedBox(
            decoration: BoxDecoration(
              color: AppColors.teal.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(15),
            ),
            child: const SizedBox.square(
              dimension: 44,
              child: Icon(Icons.folder_rounded, color: AppColors.tealDark, size: 26),
            ),
          );
          final folderName = Text(
            group.displayName,
            key: Key('分类名称-${group.displayName}'),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
              color: AppColors.ink,
              fontSize: compact ? 20 : null,
              height: compact ? 1.16 : null,
              fontWeight: FontWeight.w900,
            ),
          );
          final countBadge = DecoratedBox(
            key: Key('分类数量-${group.displayName}'),
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
          );
          final divider = Divider(color: AppColors.teal.withValues(alpha: 0.14), thickness: 1.4);

          if (compact) {
            return Column(
              key: Key('分类标题-${group.displayName}'),
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    folderIcon,
                    const SizedBox(width: 12),
                    Expanded(child: folderName),
                  ],
                ),
                const SizedBox(height: 8),
                Padding(
                  padding: const EdgeInsets.only(left: 56),
                  child: Row(
                    children: [
                      countBadge,
                      const SizedBox(width: 12),
                      Expanded(child: divider),
                    ],
                  ),
                ),
              ],
            );
          }

          return Row(
            key: Key('分类标题-${group.displayName}'),
            children: [
              folderIcon,
              const SizedBox(width: 12),
              Flexible(child: folderName),
              const SizedBox(width: 10),
              countBadge,
              const SizedBox(width: 14),
              Expanded(child: divider),
            ],
          );
        },
      ),
    );
  }
}

class _FolderVideoStrip extends StatefulWidget {
  const _FolderVideoStrip({
    required this.group,
    required this.colorOffset,
    required this.onVideoTap,
    required this.onViewMore,
  });

  final VideoFolderGroup group;
  final int colorOffset;
  final ValueChanged<int> onVideoTap;
  final VoidCallback onViewMore;

  @override
  State<_FolderVideoStrip> createState() => _FolderVideoStripState();
}

class _FolderVideoStripState extends State<_FolderVideoStrip> {
  static const int _previewVideoLimit = 4;

  late final ScrollController _scrollController;

  @override
  void initState() {
    super.initState();
    _scrollController = ScrollController();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final hasMore = widget.group.items.length > _previewVideoLimit;
    final visibleVideoCount = hasMore ? _previewVideoLimit : widget.group.items.length;
    final slotCount = visibleVideoCount + (hasMore ? 1 : 0);

    return LayoutBuilder(
      builder: (context, constraints) {
        final cardWidth = switch (constraints.maxWidth) {
          < 600 => 170.0,
          < 900 => 200.0,
          _ => 224.0,
        };
        final cardHeight = cardWidth / 0.82;
        return SizedBox(
          height: cardHeight + 8,
          child: ScrollConfiguration(
            behavior: ScrollConfiguration.of(context).copyWith(
              dragDevices: const {
                PointerDeviceKind.touch,
                PointerDeviceKind.mouse,
                PointerDeviceKind.stylus,
                PointerDeviceKind.trackpad,
              },
            ),
            child: Scrollbar(
              controller: _scrollController,
              interactive: true,
              radius: const Radius.circular(999),
              child: ListView.separated(
                key: Key('分类横向书架-${widget.group.displayName}'),
                controller: _scrollController,
                scrollDirection: Axis.horizontal,
                physics: const BouncingScrollPhysics(),
                padding: const EdgeInsets.only(bottom: 8),
                itemCount: slotCount,
                separatorBuilder: (context, index) => const SizedBox(width: 16),
                itemBuilder: (context, index) {
                  if (hasMore && index == visibleVideoCount) {
                    return SizedBox(
                      width: cardWidth,
                      child: _ViewMoreCard(
                        folderName: widget.group.displayName,
                        remainingCount: widget.group.items.length - visibleVideoCount,
                        totalCount: widget.group.items.length,
                        onTap: widget.onViewMore,
                      ),
                    );
                  }
                  final video = widget.group.items[index];
                  return SizedBox(
                    width: cardWidth,
                    child: VideoCard(
                      key: ValueKey(video.id),
                      video: video,
                      colorIndex: widget.colorOffset + index,
                      onTap: () => widget.onVideoTap(index),
                    ),
                  );
                },
              ),
            ),
          ),
        );
      },
    );
  }
}

class _ViewMoreCard extends StatelessWidget {
  const _ViewMoreCard({
    required this.folderName,
    required this.remainingCount,
    required this.totalCount,
    required this.onTap,
  });

  final String folderName;
  final int remainingCount;
  final int totalCount;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: '查看$folderName中的全部$totalCount个视频',
      child: Material(
        color: AppColors.paper,
        borderRadius: BorderRadius.circular(26),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          key: Key('查看更多-$folderName'),
          onTap: onTap,
          child: Ink(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  AppColors.teal.withValues(alpha: 0.2),
                  AppColors.sky.withValues(alpha: 0.12),
                  AppColors.sunshine.withValues(alpha: 0.2),
                ],
              ),
            ),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final compact = constraints.maxWidth < 190;
                return Padding(
                  padding: EdgeInsets.all(compact ? 16 : 20),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      DecoratedBox(
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.9),
                          borderRadius: BorderRadius.circular(compact ? 18 : 22),
                        ),
                        child: SizedBox.square(
                          dimension: compact ? 56 : 72,
                          child: Icon(
                            Icons.video_collection_rounded,
                            color: AppColors.tealDark,
                            size: compact ? 32 : 38,
                          ),
                        ),
                      ),
                      SizedBox(height: compact ? 12 : 18),
                      Text(
                        '查看更多',
                        style: compact
                            ? Theme.of(context).textTheme.titleMedium
                            : Theme.of(context).textTheme.titleLarge,
                      ),
                      SizedBox(height: compact ? 5 : 7),
                      Text(
                        '还有 $remainingCount 个视频',
                        style: Theme.of(context).textTheme.bodyMedium
                            ?.copyWith(color: AppColors.tealDark, fontWeight: FontWeight.w700),
                      ),
                      SizedBox(height: compact ? 10 : 14),
                      Icon(
                        Icons.arrow_forward_rounded,
                        color: AppColors.coral,
                        size: compact ? 24 : 28,
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

class _LoadingSections extends StatelessWidget {
  const _LoadingSections({required this.sidePadding});

  final double sidePadding;

  @override
  Widget build(BuildContext context) {
    return SliverPadding(
      padding: EdgeInsets.symmetric(horizontal: sidePadding),
      sliver: SliverToBoxAdapter(
        child: ExcludeSemantics(
          child: Column(
            key: const Key('分类骨架屏'),
            children: const [
              _LoadingSection(sectionIndex: 0),
              SizedBox(height: 32),
              _LoadingSection(sectionIndex: 1),
            ],
          ),
        ),
      ),
    );
  }
}

class _LoadingSection extends StatelessWidget {
  const _LoadingSection({required this.sectionIndex});

  final int sectionIndex;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 600;
        final cardWidth = switch (constraints.maxWidth) {
          < 600 => 170.0,
          < 900 => 200.0,
          _ => 224.0,
        };
        final cardHeight = cardWidth / 0.82;
        final header = compact
            ? Column(
                children: [
                  Row(
                    children: [
                      _SkeletonBlock(
                        width: 44,
                        height: 44,
                        borderRadius: BorderRadius.circular(15),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _SkeletonBlock(height: 46, borderRadius: BorderRadius.circular(9)),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Padding(
                    padding: const EdgeInsets.only(left: 56),
                    child: Row(
                      children: [
                        _SkeletonBlock(
                          width: 64,
                          height: 28,
                          borderRadius: BorderRadius.circular(999),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _SkeletonBlock(
                            height: 2,
                            borderRadius: BorderRadius.circular(999),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              )
            : Row(
                children: [
                  _SkeletonBlock(width: 44, height: 44, borderRadius: BorderRadius.circular(15)),
                  const SizedBox(width: 12),
                  _SkeletonBlock(width: 96, height: 23, borderRadius: BorderRadius.circular(9)),
                  const SizedBox(width: 10),
                  _SkeletonBlock(width: 64, height: 28, borderRadius: BorderRadius.circular(999)),
                  const SizedBox(width: 14),
                  Expanded(
                    child: _SkeletonBlock(height: 2, borderRadius: BorderRadius.circular(999)),
                  ),
                ],
              );
        return Column(
          key: Key('分类骨架分区-$sectionIndex'),
          children: [
            header,
            const SizedBox(height: 14),
            SizedBox(
              height: cardHeight,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: 5,
                separatorBuilder: (context, index) => const SizedBox(width: 16),
                itemBuilder: (context, index) => SizedBox(
                  width: cardWidth,
                  child: _LoadingVideoCard(key: Key('骨架视频卡片-$sectionIndex-$index')),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _LoadingVideoCard extends StatelessWidget {
  const _LoadingVideoCard({super.key});

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: AppColors.paper.withValues(alpha: 0.82),
        borderRadius: BorderRadius.circular(26),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: _SkeletonBlock(
                width: double.infinity,
                borderRadius: BorderRadius.circular(19),
              ),
            ),
            const SizedBox(height: 14),
            _SkeletonBlock(width: 116, height: 16, borderRadius: BorderRadius.circular(8)),
            const SizedBox(height: 8),
            _SkeletonBlock(width: 82, height: 14, borderRadius: BorderRadius.circular(7)),
          ],
        ),
      ),
    );
  }
}

class _SkeletonBlock extends StatelessWidget {
  const _SkeletonBlock({this.width, this.height, required this.borderRadius});

  final double? width;
  final double? height;
  final BorderRadius borderRadius;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            AppColors.teal.withValues(alpha: 0.08),
            AppColors.sky.withValues(alpha: 0.13),
            AppColors.teal.withValues(alpha: 0.08),
          ],
        ),
        borderRadius: borderRadius,
      ),
      child: SizedBox(width: width, height: height),
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
