//
//  VideoPlayerView.swift
//  GSPlayer
//
//  Created by Gesen on 2019/4/20.
//  Copyright © 2019 Gesen. All rights reserved.
//
#if !os(macOS)
import UIKit
import AVFoundation

open class VideoPlayerView: UIView {
    
    public enum State {
        
        /// None
        case none
        
        /// From the first load to get the first frame of the video
        case loading
        
        /// Playing now
        case playing
        
        /// Pause, will be called repeatedly when the buffer progress changes
        case paused(playProgress: Double, bufferProgress: Double)
        
        /// An error occurred and cannot continue playing
        case error(NSError)
    }
    
    public enum PausedReason: Int {
        
        /// Pause because the player is not visible, stateDidChanged is not called when the buffer progress changes
        case hidden
        
        /// Pause triggered by user interaction, default behavior
        case userInteraction
        
        /// Waiting for resource completion buffering
        case waitingKeepUp
    }
    
    /// An object that manages a player's visual output.
    public let playerLayer = AVPlayerLayer()
    
    /// An object that provides the interface to control the player’s transport behavior.
    public var player: AVPlayer? {
        get { playerLayer.player }
        set { playerLayer.player = newValue }
    }
    
    /// URL currently playing.
    public private(set) var playerURL: URL?
    
    /// Get current video status.
    public private(set) var state: State = .none {
        didSet { stateDidChanged(state: state, previous: oldValue) }
    }
    
    /// The reason the video was paused.
    public private(set) var pausedReason: PausedReason = .waitingKeepUp
    
    /// Number of replays.
    public private(set) var replayCount: Int = 0
    
    /// Whether the video will be automatically replayed until the end of the video playback.
    open var isAutoReplay: Bool = true
    
    /// Play to the end time.
    open var playToEndTime: (() -> Void)?
    
    /// Playback status changes, such as from play to pause.
    open var stateDidChanged: ((State) -> Void)?
    
    /// Replay after playing to the end.
    open var replay: (() -> Void)?
    
    /// Whether the video is muted, only for this instance.
    open var isMuted: Bool {
        get { player?.isMuted ?? false }
        set { player?.isMuted = newValue }
    }

    /// Video speed rate
    open var speedRate: Float = 1.0

    /// Video volume, only for this instance.
    open var volume: Double {
        get { player?.volume.double ?? 0 }
        set { player?.volume = newValue.float }
    }

    // Cached non-blocking playback details
    private var cachedPlayProgress: Double = 0
    private var cachedCurrentDuration: Double = 0
    private var cachedBufferProgress: Double = 0
    private var cachedBufferDuration: Double = 0
    private var cachedTotalDuration: Double = 0

    public var playProgress: Double { cachedPlayProgress }
    public var currentDuration: Double { cachedCurrentDuration }
    public var bufferProgress: Double { cachedBufferProgress }
    public var currentBufferDuration: Double { cachedBufferDuration }
    public var totalDuration: Double { cachedTotalDuration }

    public var watchDuration: Double {
        return isLoaded ? currentDuration + totalDuration * Double(replayCount) : 0
    }
    
    private var isLoaded = false
    private var isReplay = false
    
    private var playerBufferingObservation: NSKeyValueObservation?
    private var playerItemKeepUpObservation: NSKeyValueObservation?
    private var playerItemStatusObservation: NSKeyValueObservation?
    private var playerLayerReadyForDisplayObservation: NSKeyValueObservation?
    private var playerTimeControlStatusObservation: NSKeyValueObservation?
    private var timeObserverToken: Any?

    open override var contentMode: UIView.ContentMode {
        didSet {
            switch contentMode {
            case .scaleAspectFill: playerLayer.videoGravity = .resizeAspectFill
            case .scaleAspectFit:  playerLayer.videoGravity = .resizeAspect
            default:               playerLayer.videoGravity = .resize
            }
        }
    }
    
    public init() {
        super.init(frame: .zero)
        configureInit()
    }
    
    required public init?(coder aDecoder: NSCoder) {
        super.init(coder: aDecoder)
        configureInit()
    }
    
    open override func layoutSubviews() {
        super.layoutSubviews()
        guard playerLayer.superlayer == layer else { return }
        
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        playerLayer.frame = bounds
        CATransaction.commit()
    }
    
    deinit {
        removePeriodicObserver()
        playerLayerReadyForDisplayObservation?.invalidate()
        playerTimeControlStatusObservation?.invalidate()
        playerBufferingObservation?.invalidate()
        playerItemStatusObservation?.invalidate()
        playerItemKeepUpObservation?.invalidate()
        NotificationCenter.default.removeObserver(self)
    }
}

