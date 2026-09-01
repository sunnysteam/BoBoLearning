import 'package:bobo_learning/ui/core/app_theme.dart';
import 'package:flutter/material.dart';

/// 首页柔和几何背景。
class PlayfulBackdrop extends StatelessWidget {
  const PlayfulBackdrop({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        const ColoredBox(color: AppColors.cream),
        const IgnorePointer(child: CustomPaint(painter: _BackdropPainter())),
        child,
      ],
    );
  }
}

class _BackdropPainter extends CustomPainter {
  const _BackdropPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..style = PaintingStyle.fill;
    paint.color = AppColors.sunshine.withValues(alpha: 0.16);
    canvas.drawCircle(Offset(size.width * 0.92, 52), 112, paint);

    paint.color = AppColors.sky.withValues(alpha: 0.11);
    canvas.drawCircle(Offset(size.width * 0.08, size.height * 0.58), 150, paint);

    paint.color = AppColors.coral.withValues(alpha: 0.08);
    final coralShape = Path()
      ..moveTo(size.width * 0.68, size.height)
      ..quadraticBezierTo(size.width * 0.84, size.height * 0.78, size.width, size.height * 0.84)
      ..lineTo(size.width, size.height)
      ..close();
    canvas.drawPath(coralShape, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
