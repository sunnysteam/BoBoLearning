import 'package:bobo_learning/domain/models/cloud_media_item.dart';
import 'package:bobo_learning/domain/models/video_item.dart';
import 'package:bobo_learning/ui/core/app_theme.dart';
import 'package:bobo_learning/ui/core/playful_backdrop.dart';
import 'package:bobo_learning/ui/features/cloud/view_models/cloud_media_view_model.dart';
import 'package:bobo_learning/ui/features/cloud/views/photo_viewer_page.dart';
import 'package:bobo_learning/ui/features/home/widgets/video_card.dart';
import 'package:bobo_learning/ui/features/player/services/playback_controller.dart';
import 'package:bobo_learning/ui/features/player/view_models/player_view_model.dart';
import 'package:bobo_learning/ui/features/player/views/player_page.dart';
import 'package:flutter/material.dart';

/// 百度网盘“菠萝视频”页面。
class CloudVideoPage extends StatelessWidget {
  const CloudVideoPage({
    required this.viewModel,
    required this.playbackControllerFactory,
    super.key,
  });

  final CloudMediaViewModel viewModel;
  final PlaybackControllerFactory playbackControllerFactory;

  @override
  Widget build(BuildContext context) {
    return _CloudMediaPage(
      key: const Key('菠萝视频子页面'),
      viewModel: viewModel,
      title: '菠萝视频',
      emptyMessage: '把视频放进“我的网盘/菠萝乐园”，这里就会出现啦',
      icon: Icons.smart_display_rounded,
      accent: AppColors.coral,
      playbackControllerFactory: playbackControllerFactory,
    );
  }
}

/// 百度网盘“菠萝相册”页面。
class CloudAlbumPage extends StatelessWidget {
  const CloudAlbumPage({required this.viewModel, super.key});

  final CloudMediaViewModel viewModel;

  @override
  Widget build(BuildContext context) {
    return _CloudMediaPage(
      key: const Key('菠萝相册子页面'),
      viewModel: viewModel,
      title: '菠萝相册',
      emptyMessage: '把图片放进“我的网盘/菠萝乐园”，这里就会出现啦',
      icon: Icons.photo_library_rounded,
      accent: AppColors.lavender,
    );
  }
}

class _CloudMediaPage extends StatefulWidget {
  const _CloudMediaPage({
    required this.viewModel,
    required this.title,
    required this.emptyMessage,
    required this.icon,
    required this.accent,
    this.playbackControllerFactory,
    super.key,
  });

  final CloudMediaViewModel viewModel;
  final String title;
  final String emptyMessage;
  final IconData icon;
  final Color accent;
  final PlaybackControllerFactory? playbackControllerFactory;

  bool get isVideo => playbackControllerFactory != null;

  @override
  State<_CloudMediaPage> createState() => _CloudMediaPageState();
}

