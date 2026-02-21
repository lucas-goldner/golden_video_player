import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:golden_video_player/src/controller.dart';

/// A [StatefulWidget] that is responsible for displaying a video.
///
/// On iOS, the video is displayed using a combination
/// of AVPlayer and AVPlayerLayer.
///
/// On Android, the video is displayed using a combination
/// of MediaPlayer and VideoView.
class NativeVideoPlayerView extends StatefulWidget {
  /// Callback that is triggered when the native video player view is ready.
  ///
  /// This callback provides a [NativeVideoPlayerController] instance that can be used
  /// to control the video playback (play, pause, seek, etc.). The controller is
  /// created after the native platform view has been successfully initialized.
  ///
  /// Example usage:
  /// ```dart
  /// NativeVideoPlayerView(
  ///   onViewReady: (controller) {
  ///     // Store the controller for later use
  ///     _controller = controller;
  ///   },
  /// )
  /// ```
  final void Function(NativeVideoPlayerController) onViewReady;

  /// Whether to show native video controls provided by the platform.
  ///
  /// When set to true, the platform's native video player controls will be
  /// displayed. On iOS, this uses AVPlayerViewController. On macOS, this uses
  /// AVPlayerView. On Android, this uses ExoPlayer's PlayerView with Material
  /// Design controls.
  ///
  /// Defaults to false, which uses only the AVPlayerLayer/SurfaceView without
  /// controls.
  final bool showNativeControls;

  const NativeVideoPlayerView({
    super.key,
    required this.onViewReady,
    this.showNativeControls = false,
  });

  @override
  State<NativeVideoPlayerView> createState() => _NativeVideoPlayerViewState();
}

class _NativeVideoPlayerViewState extends State<NativeVideoPlayerView> {
  @override
  Widget build(BuildContext context) {
    const viewType = 'native_video_player_view';
    final creationParams = {'showNativeControls': widget.showNativeControls};
    final key = ValueKey('native_video_player_${widget.showNativeControls}');
    final nativeView = switch (defaultTargetPlatform) {
      TargetPlatform.android => AndroidView(
          key: key,
          viewType: viewType,
          onPlatformViewCreated: onPlatformViewCreated,
          creationParams: creationParams,
          creationParamsCodec: const StandardMessageCodec(),
        ),
      TargetPlatform.iOS => UiKitView(
          key: key,
          viewType: viewType,
          onPlatformViewCreated: onPlatformViewCreated,
          creationParams: creationParams,
          creationParamsCodec: const StandardMessageCodec(),
        ),
      TargetPlatform.macOS => AppKitView(
          key: key,
          viewType: viewType,
          onPlatformViewCreated: onPlatformViewCreated,
          creationParams: creationParams,
          creationParamsCodec: const StandardMessageCodec(),
        ),
      _ => Text('$defaultTargetPlatform is not yet supported by this plugin.'),
    };

    /// RepaintBoundary is a widget that isolates repaints
    return RepaintBoundary(
      child: nativeView,
    );
  }

  /// This method is invoked by the platform view
  /// when the native view is created.
  Future<void> onPlatformViewCreated(int id) async {
    final controller = NativeVideoPlayerController(id);
    widget.onViewReady(controller);
  }
}
