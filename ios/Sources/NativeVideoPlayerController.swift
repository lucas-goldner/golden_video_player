import Flutter
import AVFoundation
import AVKit

class NativeVideoPlayerController: NSObject, NativeVideoPlayerHostApi {
    let player: AVPlayer
    private let flutterApi: NativeVideoPlayerFlutterApi
    private var pictureInPictureController: Any?
    private var pictureInPictureDelegate: PictureInPictureDelegate?
    private weak var playerLayer: AVPlayerLayer?

    init(messenger: FlutterBinaryMessenger, viewId: Int64) {
        self.player = AVPlayer(playerItem: nil)
        self.flutterApi = NativeVideoPlayerFlutterApi(
            binaryMessenger: messenger,
            messageChannelSuffix: String(viewId))
        super.init()
        
        player.addObserver(self, forKeyPath: "status", context: nil)
        
        // Allow audio playback when the Ring/Silent switch is set to silent
        do {
            try AVAudioSession.sharedInstance().setCategory(
                .playback,
                mode: .default,
                options: [.mixWithOthers])
            try AVAudioSession.sharedInstance().setActive(true)
        } catch {
            flutterApi.onPlaybackEvent(
                event: PlaybackErrorEvent(errorMessage: "Failed to set audio session category: \(error.localizedDescription)")
            ) { _ in }
        }
    }
    
    func dispose() {
        removePlayerItemObservers()
        player.removeObserver(self, forKeyPath: "status")
        player.replaceCurrentItem(with: nil)
    }
    
    func loadVideo(source: VideoSource) throws {
        let isUrl = source.type == .network

        guard let uri = isUrl
            ? URL(string: source.path)
            : URL(fileURLWithPath: source.path)
        else {
            return
        }

        let videoAsset: AVAsset
        if isUrl {
            var options: [String: Any] = [:]
            if let headers = source.headers {
                options["AVURLAssetHTTPHeaderFieldsKey"] = headers
            }
            videoAsset = AVURLAsset(url: uri, options: options.isEmpty ? nil : options)
        } else {
            videoAsset = AVAsset(url: uri)
        }

        // Load asset properties asynchronously
        let requiredKeys = ["tracks", "duration", "playable"]
        videoAsset.loadValuesAsynchronously(forKeys: requiredKeys) { [weak self] in
            DispatchQueue.main.async {
                self?.handleAssetLoaded(videoAsset: videoAsset, requiredKeys: requiredKeys)
            }
        }
    }

    private func handleAssetLoaded(videoAsset: AVAsset, requiredKeys: [String]) {
        // Check if asset was loaded successfully
        for key in requiredKeys {
            var error: NSError?
            let status = videoAsset.statusOfValue(forKey: key, error: &error)

            if status == .failed {
                flutterApi.onPlaybackEvent(
                    event: PlaybackErrorEvent(errorMessage: "Failed to load asset property: \(key)")
                ) { _ in }
                return
            }
        }

        // Check if playable
        if !videoAsset.isPlayable {
            flutterApi.onPlaybackEvent(event: PlaybackErrorEvent(errorMessage: "Video is not playable")) { _ in }
            return
        }

        // loadVideo can be called multiple times,
        // so we need to remove the previous observers
        if player.currentItem != nil {
            removePlayerItemObservers()
        }

        let playerItem = AVPlayerItem(asset: videoAsset)
        player.replaceCurrentItem(with: playerItem)

        addPlayerItemObservers()
    }

