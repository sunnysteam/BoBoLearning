import 'package:bobo_learning/ui/core/app_theme.dart';
import 'package:bobo_learning/ui/core/playful_backdrop.dart';
import 'package:flutter/material.dart';

/// 菠萝系列内容的总入口。
class PortalPage extends StatelessWidget {
  const PortalPage({required this.earlyLearningPageBuilder, super.key});

  final WidgetBuilder earlyLearningPageBuilder;

  Future<void> _openSection(BuildContext context, _PortalSection section) {
    final WidgetBuilder pageBuilder = switch (section.kind) {
      _PortalSectionKind.earlyLearning => earlyLearningPageBuilder,
      _PortalSectionKind.videos ||
      _PortalSectionKind.albums => (_) => _PreparingSectionPage(section: section),
    };

    return Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        settings: RouteSettings(name: section.routeName),
        builder: pageBuilder,
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
              final compact = constraints.maxWidth < 680;
              final sidePadding = constraints.maxWidth > 1240
                  ? (constraints.maxWidth - 1160) / 2
                  : constraints.maxWidth >= 760
                  ? 40.0
                  : 20.0;

              return CustomScrollView(
                key: const Key('菠萝首页滚动区域'),
                physics: const BouncingScrollPhysics(),
                slivers: [
                  SliverPadding(
                    padding: EdgeInsets.fromLTRB(
                      sidePadding,
                      compact ? 20 : 34,
                      sidePadding,
                      compact ? 28 : 42,
                    ),
                    sliver: SliverToBoxAdapter(child: _PortalHeader(compact: compact)),
                  ),
                  SliverPadding(
                    padding: EdgeInsets.fromLTRB(sidePadding, 0, sidePadding, 18),
                    sliver: SliverToBoxAdapter(
                      child: Text(
                        '今天想去哪里玩？',
                        key: const Key('菠萝首页主标题'),
                        style: Theme.of(
                          context,
                        ).textTheme.bodyLarge?.copyWith(color: AppColors.ink),
                      ),
                    ),
                  ),
                  SliverPadding(
                    padding: EdgeInsets.fromLTRB(sidePadding, 6, sidePadding, compact ? 28 : 48),
                    sliver: SliverToBoxAdapter(
                      child: LayoutBuilder(
                        builder: (context, cardConstraints) {
                          final availableWidth = cardConstraints.maxWidth;
                          final columns = availableWidth >= 980
                              ? 3
                              : availableWidth >= 640
                              ? 2
                              : 1;
                          final spacing = compact ? 14.0 : 20.0;
                          final cardWidth = (availableWidth - spacing * (columns - 1)) / columns;
                          final cardHeight = compact ? 184.0 : 304.0;

                          return FocusTraversalGroup(
                            child: Wrap(
                              key: const Key('菠萝首页分类区域'),
                              alignment: WrapAlignment.center,
                              spacing: spacing,
                              runSpacing: spacing,
                              children: [
                                for (final section in _sections)
                                  SizedBox(
                                    width: cardWidth,
                                    height: cardHeight,
                                    child: _PortalCategoryCard(
                                      section: section,
                                      compact: compact,
                                      onTap: () => _openSection(context, section),
                                    ),
                                  ),
                              ],
                            ),
                          );
                        },
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

class _PortalHeader extends StatelessWidget {
  const _PortalHeader({required this.compact});

  final bool compact;

  @override
  Widget build(BuildContext context) {
    final brand = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Semantics(
          label: '菠萝乐园标志',
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(22),
              border: Border.all(color: AppColors.sunshine.withValues(alpha: 0.36)),
              boxShadow: [
                BoxShadow(
                  color: AppColors.sunshine.withValues(alpha: 0.22),
                  blurRadius: 20,
                  offset: const Offset(0, 9),
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(21),
              child: Image.asset(
                'assets/branding/pineapple_icon.png',
                key: const Key('菠萝首页品牌图标'),
                width: compact ? 64 : 72,
                height: compact ? 64 : 72,
                fit: BoxFit.cover,
                filterQuality: FilterQuality.high,
                excludeFromSemantics: true,
              ),
            ),
          ),
        ),
        const SizedBox(width: 16),
        Flexible(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '菠萝乐园',
                style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                  fontSize: compact ? 27 : 32,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                '每一天，都有新的小惊喜',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontSize: 15),
              ),
            ],
          ),
        ),
      ],
    );

    final welcomePill = DecoratedBox(
      decoration: BoxDecoration(
        color: AppColors.paper.withValues(alpha: 0.88),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: AppColors.teal.withValues(alpha: 0.16)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.auto_awesome_rounded, size: 20, color: AppColors.coral),
            const SizedBox(width: 8),
            Text(
              '三个小世界，等你来发现',
              style: Theme.of(context).textTheme.labelLarge?.copyWith(color: AppColors.tealDark),
            ),
          ],
        ),
      ),
    );

    if (compact) {
      return brand;
    }
    return Row(
      children: [
        Expanded(child: brand),
        const SizedBox(width: 24),
        welcomePill,
      ],
    );
  }
}

