import 'package:bobo_learning/domain/models/video_item.dart';
import 'package:bobo_learning/ui/core/app_theme.dart';
import 'package:flutter/material.dart';

/// 首页书架与文件夹详情页共用的视频封面卡片。
class VideoCard extends StatelessWidget {
  const VideoCard({
    required this.video,
    required this.colorIndex,
    required this.onTap,
    super.key,
  });

  final VideoItem video;
  final int colorIndex;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    const accentColors = [
      AppColors.teal,
      AppColors.coral,
      AppColors.sky,
      AppColors.sunshine,
    ];
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
                          child: Icon(
                            Icons.play_arrow_rounded,
                            color: accent,
                            size: 28,
                          ),
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