    func getVideoInfo() throws -> VideoInfo {
        guard let asset = player.currentItem?.asset else {
            return VideoInfo(height: 0, width: 0, durationInMilliseconds: 0)
        }

        // Check duration property status
        var durationError: NSError?
        let durationStatus = asset.statusOfValue(forKey: "duration", error: &durationError)
        guard durationStatus == .loaded || durationStatus == .unknown else {
            return VideoInfo(height: 0, width: 0, durationInMilliseconds: 0)
        }

        let duration = asset.duration
        let durationInMilliseconds = duration.isValid
            ? duration.seconds * 1000
            : 0

        // Check tracks property status
        var tracksError: NSError?
        let tracksStatus = asset.statusOfValue(forKey: "tracks", error: &tracksError)
        guard tracksStatus == .loaded || tracksStatus == .unknown else {
            return VideoInfo(height: 0, width: 0, durationInMilliseconds: Int64(durationInMilliseconds))
        }

        guard let videoTrack = asset.tracks(withMediaType: .video).first else {
            return VideoInfo(height: 0, width: 0, durationInMilliseconds: Int64(durationInMilliseconds))
        }

        // Get naturalSize synchronously after ensuring tracks are loaded
        let size = videoTrack.naturalSize

        return VideoInfo(
            height: Int64(size.height),
            width: Int64(size.width),
            durationInMilliseconds: Int64(durationInMilliseconds)
        )
    }

    func play(speed: Double) throws {
        player.rate = Float(speed)
    }

    func pause() throws {
        player.rate = 0.0
    }

    func stop() throws {
        player.rate = 0.0
        player.seek(to: .zero)
    }

    func isPlaying() throws -> Bool {
        return player.rate != 0 && player.error == nil
    }

    func seekTo(position: Int64) throws {
        let positionInMilliseconds = CMTimeMake(value: position, timescale: 1000)
        player.seek(
            to: positionInMilliseconds,
            toleranceBefore: .zero,
            toleranceAfter: .zero)
    }

    func getPlaybackPosition() throws -> Int64 {
        let currentTime = player.currentItem?.currentTime() ?? .zero
        let positionInMilliseconds = currentTime.isValid
            ? currentTime.seconds * 1000
            : 0
        return Int64(positionInMilliseconds)
    }

    func setPlaybackSpeed(speed: Double) throws {
        player.rate = Float(speed)
    }

    func setVolume(volume: Double) throws {
        player.volume = Float(volume)
    }

    func setPlayerLayer(_ layer: AVPlayerLayer) {
        self.playerLayer = layer
        setupPictureInPicture()
    }

    func enterPictureInPicture() throws {
        guard let controller = pictureInPictureController as? AVPictureInPictureController else {
            flutterApi.onPlaybackEvent(
                event: PlaybackErrorEvent(errorMessage: "Picture in Picture is not available")
            ) { _ in }
            return
        }

        guard player.currentItem != nil else {
            flutterApi.onPlaybackEvent(
                event: PlaybackErrorEvent(errorMessage: "No video loaded")
            ) { _ in }
            return
        }

        if !controller.isPictureInPictureActive {
            controller.startPictureInPicture()
        }
    }

    func exitPictureInPicture() throws {
        guard let controller = pictureInPictureController as? AVPictureInPictureController else {
            return
        }
        if controller.isPictureInPictureActive {
            controller.stopPictureInPicture()
        }
    }

    func isPictureInPictureActive() throws -> Bool {
        guard let controller = pictureInPictureController as? AVPictureInPictureController else {
            return false
        }
        return controller.isPictureInPictureActive
    }

    private func setupPictureInPicture() {
        guard let playerLayer = playerLayer else { return }

        // Only setup PIP if it's supported
        guard AVPictureInPictureController.isPictureInPictureSupported() else {
            return
        }

        // Create the PIP controller
        if let pipController = AVPictureInPictureController(playerLayer: playerLayer) {
            let delegate = PictureInPictureDelegate(flutterApi: flutterApi)
            pipController.delegate = delegate
            pictureInPictureController = pipController
            // Keep a strong reference to the delegate
            self.pictureInPictureDelegate = delegate
        }
    }