// MARK: - Player controls
@objc extension VideoPlayerView {
    
    /// Play a video of the specified url.
    ///
    /// - Parameter url: Can be a local or remote URL
    open func play(for url: URL) {
        guard playerURL != url else {
            pausedReason = .waitingKeepUp
            player?.playImmediately(atRate: speedRate)
            return
        }
        
        observe(player: nil)
        observe(playerItem: nil)
        removePeriodicObserver()

        player?.currentItem?.cancelPendingSeeks()
        player?.currentItem?.asset.cancelLoading()

        let player = AVPlayer()
        player.automaticallyWaitsToMinimizeStalling = false

        DispatchQueue.main.async {
            let playerItem = AVPlayerItem(url: url)
            playerItem.canUseNetworkResourcesForLiveStreamingWhilePaused = true

            self.player = player
            self.playerURL = url
            self.pausedReason = .waitingKeepUp
            self.replayCount = 0
            self.isReplay = false
            self.isLoaded = false

            if playerItem.status == .readyToPlay || url.isFileURL {
                self.state = .none
                self.isLoaded = true
                player.playImmediately(atRate: self.speedRate)
            } else {
                self.state = .loading
            }

            player.replaceCurrentItem(with: playerItem)
            self.observe(player: player)
            self.observe(playerItem: playerItem)
            self.startPeriodicProgressObserver()
        }
        
    }
    
    /// Replay video.
    ///
    /// - Parameter resetCount: Reset replayCount
    open func replay(resetCount: Bool = false) {
        replayCount = resetCount ? 0 : replayCount + 1
        player?.seek(to: .zero)
        resume()
    }
    
    /// Continue playing video.
    open func resume() {
        pausedReason = .waitingKeepUp
        player?.playImmediately(atRate: speedRate)
    }
    
    /// Pause video.
    open func pause() {
        player?.pause()
    }
    
    /// Moves the playback cursor and invokes the specified block when the seek operation has either been completed or been interrupted.
    open func seek(to time: CMTime, completion: ((Bool) -> Void)? = nil) {
        player?.seek(to: time) { completion?($0) }
    }

    open func seek(to time: CMTime, toleranceBefore: CMTime, toleranceAfter: CMTime,
                   completion: @escaping (Bool) -> Void) {
        player?.seek(to: time,
                     toleranceBefore: toleranceBefore,
                     toleranceAfter: toleranceAfter,
                     completionHandler: completion)
    }

    @discardableResult
    open func addBoundaryTimeObserver(forTimes times: [CMTime],
                                      queue: DispatchQueue? = nil,
                                      using: @escaping () -> Void) -> Any? {
        return player?.addBoundaryTimeObserver(forTimes: times.map(NSValue.init),
                                               queue: queue,
                                               using: using)
    }

    @discardableResult
    open func addPeriodicTimeObserver(forInterval interval: CMTime,
                                      queue: DispatchQueue? = nil,
                                      using: @escaping (CMTime) -> Void) -> Any? {
        player?.addPeriodicTimeObserver(forInterval: interval, queue: queue, using: using)
    }

    open func removeTimeObserver(_ observer: Any) {
        player?.removeTimeObserver(observer)
    }

    public func destroy() {
        removePeriodicObserver()
        player = nil
        NotificationCenter.default.removeObserver(self)
        removeFromSuperview()
    }

    open func playAudioTrack(index: Int) {
        guard
            let asset = player?.currentItem?.asset,
            let group = asset.mediaSelectionGroup(forMediaCharacteristic: .audible),
            group.options.count > index
        else { return }

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            self?.player?.currentItem?.select(group.options[index], in: group)
        }
    }
}

public extension VideoPlayerView {
    
    /// Pause video.
    ///
    /// - Parameter reason: Reason for pause
    func pause(reason: PausedReason) {
        pausedReason = reason
        pause()
    }
}

private extension VideoPlayerView {
    
    func configureInit() {
        
        isHidden = true
        
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(playerItemDidReachEnd(notification:)),
            name: .AVPlayerItemDidPlayToEndTime,
            object: nil
        )
        