class _CloudMediaPageState extends State<_CloudMediaPage> {
  @override
  void initState() {
    super.initState();
    widget.viewModel.addListener(_handleChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) => widget.viewModel.loadInitial());
  }

  @override
  void didUpdateWidget(covariant _CloudMediaPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.viewModel == widget.viewModel) {
      return;
    }
    oldWidget.viewModel.removeListener(_handleChanged);
    widget.viewModel.addListener(_handleChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) => widget.viewModel.loadInitial());
  }

  @override
  void dispose() {
    widget.viewModel.removeListener(_handleChanged);
    super.dispose();
  }

  void _handleChanged() {
    if (!mounted) {
      return;
    }
    setState(() {});
    final message = widget.viewModel.transientMessage;
    if (message != null) {
      widget.viewModel.clearTransientMessage();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
        }
      });
    }
  }

  Future<void> _openVideo(int index) async {
    final items = widget.viewModel.items
        .map(
          (item) => VideoItem(
            id: 'baidu-${item.id}',
            title: item.fileName,
            coverUri: item.thumbnailUri,
            streamUri: item.contentUri,
          ),
        )
        .toList(growable: false);
    final viewModel = PlayerViewModel(
      items: items,
      initialIndex: index,
      controllerFactory: widget.playbackControllerFactory!,
    );
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => PlayerPage(viewModel: viewModel, title: '菠萝视频'),
      ),
    );
  }

  Future<void> _openPhoto(int index) {
    final items = List<CloudMediaItem>.of(widget.viewModel.items);
    return Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => PhotoViewerPage(items: items, initialIndex: index),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: PlayfulBackdrop(
        child: SafeArea(
          bottom: false,
          child: LayoutBuilder(
            builder: (context, constraints) {
              final sidePadding = constraints.maxWidth > 1240
                  ? (constraints.maxWidth - 1180) / 2
                  : constraints.maxWidth >= 720
                  ? 32.0
                  : 16.0;
              return RefreshIndicator(
                color: widget.accent,
                onRefresh: widget.viewModel.refresh,
                child: CustomScrollView(
                  key: Key('${widget.title}滚动区域'),
                  physics: const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics()),
                  slivers: [
                    SliverPadding(
                      padding: EdgeInsets.fromLTRB(sidePadding, 18, sidePadding, 22),
                      sliver: SliverToBoxAdapter(
                        child: _CloudHeader(
                          title: widget.title,
                          icon: widget.icon,
                          accent: widget.accent,
                          count: widget.viewModel.items.length,
                          isRefreshing: widget.viewModel.isRefreshing,
                          onRefresh: widget.viewModel.refresh,
                        ),
                      ),
                    ),
                    ..._buildContent(sidePadding),
                    const SliverToBoxAdapter(child: SizedBox(height: 36)),
                  ],
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  List<Widget> _buildContent(double sidePadding) {
    return switch (widget.viewModel.state) {
      CloudMediaLoadState.initial || CloudMediaLoadState.loading => [
        SliverFillRemaining(
          hasScrollBody: false,
          child: _CloudMessage(
            key: Key('${widget.title}加载中'),
            icon: widget.icon,
            accent: widget.accent,
            message: '正在从百度网盘取回内容…',
            loading: true,
          ),
        ),
      ],
      CloudMediaLoadState.empty => [
        SliverFillRemaining(
          hasScrollBody: false,
          child: _CloudMessage(
            key: Key('${widget.title}空状态'),
            icon: widget.icon,
            accent: widget.accent,
            message: widget.emptyMessage,
          ),
        ),
      ],
      CloudMediaLoadState.error => [
        SliverFillRemaining(
          hasScrollBody: false,
          child: _CloudMessage(
            key: Key('${widget.title}错误状态'),
            icon: Icons.cloud_off_rounded,
            accent: widget.accent,
            message: widget.viewModel.errorMessage ?? '暂时拿不到内容，请稍后再试',
            action: FilledButton.icon(
              onPressed: widget.viewModel.retry,
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('重新加载'),
            ),
          ),
        ),
      ],
      CloudMediaLoadState.ready => [
        SliverPadding(
          padding: EdgeInsets.symmetric(horizontal: sidePadding),
          sliver: SliverGrid(
            gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
              maxCrossAxisExtent: widget.isVideo ? 280 : 300,
              childAspectRatio: widget.isVideo ? 0.82 : 0.9,
              crossAxisSpacing: 16,
              mainAxisSpacing: 18,
            ),
            delegate: SliverChildBuilderDelegate((context, index) {
              final item = widget.viewModel.items[index];
              if (widget.isVideo) {
                return VideoCard(
                  key: ValueKey('baidu-${item.id}'),
                  video: VideoItem(
                    id: 'baidu-${item.id}',
                    title: item.fileName,
                    coverUri: item.thumbnailUri,
                    streamUri: item.contentUri,
                  ),
                  colorIndex: index,
                  onTap: () => _openVideo(index),
                );
              }
              return _PhotoCard(
                key: ValueKey(item.id),
                item: item,
                colorIndex: index,
                onTap: () => _openPhoto(index),
              );
            }, childCount: widget.viewModel.items.length),
          ),
        ),
      ],
    };
  }
}

class _CloudHeader extends StatelessWidget {
  const _CloudHeader({
    required this.title,
    required this.icon,
    required this.accent,
    required this.count,
    required this.isRefreshing,
    required this.onRefresh,
  });

  final String title;
  final IconData icon;
  final Color accent;
  final int count;
  final bool isRefreshing;
  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        IconButton(
          key: Key('$title返回按钮'),
          tooltip: '返回菠萝首页',
          onPressed: () => Navigator.of(context).pop(),
          style: IconButton.styleFrom(
            backgroundColor: AppColors.paper.withValues(alpha: 0.94),
            foregroundColor: AppColors.ink,
            side: BorderSide(color: accent.withValues(alpha: 0.16)),
          ),
          icon: const Icon(Icons.arrow_back_rounded),
        ),
        const SizedBox(width: 12),
        DecoratedBox(
          decoration: BoxDecoration(
            color: accent.withValues(alpha: 0.13),
            borderRadius: BorderRadius.circular(16),
          ),
          child: SizedBox.square(dimension: 50, child: Icon(icon, color: accent, size: 28)),
        ),
        const SizedBox(width: 13),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                key: Key('$title子页面标题'),
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              Text(
                '$count 项 · 文件名倒序',
                style: Theme.of(context).textTheme.bodyMedium
                    ?.copyWith(fontWeight: FontWeight.w600),
              ),
            ],
          ),
        ),
        IconButton.filledTonal(
          key: Key('$title刷新按钮'),
          tooltip: '刷新$title',
          onPressed: isRefreshing ? null : onRefresh,
          style: IconButton.styleFrom(
            backgroundColor: accent.withValues(alpha: 0.12),
            foregroundColor: accent,
          ),
          icon: isRefreshing
              ? SizedBox.square(
                  dimension: 22,
                  child: CircularProgressIndicator(color: accent, strokeWidth: 2.5),
                )
              : const Icon(Icons.refresh_rounded),
        ),
      ],
    );
  }
}