class _PortalCategoryCard extends StatefulWidget {
  const _PortalCategoryCard({required this.section, required this.compact, required this.onTap});

  final _PortalSection section;
  final bool compact;
  final VoidCallback onTap;

  @override
  State<_PortalCategoryCard> createState() => _PortalCategoryCardState();
}

class _PortalCategoryCardState extends State<_PortalCategoryCard> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final section = widget.section;
    final borderRadius = BorderRadius.circular(widget.compact ? 26 : 32);

    return Semantics(
      button: true,
      label: '进入${section.title}',
      hint: section.description,
      child: ExcludeSemantics(
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          onEnter: (_) => setState(() => _hovered = true),
          onExit: (_) => setState(() => _hovered = false),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOutCubic,
            decoration: BoxDecoration(
              borderRadius: borderRadius,
              boxShadow: [
                BoxShadow(
                  color: section.accent.withValues(alpha: _hovered ? 0.22 : 0.12),
                  blurRadius: _hovered ? 28 : 18,
                  offset: Offset(0, _hovered ? 12 : 8),
                ),
              ],
            ),
            child: Material(
              color: section.surface,
              shape: RoundedRectangleBorder(
                borderRadius: borderRadius,
                side: BorderSide(color: section.accent.withValues(alpha: 0.18)),
              ),
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                key: Key('菠萝首页分类-${section.title}'),
                onTap: widget.onTap,
                borderRadius: borderRadius,
                overlayColor: WidgetStatePropertyAll(section.accent.withValues(alpha: 0.09)),
                child: Stack(
                  children: [
                    Positioned(
                      right: widget.compact ? -24 : -30,
                      top: widget.compact ? -34 : -42,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.45),
                          shape: BoxShape.circle,
                        ),
                        child: SizedBox.square(dimension: widget.compact ? 112 : 154),
                      ),
                    ),
                    Positioned(
                      left: widget.compact ? 114 : 24,
                      bottom: widget.compact ? -30 : -46,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: section.accent.withValues(alpha: 0.08),
                          shape: BoxShape.circle,
                        ),
                        child: SizedBox.square(dimension: widget.compact ? 84 : 124),
                      ),
                    ),
                    Padding(
                      padding: EdgeInsets.all(widget.compact ? 18 : 24),
                      child: widget.compact
                          ? _CompactCategoryContent(section: section)
                          : _ExpandedCategoryContent(section: section),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _CompactCategoryContent extends StatelessWidget {
  const _CompactCategoryContent({required this.section});

  final _PortalSection section;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        _CategoryIllustration(section: section, size: 116),
        const SizedBox(width: 18),
        Expanded(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                section.title,
                style: Theme.of(
                  context,
                ).textTheme.titleLarge?.copyWith(fontSize: 23, fontWeight: FontWeight.w900),
              ),
              const SizedBox(height: 7),
              Text(
                section.description,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: AppColors.ink.withValues(alpha: 0.76),
                  fontSize: 15,
                ),
              ),
              const SizedBox(height: 10),
              _ExploreLabel(accent: section.accent),
            ],
          ),
        ),
      ],
    );
  }
}

class _ExpandedCategoryContent extends StatelessWidget {
  const _ExpandedCategoryContent({required this.section});

  final _PortalSection section;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _CategoryIllustration(section: section, size: 134),
        const Spacer(),
        Text(
          section.title,
          style: Theme.of(
            context,
          ).textTheme.headlineMedium?.copyWith(fontSize: 27, fontWeight: FontWeight.w900),
        ),
        const SizedBox(height: 7),
        Text(
          section.description,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
            color: AppColors.ink.withValues(alpha: 0.76),
            fontSize: 15,
          ),
        ),
        const SizedBox(height: 14),
        _ExploreLabel(accent: section.accent),
      ],
    );
  }
}

class _CategoryIllustration extends StatelessWidget {
  const _CategoryIllustration({required this.section, required this.size});

  final _PortalSection section;
  final double size;

  @override
  Widget build(BuildContext context) {
    return SizedBox.square(
      dimension: size,
      child: Stack(
        children: [
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.78),
                borderRadius: BorderRadius.circular(size * 0.28),
                border: Border.all(color: section.accent.withValues(alpha: 0.14)),
              ),
            ),
          ),
          Align(
            alignment: Alignment.center,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: section.accent,
                borderRadius: BorderRadius.circular(size * 0.22),
                boxShadow: [
                  BoxShadow(
                    color: section.accent.withValues(alpha: 0.24),
                    blurRadius: 16,
                    offset: const Offset(0, 7),
                  ),
                ],
              ),
              child: SizedBox.square(
                dimension: size * 0.62,
                child: switch (section.kind) {
                  _PortalSectionKind.earlyLearning => Icon(
                    Icons.auto_stories_rounded,
                    key: Key('菠萝首页分类图标-${section.title}'),
                    color: Colors.white,
                    size: size * 0.34,
                  ),
                  _PortalSectionKind.videos => Icon(
                    Icons.smart_display_rounded,
                    key: Key('菠萝首页分类图标-${section.title}'),
                    color: Colors.white,
                    size: size * 0.34,
                  ),
                  _PortalSectionKind.albums => Icon(
                    Icons.photo_library_rounded,
                    key: Key('菠萝首页分类图标-${section.title}'),
                    color: Colors.white,
                    size: size * 0.34,
                  ),
                },
              ),
            ),
          ),
          Positioned(
            top: size * 0.08,
            right: size * 0.08,
            child: Icon(Icons.star_rounded, color: AppColors.sunshine, size: size * 0.2),
          ),
          Positioned(
            left: size * 0.08,
            bottom: size * 0.1,
            child: DecoratedBox(
              decoration: BoxDecoration(color: AppColors.coral, shape: BoxShape.circle),
              child: SizedBox.square(dimension: size * 0.11),
            ),
          ),
        ],
      ),
    );
  }
}

