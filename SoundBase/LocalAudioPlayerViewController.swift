//
//  LocalAudioPlayerViewController.swift
//  SoundBase
//
//  Created by samma on 2026/1/22.
//

import UIKit
import SnapKit
import AVFoundation

class LocalAudioPlayerViewController: UIViewController {
    
    private let audio: DownloadedAudio
    private let playerManager = MediaPlayerManager.shared
    
    private lazy var thumbnailImageView: UIImageView = {
        let imageView = UIImageView()
        imageView.contentMode = .scaleAspectFit
        imageView.backgroundColor = .systemGray6
        imageView.layer.cornerRadius = 12
        imageView.clipsToBounds = true
        return imageView
    }()
    
    private lazy var titleLabel: UILabel = {
        let label = UILabel()
        label.font = .systemFont(ofSize: 20, weight: .bold)
        label.numberOfLines = 0
        label.textAlignment = .center
        return label
    }()
    
    private lazy var channelLabel: UILabel = {
        let label = UILabel()
        label.font = .systemFont(ofSize: 16)
        label.textColor = .systemGray
        label.textAlignment = .center
        return label
    }()
    
    private lazy var progressSlider: UISlider = {
        let slider = UISlider()
        slider.addTarget(self, action: #selector(sliderValueChanged), for: .valueChanged)
        return slider
    }()
    
    private lazy var currentTimeLabel: UILabel = {
        let label = UILabel()
        label.font = .systemFont(ofSize: 12)
        label.text = "00:00"
        return label
    }()
    
    private lazy var durationLabel: UILabel = {
        let label = UILabel()
        label.font = .systemFont(ofSize: 12)
        label.text = "00:00"
        return label
    }()
    
    private lazy var playButton: UIButton = {
        let button = UIButton(type: .system)
        button.setImage(UIImage(systemName: "play.circle.fill"), for: .normal)
        button.tintColor = .systemBlue
        button.addTarget(self, action: #selector(playButtonTapped), for: .touchUpInside)
        return button
    }()
    
    init(audio: DownloadedAudio) {
        self.audio = audio
        super.init(nibName: nil, bundle: nil)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
        loadAudioInfo()
        setupPlayer()
        setupNotifications()
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        updatePlayButtonState()
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        // 不要暂停播放，支持后台继续播放
        // 不要清理player，使用全局单例
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
    }
    
    private func setupUI() {
        title = "播放"
        view.backgroundColor = .systemBackground
        
        view.addSubview(thumbnailImageView)
        view.addSubview(titleLabel)
        view.addSubview(channelLabel)
        view.addSubview(progressSlider)
        view.addSubview(currentTimeLabel)
        view.addSubview(durationLabel)
        view.addSubview(playButton)
        
        thumbnailImageView.snp.makeConstraints { make in
            make.top.equalTo(view.safeAreaLayoutGuide).offset(32)
            make.centerX.equalToSuperview()
            make.width.height.equalTo(280)
        }
        
        titleLabel.snp.makeConstraints { make in
            make.top.equalTo(thumbnailImageView.snp.bottom).offset(24)
            make.left.equalToSuperview().offset(24)
            make.right.equalToSuperview().offset(-24)
        }
        
        channelLabel.snp.makeConstraints { make in
            make.top.equalTo(titleLabel.snp.bottom).offset(8)
            make.left.right.equalTo(titleLabel)
        }
        
        currentTimeLabel.snp.makeConstraints { make in
            make.top.equalTo(channelLabel.snp.bottom).offset(48)
            make.left.equalToSuperview().offset(24)
        }
        
        durationLabel.snp.makeConstraints { make in
            make.top.equalTo(currentTimeLabel)
            make.right.equalToSuperview().offset(-24)
        }
        
        progressSlider.snp.makeConstraints { make in
            make.centerY.equalTo(currentTimeLabel)
            make.left.equalTo(currentTimeLabel.snp.right).offset(12)
            make.right.equalTo(durationLabel.snp.left).offset(-12)
        }
        
        playButton.snp.makeConstraints { make in
            make.top.equalTo(progressSlider.snp.bottom).offset(24)
            make.centerX.equalToSuperview()
            make.width.height.equalTo(80)
        }
    }
    
    private func setupAudioSession() {
        // 音频会话由MediaPlayerManager统一管理
    }
    
    private func setupNotifications() {
        // 监听播放状态变化
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(playbackStateChanged),
            name: MediaPlayerManager.playbackStateChangedNotification,
            object: nil
        )
        
        // 监听时间更新
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(timeUpdated),
            name: MediaPlayerManager.timeUpdateNotification,
            object: nil
        )
        
        // 监听播放结束
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(playbackFinished),
            name: MediaPlayerManager.playbackFinishedNotification,
            object: nil
        )
    }
    
    private func loadAudioInfo() {
        titleLabel.text = audio.title
        channelLabel.text = audio.channelTitle
        
        if let thumbnailURL = audio.thumbnailURL {
            loadImage(from: thumbnailURL)
        } else {
            thumbnailImageView.image = UIImage(systemName: "music.note")
        }
    }
    
    private func setupPlayer() {
        // 使用全局播放器管理器，只准备不自动播放
        playerManager.prepare(
            url: audio.fileURL,
            title: audio.title,
            artist: audio.channelTitle,
            artwork: thumbnailImageView.image
        )
    }
    
    @objc private func playbackStateChanged(_ notification: Notification) {
        guard let userInfo = notification.userInfo,
              let isPlaying = userInfo["isPlaying"] as? Bool else { return }
        updatePlayButton(isPlaying: isPlaying)
    }
    
    @objc private func timeUpdated(_ notification: Notification) {
        guard let userInfo = notification.userInfo,
              let currentTime = userInfo["currentTime"] as? CMTime,
              let duration = userInfo["duration"] as? CMTime else { return }
        updateProgress(currentTime: currentTime, duration: duration)
    }
    
    @objc private func playbackFinished() {
        updatePlayButton(isPlaying: false)
        playerManager.seek(to: .zero)
    }
    
    override func observeValue(forKeyPath keyPath: String?, of object: Any?, change: [NSKeyValueChangeKey : Any]?, context: UnsafeMutableRawPointer?) {
        // 不再需要KVO观察
    }
    
    private func updateProgress(currentTime: CMTime, duration: CMTime) {
        let current = CMTimeGetSeconds(currentTime)
        let total = CMTimeGetSeconds(duration)
        
        if !total.isNaN && !total.isInfinite && total > 0 {
            progressSlider.value = Float(current / total)
            currentTimeLabel.text = formatTime(current)
            durationLabel.text = formatTime(total)
        }
    }
    
    private func updatePlayButtonState() {
        let isPlaying = playerManager.isPlaying()
        updatePlayButton(isPlaying: isPlaying)
    }
    
    private func updatePlayButton(isPlaying: Bool) {
        if isPlaying {
            playButton.setImage(UIImage(systemName: "pause.circle.fill"), for: .normal)
        } else {
            playButton.setImage(UIImage(systemName: "play.circle.fill"), for: .normal)
        }
    }
    
    private func formatTime(_ seconds: Double) -> String {
        let mins = Int(seconds) / 60
        let secs = Int(seconds) % 60
        return String(format: "%02d:%02d", mins, secs)
    }
    
    private func loadImage(from url: URL) {
        URLSession.shared.dataTask(with: url) { [weak self] data, _, _ in
            guard let data = data, let image = UIImage(data: data) else { return }
            DispatchQueue.main.async {
                self?.thumbnailImageView.image = image
            }
        }.resume()
    }
    
    @objc private func playButtonTapped() {
        playerManager.togglePlayPause()
    }
    
    @objc private func sliderValueChanged() {
        let duration = CMTimeGetSeconds(playerManager.duration())
        let seconds = Double(progressSlider.value) * duration
        let time = CMTime(seconds: seconds, preferredTimescale: CMTimeScale(NSEC_PER_SEC))
        playerManager.seek(to: time)
    }
    
    @objc private func playerDidFinishPlaying() {
        // 由通知处理
    }
}