class _CloudMessage extends StatelessWidget {
  const _CloudMessage({
    required this.icon,
    required this.accent,
    required this.message,
    this.loading = false,
    this.action,
    super.key,
  });

  final IconData icon;
  final Color accent;
  final String message;
  final bool loading;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 460),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(28, 30, 28, 100),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              DecoratedBox(
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child: SizedBox.square(
                  dimension: 94,
                  child: loading
                      ? Padding(
                          padding: const EdgeInsets.all(30),
                          child: CircularProgressIndicator(color: accent, strokeWidth: 3),
                        )
                      : Icon(icon, color: accent, size: 46),
                ),
              ),
              const SizedBox(height: 24),
              Text(
                message,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyLarge
                    ?.copyWith(color: AppColors.mutedInk, fontWeight: FontWeight.w600),
              ),
              if (action != null) ...[const SizedBox(height: 24), action!],
            ],
          ),
        ),
      ),
    );
  }
}

class _PhotoCard extends StatelessWidget {
  const _PhotoCard({required this.item, required this.colorIndex, required this.onTap, super.key});

  final CloudMediaItem item;
  final int colorIndex;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    const accents = [AppColors.lavender, AppColors.sky, AppColors.coral, AppColors.teal];
    final accent = accents[colorIndex % accents.length];
    return Semantics(
      button: true,
      label: '查看${item.fileName}',
      child: Material(
        color: AppColors.paper,
        borderRadius: BorderRadius.circular(24),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          key: Key('相册图片-${item.id}'),
          onTap: onTap,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: Hero(
                  tag: '相册-${item.id}',
                  child: Image.network(
                    item.thumbnailUri.toString(),
                    fit: BoxFit.cover,
                    loadingBuilder: (context, child, progress) => progress == null
                        ? child
                        : ColoredBox(
                            color: accent.withValues(alpha: 0.1),
                            child: Center(child: CircularProgressIndicator(color: accent)),
                          ),
                    errorBuilder: (context, error, stackTrace) => ColoredBox(
                      color: accent.withValues(alpha: 0.1),
                      child: Icon(Icons.broken_image_rounded, color: accent, size: 42),
                    ),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
                child: Text(
                  item.fileName,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleSmall
                      ?.copyWith(color: AppColors.ink, fontWeight: FontWeight.w700),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
