import 'package:bobo_learning/domain/models/app_update.dart';
import 'package:bobo_learning/domain/repositories/app_update_repository.dart';
import 'package:bobo_learning/ui/features/update/services/app_update_platform.dart';
import 'package:bobo_learning/ui/features/update/view_models/app_update_view_model.dart';
import 'package:bobo_learning/ui/features/update/views/app_update_prompt_host.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('下载校验完成后弹窗并可点击重启安装', (tester) async {
    final update = AppUpdate(
      versionName: '0.2.0',
      versionCode: 2,
      downloadUri: Uri.parse('https://learning.example/bobo-learning-2.apk'),
      sha256: 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
      sizeBytes: 1024,
      releaseNotes: const ['新增静默升级', '提升播放稳定性'],
      publishedAt: DateTime.utc(2026, 9, 3),
    );
    final platform = _ReadyPlatform();
    final viewModel = AppUpdateViewModel(
      repository: _SingleUpdateRepository(update),
      platform: platform,
    );
    addTearDown(viewModel.dispose);
    await viewModel.start();

    await tester.pumpWidget(
      MaterialApp(
        home: AppUpdatePromptHost(
          viewModel: viewModel,
          child: const Scaffold(body: Text('菠萝首页')),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('应用更新弹窗')), findsOneWidget);
    expect(find.text('菠萝乐园 0.2.0'), findsOneWidget);
    expect(find.text('新增静默升级'), findsOneWidget);

    await tester.tap(find.byKey(const Key('应用更新安装按钮')));
    await tester.pumpAndSettle();

    expect(platform.installCount, 1);
    expect(find.byKey(const Key('应用更新弹窗')), findsNothing);
  });

  testWidgets('稍后安装关闭弹窗且不启动系统安装器', (tester) async {
    final update = AppUpdate(
      versionName: '0.2.0',
      versionCode: 2,
      downloadUri: Uri.parse('https://learning.example/bobo-learning-2.apk'),
      sha256: 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
      sizeBytes: 1024,
      releaseNotes: const [],
      publishedAt: DateTime.utc(2026, 9, 3),
    );
    final platform = _ReadyPlatform();
    final viewModel = AppUpdateViewModel(
      repository: _SingleUpdateRepository(update),
      platform: platform,
    );
    addTearDown(viewModel.dispose);
    await viewModel.start();

    await tester.pumpWidget(
      MaterialApp(
        home: AppUpdatePromptHost(
          viewModel: viewModel,
          child: const Scaffold(body: Text('菠萝首页')),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('应用更新稍后按钮')));
    await tester.pumpAndSettle();

    expect(platform.installCount, 0);
    expect(find.byKey(const Key('应用更新弹窗')), findsNothing);
  });
}

class _SingleUpdateRepository implements AppUpdateRepository {
  const _SingleUpdateRepository(this.update);

  final AppUpdate update;

  @override
  Future<AppUpdate?> findAvailableUpdate({required int currentVersionCode}) async => update;
}

class _ReadyPlatform implements AppUpdatePlatform {
  int installCount = 0;

  @override
  Future<AppPlatformInfo> getPlatformInfo() async =>
      const AppPlatformInfo(supported: true, versionName: '0.1.0', versionCode: 1);

  @override
  Future<UpdateDownloadSnapshot> getDownloadStatus() async => const UpdateDownloadSnapshot(
    phase: UpdateDownloadPhase.ready,
    versionCode: 2,
    downloadedBytes: 1024,
    totalBytes: 1024,
  );

  @override
  Future<UpdateInstallResult> installDownloadedUpdate() async {
    installCount += 1;
    return UpdateInstallResult.opened;
  }

  @override
  Future<void> startDownload(AppUpdate update) async {}
}