        layer.addSublayer(playerLayer)
    }
    
    func stateDidChanged(state: State, previous: State) {
        guard state != previous else { return }

        switch state {
        case .playing, .paused:
            isHidden = false
        default:
            isHidden = true
        }
        
        stateDidChanged?(state)
    }
    
    func observe(player: AVPlayer?) {
        
        guard let player = player else {
            playerLayerReadyForDisplayObservation?.invalidate()
            playerTimeControlStatusObservation?.invalidate()
            playerLayerReadyForDisplayObservation = nil
            playerTimeControlStatusObservation = nil
            return
        }

        playerLayerReadyForDisplayObservation =
            playerLayer.observe(\.isReadyForDisplay) { [weak self, weak player] layer, _ in
                guard let self = self, let player = player else { return }
                if layer.isReadyForDisplay, player.rate > 0 {
                    self.isLoaded = true
                    self.state = .playing
                }
            }

        playerTimeControlStatusObservation =
            player.observe(\.timeControlStatus) { [weak self] player, _ in
                guard let self = self else { return }
                switch player.timeControlStatus {
                case .paused:
                    self.state = .paused(playProgress: self.playProgress,
                                         bufferProgress: self.bufferProgress)
                    if self.pausedReason == .waitingKeepUp {
                        player.playImmediately(atRate: self.speedRate)
                    }
                case .playing:
                    if self.playerLayer.isReadyForDisplay, player.rate > 0 {
                        self.isLoaded = true
                        if self.playProgress == 0, self.isReplay {
                            self.isReplay = false
                            break
                        }
                        self.state = .playing
                    }
                default:
                    break
                }
            }
    }
    
    func observe(playerItem: AVPlayerItem?) {
        guard let item = playerItem else {
            playerBufferingObservation?.invalidate()
            playerItemStatusObservation?.invalidate()
            playerItemKeepUpObservation?.invalidate()
            playerBufferingObservation = nil
            playerItemStatusObservation = nil
            playerItemKeepUpObservation = nil
            return
        }

        playerBufferingObservation =
            item.observe(\.loadedTimeRanges) { [weak self] item, _ in
                guard let self = self else { return }
                self.updateBufferProgress(item)

                if case .paused = self.state, self.pausedReason != .hidden {
                    self.state = .paused(playProgress: self.playProgress,
                                         bufferProgress: self.bufferProgress)
                }
            }

        playerItemStatusObservation =
            item.observe(\.status) { [weak self] item, _ in
                guard let self = self else { return }
                if item.status == .failed, let error = item.error as NSError? {
                    self.state = .error(error)
                }
            }

        playerItemKeepUpObservation =
            item.observe(\.isPlaybackLikelyToKeepUp) { [weak self] item, _ in
                guard let self = self else { return }
                if item.isPlaybackLikelyToKeepUp,
                   self.player?.rate == 0,
                   self.pausedReason == .waitingKeepUp {
                    self.player?.playImmediately(atRate: self.speedRate)
                }
            }
    }

    @objc func playerItemDidReachEnd(notification: Notification) {
        guard (notification.object as? AVPlayerItem) == player?.currentItem else { return }

        playToEndTime?()

        guard isAutoReplay, pausedReason == .waitingKeepUp else { return }
        isReplay = true
        replay?()
        replayCount += 1

        player?.seek(to: .zero)
        player?.playImmediately(atRate: speedRate)
    }

    func startPeriodicProgressObserver() {
        guard let player = player else { return }
        let interval = CMTime(seconds: 0.5, preferredTimescale: CMTimeScale(NSEC_PER_SEC))
        timeObserverToken = player.addPeriodicTimeObserver(forInterval: interval,
                                                           queue: .main) { [weak self] time in
            self?.updateTimeValues()
        }
    }

    func removePeriodicObserver() {
        if let token = timeObserverToken, let player = player {
            player.removeTimeObserver(token)
            timeObserverToken = nil
        }
    }

    func updateTimeValues() {
        guard let item = player?.currentItem else { return }
        let duration = item.duration.seconds
        let current = item.currentTime().seconds
        cachedTotalDuration = duration.isFinite ? duration : 0
        cachedCurrentDuration = current.isFinite ? current : 0
        cachedPlayProgress = duration > 0 ? current / duration : 0
        updateBufferProgress(item)
    }

    func updateBufferProgress(_ item: AVPlayerItem) {
        guard let timeRange = item.loadedTimeRanges.first?.timeRangeValue else { return }
        let buffered = CMTimeGetSeconds(timeRange.start) + CMTimeGetSeconds(timeRange.duration)
        cachedBufferDuration = buffered
        if cachedTotalDuration > 0 {
            cachedBufferProgress = buffered / cachedTotalDuration
        }
    }
}

extension VideoPlayerView.State: Equatable {
    public static func == (lhs: VideoPlayerView.State, rhs: VideoPlayerView.State) -> Bool {
        switch (lhs, rhs) {
        case (.none, .none),
             (.loading, .loading),
             (.playing, .playing):
            return true
        case let (.paused(p1, b1), .paused(p2, b2)):
            return p1 == p2 && b1 == b2
        case let (.error(e1), .error(e2)):
            return e1 == e2
        default:
            return false
        }
    }
}
#endif
