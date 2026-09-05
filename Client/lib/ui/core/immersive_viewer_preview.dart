import 'package:bobo_learning/ui/core/app_theme.dart';
import 'package:bobo_learning/ui/core/immersive_viewer.dart';
import 'package:flutter/material.dart';
import 'package:flutter/widget_previews.dart';

/// 不依赖网络与原生播放器，用于独立检查两种尺寸下的公共控制层。
@Preview(name: '手机沉浸工具栏', group: '媒体浏览', size: Size(390, 844))
@Preview(name: '桌面沉浸工具栏', group: '媒体浏览', size: Size(1912, 914))
Widget immersiveViewerPreview() => MaterialApp(theme: AppTheme.light, home: const _ViewerPreview());

class _ViewerPreview extends StatefulWidget {
  const _ViewerPreview();

  @override
  State<_ViewerPreview> createState() => _ViewerPreviewState();
}

class _ViewerPreviewState extends State<_ViewerPreview> {
  bool _visible = true;

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: const Color(0xFF151B22),
    body: Stack(
      fit: StackFit.expand,
      children: [
        Center(
          child: ViewerButton(
            label: _visible ? '隐藏工具栏' : '显示工具栏',
            icon: _visible ? Icons.visibility_off_outlined : Icons.visibility_outlined,
            large: true,
            onPressed: () => setState(() => _visible = !_visible),
          ),
        ),
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          child: ViewerChrome(
            visible: _visible,
            child: SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    ViewerButton(label: '返回列表', icon: Icons.arrow_back_rounded, onPressed: () {}),
                    const SizedBox(width: 14),
                    const Text('菠萝视频', style: TextStyle(color: Colors.white, fontSize: 16)),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    ),
  );
}
