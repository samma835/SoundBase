//
//  MediaPlayerManager.swift
//  SoundBase
//
//  Created by samma on 2026/1/22.
//

import AVFoundation
import MediaPlayer

class MediaPlayerManager: NSObject {  // 继承自NSObject以支持KVO
    static let shared = MediaPlayerManager()
    
    private(set) var player: AVPlayer?
    private var timeObserver: Any?
    private var currentPlayerItem: AVPlayerItem?
    
    // 当前播放信息
    private(set) var currentTitle: String?
    private(set) var currentArtist: String?
    private(set) var currentArtwork: UIImage?
    
    // 播放状态回调 - 使用通知
    static let playbackStateChangedNotification = Notification.Name("MediaPlayerPlaybackStateChanged")
    static let timeUpdateNotification = Notification.Name("MediaPlayerTimeUpdate")
    static let playbackFinishedNotification = Notification.Name("MediaPlayerPlaybackFinished")
    
    private override init() {
        super.init()
        setupAudioSession()
        setupRemoteCommandCenter()
    }
    
    // MARK: - Public Methods
    
    func play(url: URL, title: String? = nil, artist: String? = nil, artwork: UIImage? = nil) {
        print("🎵 [播放器管理] 播放: \(title ?? url.lastPathComponent)")
        
        // 如果已有player且URL相同，继续播放
        if let currentItem = player?.currentItem,
           let currentURL = (currentItem.asset as? AVURLAsset)?.url,
           currentURL == url {
            print("🎵 [播放器管理] 继续播放当前音频")
            player?.play()
            postPlaybackStateChanged(isPlaying: true)
            return
        }
        
        // 清理旧的观察者
        cleanupCurrentItem()
        
        // 创建新的player
        let playerItem = AVPlayerItem(url: url)
        currentPlayerItem = playerItem
        
        if player == nil {
            player = AVPlayer(playerItem: playerItem)
        } else {
            player?.replaceCurrentItem(with: playerItem)
        }
        
        // 保存播放信息
        currentTitle = title
        currentArtist = artist
        currentArtwork = artwork
        
        // 添加状态观察
        playerItem.addObserver(self, forKeyPath: "status", options: [.new, .initial], context: nil)
        
        // 监听播放进度
        let interval = CMTime(seconds: 0.5, preferredTimescale: CMTimeScale(NSEC_PER_SEC))
        timeObserver = player?.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
            guard let self = self,
                  let duration = self.player?.currentItem?.duration else { return }
            NotificationCenter.default.post(
                name: MediaPlayerManager.timeUpdateNotification,
                object: nil,
                userInfo: ["currentTime": time, "duration": duration]
            )
        }
        