class _ExploreLabel extends StatelessWidget {
  const _ExploreLabel({required this.accent});

  final Color accent;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text('一起出发', style: Theme.of(context).textTheme.labelLarge?.copyWith(color: AppColors.ink)),
        const SizedBox(width: 6),
        DecoratedBox(
          decoration: BoxDecoration(color: accent, shape: BoxShape.circle),
          child: const SizedBox.square(
            dimension: 26,
            child: Icon(Icons.arrow_forward_rounded, color: Colors.white, size: 17),
          ),
        ),
      ],
    );
  }
}

class _PreparingSectionPage extends StatelessWidget {
  const _PreparingSectionPage({required this.section});

  final _PortalSection section;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      key: Key('${section.title}子页面'),
      body: PlayfulBackdrop(
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    IconButton(
                      key: Key('${section.title}返回按钮'),
                      tooltip: '返回菠萝首页',
                      onPressed: () => Navigator.of(context).pop(),
                      style: IconButton.styleFrom(
                        backgroundColor: AppColors.paper.withValues(alpha: 0.94),
                        foregroundColor: AppColors.ink,
                        side: BorderSide(color: section.accent.withValues(alpha: 0.16)),
                      ),
                      icon: const Icon(Icons.arrow_back_rounded),
                    ),
                    const SizedBox(width: 12),
                    Text(
                      section.title,
                      key: Key('${section.title}子页面标题'),
                      style: Theme.of(context).textTheme.headlineMedium,
                    ),
                  ],
                ),
                Expanded(
                  child: Center(
                    child: SingleChildScrollView(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 520),
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(24, 24, 24, 80),
                          child: Column(
                            children: [
                              _CategoryIllustration(section: section, size: 168),
                              const SizedBox(height: 32),
                              Text(
                                section.preparingTitle,
                                textAlign: TextAlign.center,
                                style: Theme.of(context).textTheme.headlineMedium,
                              ),
                              const SizedBox(height: 12),
                              Text(
                                section.preparingMessage,
                                textAlign: TextAlign.center,
                                style: Theme.of(
                                  context,
                                ).textTheme.bodyLarge?.copyWith(color: AppColors.mutedInk),
                              ),
                              const SizedBox(height: 22),
                              DecoratedBox(
                                decoration: BoxDecoration(
                                  color: section.surface,
                                  borderRadius: BorderRadius.circular(999),
                                  border: Border.all(color: section.accent.withValues(alpha: 0.18)),
                                ),
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 11),
                                  child: Text(
                                    '小世界正在准备中',
                                    style: Theme.of(
                                      context,
                                    ).textTheme.labelLarge?.copyWith(color: AppColors.ink),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

enum _PortalSectionKind { earlyLearning, videos, albums }

class _PortalSection {
  const _PortalSection({
    required this.kind,
    required this.routeName,
    required this.title,
    required this.description,
    required this.preparingTitle,
    required this.preparingMessage,
    required this.surface,
    required this.accent,
  });

  final _PortalSectionKind kind;
  final String routeName;
  final String title;
  final String description;
  final String preparingTitle;
  final String preparingMessage;
  final Color surface;
  final Color accent;
}

const _sections = <_PortalSection>[
  _PortalSection(
    kind: _PortalSectionKind.earlyLearning,
    routeName: '/early-learning',
    title: '菠萝早教',
    description: '听故事、学知识，让好奇心快乐长大',
    preparingTitle: '',
    preparingMessage: '',
    surface: AppColors.mintMist,
    accent: AppColors.teal,
  ),
  _PortalSection(
    kind: _PortalSectionKind.videos,
    routeName: '/videos',
    title: '菠萝视频',
    description: '打开欢乐小舞台，发现更多有趣画面',
    preparingTitle: '欢乐小舞台正在布置',
    preparingMessage: '菠萝视频会在这里和你见面，敬请期待新的快乐内容。',
    surface: AppColors.peachMist,
    accent: AppColors.coral,
  ),
  _PortalSection(
    kind: _PortalSectionKind.albums,
    routeName: '/albums',
    title: '菠萝相册',
    description: '收藏闪亮瞬间，把每份快乐好好珍藏',
    preparingTitle: '相册星球正在收集笑脸',
    preparingMessage: '菠萝相册会在这里珍藏美好瞬间，很快就能一起翻看啦。',
    surface: AppColors.skyMist,
    accent: AppColors.lavender,
  ),
];
