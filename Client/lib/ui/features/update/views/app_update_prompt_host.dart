import 'package:bobo_learning/domain/models/app_update.dart';
import 'package:bobo_learning/ui/core/app_theme.dart';
import 'package:bobo_learning/ui/features/update/view_models/app_update_view_model.dart';
import 'package:flutter/material.dart';

/// 在应用内容之上统一展示升级完成提示和非阻塞错误消息。
class AppUpdatePromptHost extends StatefulWidget {
  const AppUpdatePromptHost({required this.viewModel, required this.child, super.key});

  final AppUpdateViewModel viewModel;
  final Widget child;

  @override
  State<AppUpdatePromptHost> createState() => _AppUpdatePromptHostState();
}

class _AppUpdatePromptHostState extends State<AppUpdatePromptHost> {
  int? _promptedVersionCode;
  String? _shownError;
  bool _dialogVisible = false;

  @override
  void initState() {
    super.initState();
    widget.viewModel.addListener(_handleStateChanged);
    _handleStateChanged();
  }

  @override
  void didUpdateWidget(covariant AppUpdatePromptHost oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.viewModel != widget.viewModel) {
      oldWidget.viewModel.removeListener(_handleStateChanged);
      widget.viewModel.addListener(_handleStateChanged);
      _handleStateChanged();
    }
  }

  void _handleStateChanged() {
    if (!mounted) {
      return;
    }
    final viewModel = widget.viewModel;
    final update = viewModel.update;
    if (viewModel.phase == AppUpdatePhase.ready &&
        update != null &&
        update.versionCode != _promptedVersionCode &&
        !_dialogVisible) {
      _promptedVersionCode = update.versionCode;
      _dialogVisible = true;
      WidgetsBinding.instance.addPostFrameCallback((_) => _showUpdateDialog(update));
    }

    final message = viewModel.message;
    if (viewModel.phase == AppUpdatePhase.failed && message != null && message != _shownError) {
      _shownError = message;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) {
          return;
        }
        ScaffoldMessenger.maybeOf(
          context,
        )?.showSnackBar(SnackBar(content: Text(message), showCloseIcon: true));
      });
    }
  }

  Future<void> _showUpdateDialog(AppUpdate update) async {
    if (!mounted) {
      _dialogVisible = false;
      return;
    }
    final shouldInstall = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => _UpdateReadyDialog(update: update),
    );
    _dialogVisible = false;
    if (!mounted || shouldInstall != true) {
      return;
    }

    final result = await widget.viewModel.install();
    if (!mounted || result != UpdateInstallResult.permissionRequired) {
      return;
    }
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(
      const SnackBar(content: Text('请开启“允许来自此来源的应用”，返回后会继续安装'), duration: Duration(seconds: 6)),
    );
  }

  @override
  void dispose() {
    widget.viewModel.removeListener(_handleStateChanged);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

class _UpdateReadyDialog extends StatelessWidget {
  const _UpdateReadyDialog({required this.update});

  final AppUpdate update;

  @override
  Widget build(BuildContext context) {
    final notes = update.releaseNotes.isEmpty ? const ['优化体验并提升稳定性'] : update.releaseNotes;
    return AlertDialog(
      key: const Key('应用更新弹窗'),
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
      icon: DecoratedBox(
        decoration: BoxDecoration(
          color: AppColors.mintMist,
          shape: BoxShape.circle,
          border: Border.all(color: AppColors.teal.withValues(alpha: 0.2)),
        ),
        child: const SizedBox.square(
          dimension: 68,
          child: Icon(Icons.system_update_alt_rounded, color: AppColors.tealDark, size: 34),
        ),
      ),
      title: const Text('新版本已经准备好', textAlign: TextAlign.center),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: AppColors.skyMist,
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                    child: Text(
                      '菠萝乐园 ${update.versionName}',
                      style: Theme.of(
                        context,
                      ).textTheme.labelLarge?.copyWith(color: AppColors.tealDark),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 18),
              Text('更新内容', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 10),
              for (final note in notes)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Padding(
                        padding: EdgeInsets.only(top: 5),
                        child: Icon(Icons.star_rounded, color: AppColors.sunshine, size: 18),
                      ),
                      const SizedBox(width: 8),
                      Expanded(child: Text(note)),
                    ],
                  ),
                ),
              const SizedBox(height: 8),
              Text(
                '安装包已在后台下载并通过安全校验。点击后将打开 Android 系统安装页面。',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ],
          ),
        ),
      ),
      actionsAlignment: MainAxisAlignment.center,
      actionsPadding: const EdgeInsets.fromLTRB(24, 4, 24, 22),
      actions: [
        TextButton(
          key: const Key('应用更新稍后按钮'),
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('稍后'),
        ),
        FilledButton.icon(
          key: const Key('应用更新安装按钮'),
          onPressed: () => Navigator.of(context).pop(true),
          icon: const Icon(Icons.restart_alt_rounded),
          label: const Text('重启并安装'),
        ),
      ],
    );
  }
}
