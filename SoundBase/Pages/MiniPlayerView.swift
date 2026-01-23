//
//  MiniPlayerView.swift
//  SoundBase
//
//  Created by samma on 2026/1/23.
//

import UIKit
import SnapKit
import AVFoundation

class MiniPlayerView: UIView {
    
    private let playerManager = MediaPlayerManager.shared
    
    // UI Components
    private lazy var thumbnailImageView: UIImageView = {
        let imageView = UIImageView()
        imageView.contentMode = .scaleAspectFill
        imageView.backgroundColor = .systemGray5
        imageView.layer.cornerRadius = 4
        imageView.clipsToBounds = true
        return imageView
    }()
    
    private lazy var titleLabel: UILabel = {
        let label = UILabel()
        label.font = .systemFont(ofSize: 14, weight: .medium)
        label.textColor = .label
        return label
    }()
    
    private lazy var artistLabel: UILabel = {
        let label = UILabel()
        label.font = .systemFont(ofSize: 12)
        label.textColor = .secondaryLabel
        return label
    }()
    
    private lazy var playButton: UIButton = {
        let button = UIButton(type: .system)
        let config = UIImage.SymbolConfiguration(pointSize: 20, weight: .semibold)
        button.setImage(UIImage(systemName: "play.fill", withConfiguration: config), for: .normal)
        button.tintColor = .label
        button.addTarget(self, action: #selector(playButtonTapped), for: .touchUpInside)
        return button
    }()
    
    private lazy var progressView: UIProgressView = {
        let progress = UIProgressView(progressViewStyle: .bar)
        progress.trackTintColor = .systemGray5
        progress.progressTintColor = .systemBlue
        return progress
    }()
    
    var onTap: (() -> Void)?
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        setupUI()
        setupNotifications()
        updateFromCurrentPlayer()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
    }
    
    private func setupUI() {
        backgroundColor = .systemBackground
        layer.shadowColor = UIColor.black.cgColor
        layer.shadowOffset = CGSize(width: 0, height: -2)
        layer.shadowRadius = 8
        layer.shadowOpacity = 0.1
        
        addSubview(progressView)
        addSubview(thumbnailImageView)
        addSubview(titleLabel)
        addSubview(artistLabel)
        addSubview(playButton)
        
        progressView.snp.makeConstraints { make in
            make.top.left.right.equalToSuperview()
            make.height.equalTo(2)
        }
        
        thumbnailImageView.snp.makeConstraints { make in
            make.left.equalToSuperview().offset(12)
            make.centerY.equalToSuperview()
            make.width.height.equalTo(48)
        }
        
        titleLabel.snp.makeConstraints { make in
            make.left.equalTo(thumbnailImageView.snp.right).offset(12)
            make.top.equalTo(thumbnailImageView).offset(4)
            make.right.equalTo(playButton.snp.left).offset(-12)
        }
        
        artistLabel.snp.makeConstraints { make in
            make.left.equalTo(titleLabel)
            make.bottom.equalTo(thumbnailImageView).offset(-4)
            make.right.equalTo(titleLabel)
        }
        
        playButton.snp.makeConstraints { make in
            make.right.equalToSuperview().offset(-12)
            make.centerY.equalToSuperview()
            make.width.height.equalTo(44)
        }
        
        // 添加点击手势
        let tapGesture = UITapGestureRecognizer(target: self, action: #selector(viewTapped))
        addGestureRecognizer(tapGesture)
    }
    
    private func setupNotifications() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(playbackStateChanged(_:)),
            name: MediaPlayerManager.playbackStateChangedNotification,
            object: nil
        )
        
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(timeUpdated(_:)),
            name: MediaPlayerManager.timeUpdateNotification,
            object: nil
        )
    }
    
    func updateInfo(title: String?, artist: String?, artwork: UIImage?) {
        titleLabel.text = title ?? "未播放"
        artistLabel.text = artist ?? ""
        thumbnailImageView.image = artwork ?? UIImage(systemName: "music.note")
    }
    
    private func updateFromCurrentPlayer() {
        updateInfo(
            title: playerManager.currentTitle,
            artist: playerManager.currentArtist,
            artwork: playerManager.currentArtwork
        )
        updatePlayButton(isPlaying: playerManager.isPlaying())
    }
    
    private func updatePlayButton(isPlaying: Bool) {
        let config = UIImage.SymbolConfiguration(pointSize: 20, weight: .semibold)
        if isPlaying {
            playButton.setImage(UIImage(systemName: "pause.fill", withConfiguration: config), for: .normal)
        } else {
            playButton.setImage(UIImage(systemName: "play.fill", withConfiguration: config), for: .normal)
        }
    }
    
    @objc private func playButtonTapped() {
        playerManager.togglePlayPause()
    }
    
    @objc private func viewTapped() {
        onTap?()
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
        
        let current = CMTimeGetSeconds(currentTime)
        let total = CMTimeGetSeconds(duration)
        
        if !total.isNaN && !total.isInfinite && total > 0 {
            progressView.progress = Float(current / total)
        }
    }
}
