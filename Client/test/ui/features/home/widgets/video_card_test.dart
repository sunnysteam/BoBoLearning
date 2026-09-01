import 'package:bobo_learning/domain/models/video_item.dart';
import 'package:bobo_learning/ui/core/app_theme.dart';
import 'package:bobo_learning/ui/features/home/widgets/video_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('短标题和长标题都占用固定两行标题区域', (tester) async {
    tester.view.physicalSize = const Size(500, 400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    const shortTitle = '员工风采';
    const longTitle = '这是一个会占满两行并在超出时省略的视频标题';
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(
          body: SizedBox(
            height: 280,
            child: Row(
              children: [
                Expanded(
                  child: VideoCard(video: _video('short', shortTitle), colorIndex: 0, onTap: () {}),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: VideoCard(video: _video('long', longTitle), colorIndex: 1, onTap: () {}),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    final shortSlot = tester.getSize(find.byKey(const Key('视频标题区域-short')));
    final longSlot = tester.getSize(find.byKey(const Key('视频标题区域-long')));
    final shortText = tester.getSize(find.text(shortTitle));

    expect(shortSlot.height, closeTo(longSlot.height, 0.01));
    expect(shortSlot.height, greaterThan(shortText.height));
    expect(tester.widget<Text>(find.text(shortTitle)).maxLines, 2);
    expect(tester.widget<Text>(find.text(longTitle)).maxLines, 2);
  });
}

VideoItem _video(String id, String title) {
  return VideoItem(
    id: id,
    title: title,
    folderPath: '测试分类',
    coverUri: Uri.parse('https://invalid.example/$id.jpg'),
    streamUri: Uri.parse('https://invalid.example/$id.mp4'),
  );
}
