import 'package:bobo_learning/domain/models/app_update.dart';

abstract interface class AppUpdateRepository {
  /// 返回比当前构建号更高的更新；没有更新时返回空。
  Future<AppUpdate?> findAvailableUpdate({required int currentVersionCode});
}
