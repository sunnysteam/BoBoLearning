import 'package:bobo_learning/domain/models/video_item.dart';
import 'package:bobo_learning/ui/core/app_theme.dart';
import 'package:bobo_learning/ui/core/playful_backdrop.dart';
import 'package:bobo_learning/ui/features/home/widgets/video_card.dart';
import 'package:bobo_learning/ui/features/player/services/playback_controller.dart';
import 'package:bobo_learning/ui/features/player/view_models/player_view_model.dart';
import 'package:bobo_learning/ui/features/player/views/player_page.dart';
import 'package:flutter/material.dart';

/// 展示单个媒体文件夹中全部视频的响应式网格页。
class FolderPage extends StatelessWidget {
  FolderPage({
    required this.folderName,
    required List<VideoItem> items,
    required this.playbackControllerFactory,
    super.key,
  }) : items = List.unmodifiable(items);

  final String folderName;
  final List<VideoItem> items;
  final PlaybackControllerFactory playbackControllerFactory;

  Future<void> _openPlayer(BuildContext context, int index) async {
    final viewModel = PlayerViewModel(
      items: items,
      initialIndex: index,
      controllerFactory: playbackControllerFactory,
    );
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => PlayerPage(viewModel: viewModel),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      key: const Key('文件夹详情页'),
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
              return CustomScrollView(
                key: const Key('文件夹详情滚动区域'),
                physics: const BouncingScrollPhysics(),
                slivers: [
                  SliverPadding(
                    padding: EdgeInsets.fromLTRB(sidePadding, 20, sidePadding, 24),
                    sliver: SliverToBoxAdapter(
                      child: _FolderPageHeader(
                        folderName: folderName,
                        count: items.length,
                      ),
                    ),
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
                        (context, index) => VideoCard(
                          key: ValueKey(items[index].id),
                          video: items[index],
                          colorIndex: index,
                          onTap: () => _openPlayer(context, index),
                        ),
                        childCount: items.length,
                      ),
                    ),
                  ),
                  const SliverToBoxAdapter(child: SizedBox(height: 36)),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

class _FolderPageHeader extends StatelessWidget {
  const _FolderPageHeader({required this.folderName, required this.count});

  final String folderName;
  final int count;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        IconButton.filledTonal(
          key: const Key('文件夹详情返回按钮'),
          tooltip: '返回首页',
          onPressed: () => Navigator.of(context).pop(),
          style: IconButton.styleFrom(
            backgroundColor: AppColors.paper.withValues(alpha: 0.92),
            foregroundColor: AppColors.tealDark,
            side: BorderSide(color: AppColors.teal.withValues(alpha: 0.16)),
          ),
          icon: const Icon(Icons.arrow_back_rounded),
        ),
        const SizedBox(width: 14),
        DecoratedBox(
          decoration: BoxDecoration(
            color: AppColors.teal.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(16),
          ),
          child: const SizedBox.square(
            dimension: 50,
            child: Icon(Icons.folder_open_rounded, color: AppColors.tealDark, size: 29),
          ),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                folderName,
                key: const Key('文件夹详情标题'),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.headlineMedium,
              ),
              const SizedBox(height: 3),
              Text(
                '$count 个视频 · 选一个开始探索吧',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: AppColors.mutedInk,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
