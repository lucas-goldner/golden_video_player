import Flutter
import UIKit
import AVFoundation
import AVKit

public class NativeVideoPlayerViewFactory: NSObject, FlutterPlatformViewFactory {
    public static let id = "native_video_player_view"

    private let messenger: FlutterBinaryMessenger

    init(messenger: FlutterBinaryMessenger) {
        self.messenger = messenger
        super.init()
    }

    public func create(
        withFrame frame: CGRect,
        viewIdentifier viewId: Int64,
        arguments args: Any?
    ) -> FlutterPlatformView {
        // Parse creation arguments to get showNativeControls flag
        let showNativeControls = (args as? [String: Any])?["showNativeControls"] as? Bool ?? false

        if showNativeControls {
            return NativeVideoPlayerViewWithControls(
                messenger: messenger,
                viewId: viewId,
                frame: frame
            )
        } else {
            return NativeVideoPlayerView(
                messenger: messenger,
                viewId: viewId,
                frame: frame
            )
        }
    }
}

class NativeVideoPlayerView: UIView, FlutterPlatformView {
    private let messenger: FlutterBinaryMessenger
    private let playerLayer: AVPlayerLayer
    private let controller: NativeVideoPlayerController

    required init?(coder: NSCoder) {
        fatalError("init(coder:) - use init(frame:) instead")
    }

    init(
        messenger: FlutterBinaryMessenger,
        viewId: Int64,
        frame: CGRect
    ) {
        self.messenger = messenger
        self.playerLayer = AVPlayerLayer()

        self.controller = NativeVideoPlayerController(
            messenger: messenger,
            viewId: viewId,
            playerLayer: self.playerLayer)

        self.playerLayer.player = controller.player

        super.init(frame: frame)

        NativeVideoPlayerHostApiSetup.setUp(
            binaryMessenger: messenger,
            api: controller,
            messageChannelSuffix: String(viewId))

        setupView(viewId: viewId)
    }

    deinit {
        playerLayer.removeFromSuperlayer()

        controller.dispose()

        NativeVideoPlayerHostApiSetup.setUp(
            binaryMessenger: messenger,
            api: nil)
    }

    private func setupView(viewId: Int64) {
        playerLayer.videoGravity = .resize

        backgroundColor = UIColor.clear
        layer.addSublayer(playerLayer)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        playerLayer.frame = bounds
        playerLayer.removeAllAnimations()
    }

    func view() -> UIView {
        return self
    }
}

class NativeVideoPlayerViewWithControls: UIView, FlutterPlatformView {
    private let messenger: FlutterBinaryMessenger
    private let controller: NativeVideoPlayerController
    private let playerViewController: AVPlayerViewController
    private var controlsHideTimer: Timer?

    required init?(coder: NSCoder) {
        fatalError("init(coder:) - use init(frame:) instead")
    }

    init(
        messenger: FlutterBinaryMessenger,
        viewId: Int64,
        frame: CGRect
    ) {
        self.messenger = messenger

        self.playerViewController = AVPlayerViewController()

        self.controller = NativeVideoPlayerController(
            messenger: messenger,
            viewId: viewId,
            playerViewController: playerViewController)

        super.init(frame: frame)

        // Set up the player view controller with the player from controller
        playerViewController.player = controller.player
        playerViewController.allowsPictureInPicturePlayback = true
        playerViewController.showsPlaybackControls = true
        playerViewController.exitsFullScreenWhenPlaybackEnds = false

        // Add the player view controller's view as a subview
        addSubview(playerViewController.view)
        playerViewController.view.frame = bounds
        playerViewController.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]

        // Keep controls visible by preventing them from hiding
        startKeepingControlsVisible()

        // Add tap gesture to show controls
        let tapGesture = UITapGestureRecognizer(target: self, action: #selector(handleTap))
        addGestureRecognizer(tapGesture)

        NativeVideoPlayerHostApiSetup.setUp(
            binaryMessenger: messenger,
            api: controller,
            messageChannelSuffix: String(viewId))
    }

    @objc private func handleTap() {
        // Tapping will toggle controls visibility, and we'll keep them visible
        startKeepingControlsVisible()
    }

    private func startKeepingControlsVisible() {
        // Cancel existing timer
        controlsHideTimer?.invalidate()

        // Show controls immediately
        playerViewController.showsPlaybackControls = true

        // Keep refreshing the state to prevent them from hiding
        controlsHideTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            self?.playerViewController.showsPlaybackControls = true
        }
    }

    deinit {
        controlsHideTimer?.invalidate()
        controller.dispose()

        NativeVideoPlayerHostApiSetup.setUp(
            binaryMessenger: messenger,
            api: nil)

        playerViewController.view.removeFromSuperview()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        playerViewController.view.frame = bounds
    }

    func view() -> UIView {
        return self
    }
}