        // 监听播放结束
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(playerDidFinishPlaying),
            name: .AVPlayerItemDidPlayToEndTime,
            object: playerItem
        )
        
        // 更新锁屏信息
        updateNowPlayingInfo()
        
        // 自动播放
        player?.play()
        postPlaybackStateChanged(isPlaying: true)
    }
    
    /// 准备播放器但不自动播放
    func prepare(url: URL, title: String? = nil, artist: String? = nil, artwork: UIImage? = nil) {
        print("🎵 [播放器管理] 准备: \(title ?? url.lastPathComponent)")
        
        // 如果已有player且URL相同，不做任何操作
        if let currentItem = player?.currentItem,
           let currentURL = (currentItem.asset as? AVURLAsset)?.url,
           currentURL == url {
            print("🎵 [播放器管理] 已准备相同音频")
            return
        }
        
        // 清理旧的观察者
        cleanupCurrentItem()
        
        // 创建新的player
        let playerItem = AVPlayerItem(url: url)
        currentPlayerItem = playerItem
        
        if player == nil {
            player = AVPlayer(playerItem: playerItem)
        } else {
            player?.replaceCurrentItem(with: playerItem)
        }
        
        // 保存播放信息
        currentTitle = title
        currentArtist = artist
        currentArtwork = artwork
        
        // 添加状态观察
        playerItem.addObserver(self, forKeyPath: "status", options: [.new, .initial], context: nil)
        
        // 监听播放进度
        let interval = CMTime(seconds: 0.5, preferredTimescale: CMTimeScale(NSEC_PER_SEC))
        timeObserver = player?.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
            guard let self = self,
                  let duration = self.player?.currentItem?.duration else { return }
            NotificationCenter.default.post(
                name: MediaPlayerManager.timeUpdateNotification,
                object: nil,
                userInfo: ["currentTime": time, "duration": duration]
            )
        }
        
        // 监听播放结束
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(playerDidFinishPlaying),
            name: .AVPlayerItemDidPlayToEndTime,
            object: playerItem
        )
        
        // 更新锁屏信息
        updateNowPlayingInfo()
        
        // 不自动播放
        print("🎵 [播放器管理] 准备完成，等待用户播放")
    }
    
    func play() {
        player?.play()
        postPlaybackStateChanged(isPlaying: true)
    }
    
    func pause() {
        player?.pause()
        postPlaybackStateChanged(isPlaying: false)
    }
    
    func togglePlayPause() {
        if isPlaying() {
            pause()
        } else {
            play()
        }
    }
    
    func seek(to time: CMTime, completion: ((Bool) -> Void)? = nil) {
        player?.seek(to: time) { finished in
            completion?(finished)
        }
    }
    
    func isPlaying() -> Bool {
        return player?.timeControlStatus == .playing
    }
    
    func currentTime() -> CMTime {
        return player?.currentTime() ?? .zero
    }
    
    func duration() -> CMTime {
        return player?.currentItem?.duration ?? .zero
    }
    
    // MARK: - KVO
    
    override func observeValue(forKeyPath keyPath: String?, of object: Any?, change: [NSKeyValueChangeKey : Any]?, context: UnsafeMutableRawPointer?) {
        if keyPath == "status" {
            if let statusNumber = change?[.newKey] as? NSNumber {
                let status = AVPlayerItem.Status(rawValue: statusNumber.intValue)
                if status == .readyToPlay {
                    print("✅ [播放器管理] 准备就绪")
                } else if status == .failed {
                    print("❌ [播放器管理] 播放失败: \(player?.currentItem?.error?.localizedDescription ?? "unknown")")
                }
            }
        }
    }
    
    // MARK: - Private Methods
    
    private func setupAudioSession() {
        do {
            let audioSession = AVAudioSession.sharedInstance()
            try audioSession.setCategory(.playback, mode: .default)
            try audioSession.setActive(true)
            print("✅ [播放器管理] 音频会话已设置")
        } catch {
            print("❌ [播放器管理] 音频会话设置失败: \(error.localizedDescription)")
        }
    }
    
    private func setupRemoteCommandCenter() {
        let commandCenter = MPRemoteCommandCenter.shared()
        
        commandCenter.playCommand.isEnabled = true
        commandCenter.playCommand.addTarget { [weak self] _ in
            self?.play()
            return .success
        }
        
        commandCenter.pauseCommand.isEnabled = true
        commandCenter.pauseCommand.addTarget { [weak self] _ in
            self?.pause()
            return .success
        }
        
        print("✅ [播放器管理] 远程控制已设置")
    }
    
    private func updateNowPlayingInfo() {
        var nowPlayingInfo = [String: Any]()
        
        if let title = currentTitle {
            nowPlayingInfo[MPMediaItemPropertyTitle] = title
        }
        
        if let artist = currentArtist {
            nowPlayingInfo[MPMediaItemPropertyArtist] = artist
        }
        
        if let artwork = currentArtwork {
            nowPlayingInfo[MPMediaItemPropertyArtwork] = MPMediaItemArtwork(boundsSize: artwork.size) { _ in
                return artwork
            }
        }
        
        let duration = CMTimeGetSeconds(self.duration())
        if !duration.isNaN && !duration.isInfinite {
            nowPlayingInfo[MPMediaItemPropertyPlaybackDuration] = duration
            nowPlayingInfo[MPNowPlayingInfoPropertyElapsedPlaybackTime] = CMTimeGetSeconds(currentTime())
        }
        
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nowPlayingInfo
        print("🎵 [播放器管理] 锁屏信息已更新: \(currentTitle ?? "Unknown")")
    }
    
    private func postPlaybackStateChanged(isPlaying: Bool) {
        NotificationCenter.default.post(
            name: MediaPlayerManager.playbackStateChangedNotification,
            object: nil,
            userInfo: ["isPlaying": isPlaying]
        )
    }
    
    private func cleanupCurrentItem() {
        if let observer = timeObserver {
            player?.removeTimeObserver(observer)
            timeObserver = nil
        }
        
        if let item = currentPlayerItem {
            item.removeObserver(self, forKeyPath: "status")
            NotificationCenter.default.removeObserver(self, name: .AVPlayerItemDidPlayToEndTime, object: item)
        }
        
        currentPlayerItem = nil
    }
    
    @objc private func playerDidFinishPlaying() {
        print("🎵 [播放器管理] 播放结束")
        postPlaybackStateChanged(isPlaying: false)
        NotificationCenter.default.post(name: MediaPlayerManager.playbackFinishedNotification, object: nil)
    }
    
    deinit {
        cleanupCurrentItem()
    }
}
