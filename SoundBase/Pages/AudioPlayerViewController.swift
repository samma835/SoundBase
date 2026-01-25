//
//  AudioPlayerViewController.swift
//  SoundBase
//
//  Created by samma on 2026/1/23.
//  完全重写版本 - 移除自动解析，优化控制布局
//

import UIKit
import SnapKit
import YouTubeKit
import AVFoundation

class AudioPlayerViewController: UIViewController {
    
    private let video: VideoSearchResult
    private let playerManager = MediaPlayerManager.shared
    private let playlistManager = PlaylistManager.shared
    
    private var showingLyrics = false
    
    // MARK: - UI Components
    
    private lazy var albumArtView: UIImageView = {
        let imageView = UIImageView()
        imageView.contentMode = .scaleAspectFill
        imageView.backgroundColor = .systemGray6
        imageView.layer.cornerRadius = 12
        imageView.clipsToBounds = true
        imageView.isUserInteractionEnabled = true
        let tapGesture = UITapGestureRecognizer(target: self, action: #selector(albumArtTapped))
        imageView.addGestureRecognizer(tapGesture)
        return imageView
    }()
    
    private lazy var titleLabel: UILabel = {
        let label = UILabel()
        label.font = .systemFont(ofSize: 20, weight: .bold)
        label.numberOfLines = 2
        label.textAlignment = .center
        return label
    }()
    
    private lazy var artistLabel: UILabel = {
        let label = UILabel()
        label.font = .systemFont(ofSize: 16)
        label.textColor = .secondaryLabel
        label.textAlignment = .center
        return label
    }()
    
    private lazy var progressSlider: UISlider = {
        let slider = UISlider()
        slider.addTarget(self, action: #selector(sliderChanged), for: .valueChanged)
        return slider
    }()
    
    private lazy var currentTimeLabel: UILabel = {
        let label = UILabel()
        label.font = .monospacedDigitSystemFont(ofSize: 12, weight: .regular)
        label.text = "0:00"
        label.textColor = .secondaryLabel
        return label
    }()
    
    private lazy var durationLabel: UILabel = {
        let label = UILabel()
        label.font = .monospacedDigitSystemFont(ofSize: 12, weight: .regular)
        label.text = "0:00"
        label.textColor = .secondaryLabel
        return label
    }()
    
    // 控制按钮
    private lazy var repeatButton: UIButton = {
        let button = createControlButton(icon: "repeat", size: 20)
        button.addTarget(self, action: #selector(repeatButtonTapped), for: .touchUpInside)
        return button
    }()
    
    private lazy var shuffleButton: UIButton = {
        let button = createControlButton(icon: "shuffle", size: 20)
        button.addTarget(self, action: #selector(shuffleButtonTapped), for: .touchUpInside)
        return button
    }()
    
    private lazy var speedButton: UIButton = {
        let button = UIButton(type: .system)
        button.titleLabel?.font = .systemFont(ofSize: 14, weight: .semibold)
        button.setTitle("1.0x", for: .normal)
        button.tintColor = .label
        button.addTarget(self, action: #selector(speedButtonTapped), for: .touchUpInside)
        return button
    }()
    
    private lazy var downloadButton: UIButton = {
        let button = createControlButton(icon: "arrow.down.circle", size: 22)
        button.addTarget(self, action: #selector(downloadButtonTapped), for: .touchUpInside)
        return button
    }()
    
    private lazy var videoButton: UIButton = {
        let button = createControlButton(icon: "play.rectangle", size: 20)
        button.addTarget(self, action: #selector(videoButtonTapped), for: .touchUpInside)
        button.alpha = 0.3
        button.isEnabled = false
        return button
    }()
    
    private lazy var previousButton: UIButton = {
        let button = createControlButton(icon: "backward.fill", size: 28)
        button.addTarget(self, action: #selector(previousButtonTapped), for: .touchUpInside)
        return button
    }()
    
    private lazy var playPauseButton: UIButton = {
        let button = createControlButton(icon: "play.fill", size: 44)
        button.tintColor = .systemBlue
        button.addTarget(self, action: #selector(playPauseButtonTapped), for: .touchUpInside)
        return button
    }()
    
    private lazy var nextButton: UIButton = {
        let button = createControlButton(icon: "forward.fill", size: 28)
        button.addTarget(self, action: #selector(nextButtonTapped), for: .touchUpInside)
        return button
    }()
    
    init(video: VideoSearchResult) {
        self.video = video
        super.init(nibName: nil, bundle: nil)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
        loadVideoInfo()
        setupNotifications()
        updatePlayModeButtons()
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        GlobalPlayerContainer.shared.hide()
        updatePlayButtonState()
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        // 只在页面被pop/dismiss时显示全局播放器
        // isMovingFromParent表示页面正在从导航栈中移除
        // isBeingDismissed表示页面正在被dismiss
        if (isMovingFromParent || isBeingDismissed) && playerManager.isPlaying() {
            showGlobalPlayer()
        }
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
    }
    
    private func setupUI() {
        title = "正在播放"
        view.backgroundColor = .systemBackground
        
        view.addSubview(albumArtView)
        view.addSubview(titleLabel)
        view.addSubview(artistLabel)
        view.addSubview(currentTimeLabel)
        view.addSubview(progressSlider)
        view.addSubview(durationLabel)
        
        let topControlsStack = UIStackView(arrangedSubviews: [
            repeatButton, shuffleButton, speedButton, downloadButton, videoButton
        ])
        topControlsStack.axis = .horizontal
        topControlsStack.distribution = .equalSpacing
        topControlsStack.alignment = .center
        view.addSubview(topControlsStack)
        
        let playControlsStack = UIStackView(arrangedSubviews: [
            previousButton, playPauseButton, nextButton
        ])
        playControlsStack.axis = .horizontal
        playControlsStack.distribution = .equalSpacing
        playControlsStack.alignment = .center
        view.addSubview(playControlsStack)
        
        albumArtView.snp.makeConstraints { make in
            make.top.equalTo(view.safeAreaLayoutGuide).offset(20)
            make.centerX.equalToSuperview()
            make.width.height.equalTo(min(UIScreen.main.bounds.width - 80, 320))
        }
        
        titleLabel.snp.makeConstraints { make in
            make.top.equalTo(albumArtView.snp.bottom).offset(24)
            make.left.right.equalToSuperview().inset(32)
        }
        
        artistLabel.snp.makeConstraints { make in
            make.top.equalTo(titleLabel.snp.bottom).offset(8)
            make.left.right.equalTo(titleLabel)
        }
        
        currentTimeLabel.snp.makeConstraints { make in
            make.top.equalTo(artistLabel.snp.bottom).offset(32)
            make.left.equalToSuperview().offset(32)
        }
        
        durationLabel.snp.makeConstraints { make in
            make.top.equalTo(currentTimeLabel)
            make.right.equalToSuperview().offset(-32)
        }
        
        progressSlider.snp.makeConstraints { make in
            make.centerY.equalTo(currentTimeLabel)
            make.left.equalTo(currentTimeLabel.snp.right).offset(16)
            make.right.equalTo(durationLabel.snp.left).offset(-16)
        }
        
        topControlsStack.snp.makeConstraints { make in
            make.top.equalTo(progressSlider.snp.bottom).offset(28)
            make.left.right.equalToSuperview().inset(48)
            make.height.equalTo(44)
        }
        
        playControlsStack.snp.makeConstraints { make in
            make.top.equalTo(topControlsStack.snp.bottom).offset(20)
            make.centerX.equalToSuperview()
            make.width.equalTo(240)
            make.height.equalTo(60)
        }
    }
    
    private func createControlButton(icon: String, size: CGFloat) -> UIButton {
        let button = UIButton(type: .system)
        let config = UIImage.SymbolConfiguration(pointSize: size, weight: .medium)
        button.setImage(UIImage(systemName: icon, withConfiguration: config), for: .normal)
        button.tintColor = .label
        return button
    }
    
    private func loadVideoInfo() {
        titleLabel.text = video.title
        artistLabel.text = video.channelTitle
        
        if let thumbnailURL = video.thumbnailURL {
            loadImage(from: thumbnailURL)
        }
    }
    
    private func loadImage(from url: URL) {
        URLSession.shared.dataTask(with: url) { [weak self] data, _, _ in
            guard let data = data, let image = UIImage(data: data) else { return }
            DispatchQueue.main.async {
                self?.albumArtView.image = image
            }
        }.resume()
    }
    
    private func setupNotifications() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(playbackStateChanged),
            name: MediaPlayerManager.playbackStateChangedNotification,
            object: nil
        )
        
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(timeUpdated),
            name: MediaPlayerManager.timeUpdateNotification,
            object: nil
        )
        
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(playModeChanged),
            name: .playModeChanged,
            object: nil
        )
    }
    
    @objc private func albumArtTapped() {
        showingLyrics.toggle()
        print("�� [歌词] 切换歌词显示: \(showingLyrics)")
    }
    
    @objc private func repeatButtonTapped() {
        let mode = playlistManager.toggleRepeatMode()
        updateRepeatButton(mode: mode)
    }
    
    @objc private func shuffleButtonTapped() {
        let enabled = playlistManager.toggleShuffle()
        updateShuffleButton(enabled: enabled)
    }
    
    @objc private func speedButtonTapped() {
        let speeds: [Float] = [0.5, 0.8, 1.0, 1.25, 1.5, 2.0, 3.0]
        let alert = UIAlertController(title: "播放速度", message: nil, preferredStyle: .actionSheet)
        
        for speed in speeds {
            let action = UIAlertAction(title: "\(speed)x", style: .default) { [weak self] _ in
                self?.playerManager.setPlaybackRate(speed)
                self?.speedButton.setTitle("\(speed)x", for: .normal)
            }
            alert.addAction(action)
        }
        
        alert.addAction(UIAlertAction(title: "取消", style: .cancel))
        
        if let popover = alert.popoverPresentationController {
            popover.sourceView = speedButton
            popover.sourceRect = speedButton.bounds
        }
        
        present(alert, animated: true)
    }
    
    @objc private func downloadButtonTapped() {
        if AudioFileManager.shared.isDownloaded(videoId: video.videoId) != nil {
            showAlert(title: "提示", message: "该音频已下载")
            return
        }
        
        if AudioFileManager.shared.isDownloading(videoId: video.videoId) {
            showAlert(title: "提示", message: "正在下载中...")
            return
        }
        
        showAlert(title: "开始下载", message: "正在解析音频链接...")
        
        Task {
            do {
                let audioURL = try await extractAudioURL()
                await startDownload(audioURL: audioURL)
            } catch {
                await MainActor.run {
                    self.showAlert(title: "下载失败", message: error.localizedDescription)
                }
            }
        }
    }
    
    @objc private func videoButtonTapped() {
        showAlert(title: "提示", message: "查看视频功能即将推出")
    }
    
    @objc private func previousButtonTapped() {
        _ = playlistManager.playPrevious()
    }
    
    @objc private func playPauseButtonTapped() {
        playerManager.togglePlayPause()
    }
    
    @objc private func nextButtonTapped() {
        _ = playlistManager.playNext()
    }
    
    @objc private func sliderChanged() {
        let duration = CMTimeGetSeconds(playerManager.duration())
        let seconds = Double(progressSlider.value) * duration
        let time = CMTime(seconds: seconds, preferredTimescale: CMTimeScale(NSEC_PER_SEC))
        playerManager.seek(to: time)
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
    
    @objc private func playModeChanged() {
        updatePlayModeButtons()
    }
    
    private func updatePlayButtonState() {
        let isPlaying = playerManager.isPlaying()
        updatePlayButton(isPlaying: isPlaying)
    }
    
    private func updatePlayButton(isPlaying: Bool) {
        let config = UIImage.SymbolConfiguration(pointSize: 44, weight: .medium)
        let icon = isPlaying ? "pause.fill" : "play.fill"
        playPauseButton.setImage(UIImage(systemName: icon, withConfiguration: config), for: .normal)
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
    
    private func formatTime(_ seconds: Double) -> String {
        let mins = Int(seconds) / 60
        let secs = Int(seconds) % 60
        return String(format: "%d:%02d", mins, secs)
    }
    
    private func updatePlayModeButtons() {
        updateRepeatButton(mode: playlistManager.getRepeatMode())
        updateShuffleButton(enabled: playlistManager.getShuffleEnabled())
    }
    
    private func updateRepeatButton(mode: RepeatMode) {
        let config = UIImage.SymbolConfiguration(pointSize: 20, weight: .medium)
        switch mode {
        case .off:
            repeatButton.setImage(UIImage(systemName: "repeat", withConfiguration: config), for: .normal)
            repeatButton.tintColor = .secondaryLabel
        case .all:
            repeatButton.setImage(UIImage(systemName: "repeat", withConfiguration: config), for: .normal)
            repeatButton.tintColor = .systemBlue
        case .one:
            repeatButton.setImage(UIImage(systemName: "repeat.1", withConfiguration: config), for: .normal)
            repeatButton.tintColor = .systemBlue
        }
    }
    
    private func updateShuffleButton(enabled: Bool) {
        shuffleButton.tintColor = enabled ? .systemBlue : .secondaryLabel
    }
    
    private func showGlobalPlayer() {
        GlobalPlayerContainer.shared.show(
            title: video.title,
            artist: video.channelTitle,
            artwork: albumArtView.image,
            video: video
        )
    }
    
    private func extractAudioURL() async throws -> URL {
        let youtube = YouTube(videoID: video.videoId)
        let streams = try await youtube.streams
        
        let nativePlayableAudioStreams = streams
            .filterAudioOnly()
            .filter { $0.isNativelyPlayable }
        
        if let stream = nativePlayableAudioStreams.highestAudioBitrateStream() {
            return stream.url
        } else if let stream = streams.filterAudioOnly().highestAudioBitrateStream() {
            return stream.url
        } else {
            throw NSError(domain: "AudioExtraction", code: -1, userInfo: [NSLocalizedDescriptionKey: "未找到音频流"])
        }
    }
    
    private func startDownload(audioURL: URL) async {
        await MainActor.run {
            AudioFileManager.shared.saveAudio(
                videoId: video.videoId,
                title: video.title,
                channelTitle: video.channelTitle,
                thumbnailURL: video.thumbnailURL,
                sourceURL: audioURL
            ) { [weak self] result in
                DispatchQueue.main.async {
                    switch result {
                    case .success:
                        self?.showAlert(title: "✅ 下载完成", message: "音频已保存到离线列表")
                    case .failure(let error):
                        self?.showAlert(title: "下载失败", message: error.localizedDescription)
                    }
                }
            }
        }
    }
    
    private func showAlert(title: String, message: String) {
        let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "确定", style: .default))
        present(alert, animated: true)
    }
}
