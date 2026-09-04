import 'package:bobo_learning/ui/features/player/services/playback_contract.dart';
import 'package:bobo_learning/ui/features/player/services/playback_controller_video_player.dart'
    if (dart.library.js_interop) 'package:bobo_learning/ui/features/player/services/playback_controller_web.dart'
    as platform;

export 'package:bobo_learning/ui/features/player/services/playback_contract.dart';

/// 按运行平台选择播放内核：Web 使用原生 video，其余平台使用 video_player。
class VideoPlayerControllerFactory implements PlaybackControllerFactory {
  const VideoPlayerControllerFactory();

  @override
  PlaybackController create(Uri streamUri, {Uri? hlsUri}) {
    return platform.createPlatformPlaybackController(streamUri, hlsUri: hlsUri);
  }
}
