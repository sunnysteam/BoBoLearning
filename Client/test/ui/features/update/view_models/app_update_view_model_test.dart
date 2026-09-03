import 'package:bobo_learning/domain/models/app_update.dart';
import 'package:bobo_learning/domain/repositories/app_update_repository.dart';
import 'package:bobo_learning/ui/features/update/services/app_update_platform.dart';
import 'package:bobo_learning/ui/features/update/view_models/app_update_view_model.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('AppUpdateViewModel', () {
    test('发现新版本后静默提交系统下载任务', () async {
      final platform = _FakeAppUpdatePlatform();
      final viewModel = AppUpdateViewModel(
        repository: _FakeAppUpdateRepository(_update),
        platform: platform,
        pollInterval: const Duration(days: 1),
      );
      addTearDown(viewModel.dispose);

      await viewModel.start();

      expect(viewModel.phase, AppUpdatePhase.downloading);
      expect(platform.startedUpdate, _update);
      expect(platform.startCount, 1);
    });

    test('恢复到已校验任务时直接进入待安装状态且不重复下载', () async {
      final platform = _FakeAppUpdatePlatform()
        ..snapshot = const UpdateDownloadSnapshot(
          phase: UpdateDownloadPhase.ready,
          versionCode: 2,
          downloadedBytes: 1024,
          totalBytes: 1024,
        );
      final viewModel = AppUpdateViewModel(
        repository: _FakeAppUpdateRepository(_update),
        platform: platform,
      );
      addTearDown(viewModel.dispose);

      await viewModel.start();

      expect(viewModel.phase, AppUpdatePhase.ready);
      expect(platform.startCount, 0);
    });

    test('点击安装时正确传递未知来源授权状态', () async {
      final platform = _FakeAppUpdatePlatform()
        ..snapshot = const UpdateDownloadSnapshot(phase: UpdateDownloadPhase.ready, versionCode: 2)
        ..installResult = UpdateInstallResult.permissionRequired;
      final viewModel = AppUpdateViewModel(
        repository: _FakeAppUpdateRepository(_update),
        platform: platform,
      );
      addTearDown(viewModel.dispose);
      await viewModel.start();

      final result = await viewModel.install();

      expect(result, UpdateInstallResult.permissionRequired);
      expect(viewModel.phase, AppUpdatePhase.ready);
      expect(viewModel.message, contains('允许菠萝乐园安装应用'));
    });

    test('不支持的平台禁用升级且不请求接口', () async {
      final repository = _FakeAppUpdateRepository(_update);
      final platform = _FakeAppUpdatePlatform()..platformInfo = const AppPlatformInfo.unsupported();
      final viewModel = AppUpdateViewModel(repository: repository, platform: platform);
      addTearDown(viewModel.dispose);

      await viewModel.start();

      expect(viewModel.phase, AppUpdatePhase.disabled);
      expect(repository.requestCount, 0);
    });
  });
}

final _update = AppUpdate(
  versionName: '0.2.0',
  versionCode: 2,
  downloadUri: Uri.parse(
    'https://learning.example/api/v1/app-updates/packages/bobo-learning-2.apk',
  ),
  sha256: 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
  sizeBytes: 1024,
  releaseNotes: const ['新增静默升级'],
  publishedAt: DateTime.utc(2026, 9, 3),
);

class _FakeAppUpdateRepository implements AppUpdateRepository {
  _FakeAppUpdateRepository(this.result);

  final AppUpdate? result;
  int requestCount = 0;

  @override
  Future<AppUpdate?> findAvailableUpdate({required int currentVersionCode}) async {
    requestCount += 1;
    return result;
  }
}

class _FakeAppUpdatePlatform implements AppUpdatePlatform {
  AppPlatformInfo platformInfo = const AppPlatformInfo(
    supported: true,
    versionName: '0.1.0',
    versionCode: 1,
  );
  UpdateDownloadSnapshot snapshot = const UpdateDownloadSnapshot.notFound();
  UpdateInstallResult installResult = UpdateInstallResult.opened;
  AppUpdate? startedUpdate;
  int startCount = 0;

  @override
  Future<AppPlatformInfo> getPlatformInfo() async => platformInfo;

  @override
  Future<UpdateDownloadSnapshot> getDownloadStatus() async => snapshot;

  @override
  Future<UpdateInstallResult> installDownloadedUpdate() async => installResult;

  @override
  Future<void> startDownload(AppUpdate update) async {
    startedUpdate = update;
    startCount += 1;
  }
}
