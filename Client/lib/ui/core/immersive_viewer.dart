import 'dart:ui' as ui;

import 'package:flutter/material.dart';

/// 相册和视频详情共用的轻量控制层，隐藏时不截获画面手势。
class ViewerChrome extends StatelessWidget {
  const ViewerChrome({required this.visible, required this.child, this.bottom = false, super.key});

  final bool visible;
  final bool bottom;
  final Widget child;

  @override
  Widget build(BuildContext context) => IgnorePointer(
    ignoring: !visible,
    child: AnimatedOpacity(
      opacity: visible ? 1 : 0,
      duration: MediaQuery.disableAnimationsOf(context)
          ? Duration.zero
          : const Duration(milliseconds: 200),
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: bottom ? Alignment.bottomCenter : Alignment.topCenter,
            end: bottom ? Alignment.topCenter : Alignment.bottomCenter,
            colors: const [Color(0xAA11171D), Color(0x0011171D)],
          ),
        ),
        child: child,
      ),
    ),
  );
}

/// 统一返回键和上一项、下一项按钮的尺寸、描边与悬停反馈。
class ViewerButton extends StatelessWidget {
  const ViewerButton({
    required this.label,
    required this.icon,
    required this.onPressed,
    this.large = false,
    super.key,
  });

  final String label;
  final IconData icon;
  final VoidCallback? onPressed;
  final bool large;

  @override
  Widget build(BuildContext context) => IconButton(
    tooltip: label,
    onPressed: onPressed,
    icon: Icon(icon, size: large ? 32 : 22),
    style: IconButton.styleFrom(
      minimumSize: Size.square(large ? 60 : 48),
      backgroundColor: Colors.black.withValues(alpha: 0.16),
      foregroundColor: Colors.white,
      disabledForegroundColor: Colors.white30,
      side: BorderSide(color: Colors.white.withValues(alpha: 0.16)),
      shape: const CircleBorder(),
    ),
  );
}

/// 仅对静态封面模糊，独立重绘边界避免跟随视频帧刷新。
class ViewerBackdrop extends StatelessWidget {
  const ViewerBackdrop({required this.image, super.key});

  final ImageProvider<Object> image;

  @override
  Widget build(BuildContext context) => ExcludeSemantics(
    child: RepaintBoundary(
      child: ClipRect(
        child: ImageFiltered(
          imageFilter: ui.ImageFilter.blur(sigmaX: 28, sigmaY: 28),
          child: Image(
            image: image,
            fit: BoxFit.cover,
            color: Colors.black.withValues(alpha: 0.76),
            colorBlendMode: BlendMode.darken,
            errorBuilder: (_, _, _) => const SizedBox.expand(),
          ),
        ),
      ),
    ),
  );
}