    override public func observeValue(
        forKeyPath keyPath: String?,
        of object: Any?,
        change: [NSKeyValueChangeKey: Any]?,
        context: UnsafeMutableRawPointer?
    ) {
        if keyPath == "status" {
            // print("AVPlayer status changed to: \(player.status)")
            switch (player.status) {
            case .unknown:
                break
            case .readyToPlay:
                flutterApi.onPlaybackEvent(
                    event: PlaybackReadyEvent()
                ) { _ in }
                break
            case .failed:
                if let error = player.error {
                    flutterApi.onPlaybackEvent(
                        event: PlaybackErrorEvent(errorMessage: error.localizedDescription)
                    ) { _ in }
                }
            default:
                break
            }
        }
    }

    // MARK: - Player Item Notifications

    private let playerItemNotifications: [NSNotification.Name] = [
        // A notification the system posts when a player item plays to its end time.
        AVPlayerItem.didPlayToEndTimeNotification,
        // A notification that the system posts when a player item fails to play to its end time.
        // AVPlayerItem.failedToPlayToEndTimeNotification,
        // A notification the system posts when a player item's time changes discontinuously.
        // AVPlayerItem.timeJumpedNotification,
        // A notification the system posts when a player item media doesn't arrive in time to continue playback.
        // AVPlayerItem.playbackStalledNotification,
        // A notification the player item posts when its media selection changes.
        // AVPlayerItem.mediaSelectionDidChangeNotification,
        // A notification the player item posts when its offset from the live time changes.
        // AVPlayerItem.recommendedTimeOffsetFromLiveDidChangeNotification,
        // A notification the system posts when a player item adds a new entry to its access log.
        // AVPlayerItem.newAccessLogEntryNotification,
        // A notification the system posts when a player item adds a new entry to its error log.
        // AVPlayerItem.newErrorLogEntryNotification
    ]

    @objc
    private func onPlayerItemNotification(notification: NSNotification) {
        // print("AVPlayerItem notification: \(notification.name)")
        switch notification.name {
        case AVPlayerItem.didPlayToEndTimeNotification:
            flutterApi.onPlaybackEvent(event: PlaybackEndedEvent()) { _ in }
            break
//        case AVPlayerItem.failedToPlayToEndTimeNotification:
//            break
//        case AVPlayerItem.timeJumpedNotification:
//            break
//        case AVPlayerItem.playbackStalledNotification:
//            break
//       case AVPlayerItem.mediaSelectionDidChangeNotification:
//           break
//       case AVPlayerItem.recommendedTimeOffsetFromLiveDidChangeNotification:
//           break
//        case AVPlayerItem.newAccessLogEntryNotification:
//            break
//        case AVPlayerItem.newErrorLogEntryNotification:
//            break
        default:
            break
        }
    }

    private func addPlayerItemObservers() {
        for notification in playerItemNotifications {
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(onPlayerItemNotification(notification:)),
                name: notification,
                object: player.currentItem)
        }
    }

    private func removePlayerItemObservers() {
        for notification in playerItemNotifications {
            NotificationCenter.default.removeObserver(
                self,
                name: notification,
                object: player.currentItem)
        }
    }
}

// MARK: - Picture in Picture Delegate (iOS 9.0+)

private class PictureInPictureDelegate: NSObject, AVPictureInPictureControllerDelegate {
    private let flutterApi: NativeVideoPlayerFlutterApi

    init(flutterApi: NativeVideoPlayerFlutterApi) {
        self.flutterApi = flutterApi
        super.init()
    }

    func pictureInPictureControllerDidStartPictureInPicture(_ pictureInPictureController: AVPictureInPictureController) {
        flutterApi.onPlaybackEvent(
            event: PictureInPictureStatusChangedEvent(isActive: true)
        ) { _ in }
    }

    func pictureInPictureControllerDidStopPictureInPicture(_ pictureInPictureController: AVPictureInPictureController) {
        flutterApi.onPlaybackEvent(
            event: PictureInPictureStatusChangedEvent(isActive: false)
        ) { _ in }
    }
}
