//
//  AudioPlayerViewController.swift
//  SoundBase
//
//  Created by samma on 2026/1/22.
//

import UIKit
import SnapKit
import YouTubeKit
import AVFoundation
import MediaPlayer

class AudioPlayerViewController: UIViewController {
    
    private let video: VideoSearchResult
    private let playerManager = MediaPlayerManager.shared
    private var audioURL: URL?
    private var downloadedFileURL: URL?
    private var isDownloading = false
    private var thumbnailImage: UIImage?
    
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
        let config = UIImage.SymbolConfiguration(pointSize: 24, weight: .semibold)
        button.setImage(UIImage(systemName: "play.fill", withConfiguration: config), for: .normal)
        button.setTitle("  播放", for: .normal)
        button.tintColor = .white
        button.backgroundColor = .systemBlue
        button.layer.cornerRadius = 27
        button.titleLabel?.font = .systemFont(ofSize: 18, weight: .semibold)
        button.addTarget(self, action: #selector(playButtonTapped), for: .touchUpInside)
        return button
    }()
    
    private lazy var downloadButton: UIButton = {
        let button = UIButton(type: .system)
        let config = UIImage.SymbolConfiguration(pointSize: 20, weight: .semibold)
        button.setImage(UIImage(systemName: "arrow.down.circle.fill", withConfiguration: config), for: .normal)
        button.setTitle("  下载", for: .normal)
        button.tintColor = .systemBlue
        button.backgroundColor = .systemGray6
        button.layer.cornerRadius = 27
        button.titleLabel?.font = .systemFont(ofSize: 18, weight: .semibold)
        button.addTarget(self, action: #selector(downloadButtonTapped), for: .touchUpInside)
        return button
    }()
    
    private lazy var downloadProgressLayer: CAShapeLayer = {
        let layer = CAShapeLayer()
        layer.fillColor = UIColor.clear.cgColor
        layer.strokeColor = UIColor.systemBlue.cgColor
        layer.lineWidth = 4
        layer.lineCap = .round
        layer.strokeEnd = 0
        layer.isHidden = true
        return layer
    }()
    
    private lazy var downloadBackgroundLayer: CAShapeLayer = {
        let layer = CAShapeLayer()
        layer.fillColor = UIColor.clear.cgColor
        layer.strokeColor = UIColor.systemGray5.cgColor
        layer.lineWidth = 4
        layer.lineCap = .round
        layer.isHidden = true
        return layer
    }()
    
    private lazy var playLocalButton: UIButton = {
        let button = UIButton(type: .system)
        button.setTitle("播放本地文件", for: .normal)
        button.addTarget(self, action: #selector(playLocalButtonTapped), for: .touchUpInside)
        button.isHidden = true
        return button
    }()
    
    private lazy var statusLabel: UILabel = {
        let label = UILabel()
        label.font = .systemFont(ofSize: 14)
        label.textColor = .systemGray
        label.textAlignment = .center
        label.text = "正在解析音频..."
        return label
    }()
    
    private lazy var activityIndicator: UIActivityIndicatorView = {
        let indicator = UIActivityIndicatorView(style: .large)
        indicator.hidesWhenStopped = true
        return indicator
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
        checkDownloadStatus()
        setupNotifications()
        extractAudio()
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        checkDownloadStatus()
        updatePlayButtonState()
    }
    
    // 更新播放按钮状态
    private func updatePlayButtonState() {
        let isPlaying = playerManager.isPlaying()
        updatePlayButton(isPlaying: isPlaying)
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        // 不要暂停播放，支持后台继续播放
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
    }
    
    private func setupUI() {
        title = "音频播放"
        view.backgroundColor = .systemBackground
        
        view.addSubview(thumbnailImageView)
        view.addSubview(titleLabel)
        view.addSubview(channelLabel)
        view.addSubview(statusLabel)
        view.addSubview(progressSlider)
        view.addSubview(currentTimeLabel)
        view.addSubview(durationLabel)
        view.addSubview(playButton)
        view.addSubview(downloadButton)
        view.addSubview(playLocalButton)
        view.addSubview(activityIndicator)
        
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
        
        statusLabel.snp.makeConstraints { make in
            make.top.equalTo(channelLabel.snp.bottom).offset(16)
            make.left.right.equalTo(titleLabel)
        }
        
        currentTimeLabel.snp.makeConstraints { make in
            make.top.equalTo(statusLabel.snp.bottom).offset(32)
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
            make.top.equalTo(progressSlider.snp.bottom).offset(32)
            make.right.equalTo(view.snp.centerX).offset(-12)
            make.width.equalTo(140)
            make.height.equalTo(54)
        }
        
        downloadButton.snp.makeConstraints { make in
            make.top.equalTo(playButton)
            make.left.equalTo(view.snp.centerX).offset(12)
            make.width.equalTo(140)
            make.height.equalTo(54)
        }
        
        playLocalButton.snp.makeConstraints { make in
            make.top.equalTo(playButton.snp.bottom).offset(16)
            make.centerX.equalToSuperview()
            make.width.equalTo(200)
            make.height.equalTo(50)
        }
        
        activityIndicator.snp.makeConstraints { make in
            make.center.equalTo(playButton)
        }
        
        // 添加进度圈到下载按钮
        downloadButton.layer.insertSublayer(downloadBackgroundLayer, at: 0)
        downloadButton.layer.insertSublayer(downloadProgressLayer, at: 1)
        
        playButton.isEnabled = false
        downloadButton.isEnabled = false
    }
    
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        // 设置进度路径 - 沿着按钮边框（圆角矩形）
        let buttonBounds = downloadButton.bounds
        let cornerRadius: CGFloat = downloadButton.layer.cornerRadius > 0 ? downloadButton.layer.cornerRadius : 27 // 按钮高度的一半
        let inset: CGFloat = 2 // 距离边框的距离
        let rect = buttonBounds.insetBy(dx: inset, dy: inset)
        
        let path = UIBezierPath(roundedRect: rect, cornerRadius: cornerRadius - inset)
        
        downloadBackgroundLayer.path = path.cgPath
        downloadProgressLayer.path = path.cgPath
    }
    
    private func loadVideoInfo() {
        titleLabel.text = video.title
        channelLabel.text = video.channelTitle
        
        if let thumbnailURL = video.thumbnailURL {
            loadImage(from: thumbnailURL)
        }
    }
    
    private func extractAudio() {
        // 先检查是否有本地文件
        if let downloadedAudio = AudioFileManager.shared.isDownloaded(videoId: video.videoId) {
            print("📱 [本地播放] 找到本地文件: \(downloadedAudio.title)")
            statusLabel.text = "播放本地音频"
            audioURL = downloadedAudio.fileURL
            downloadedFileURL = downloadedAudio.fileURL
            playButton.isEnabled = true
            downloadButton.isEnabled = false
            downloadButton.setTitle("  已下载", for: .normal)
            downloadButton.backgroundColor = .systemGreen.withAlphaComponent(0.2)
            downloadButton.tintColor = .systemGreen
            return
        }
        
        // 没有本地文件，继续YouTube提取流程
        activityIndicator.startAnimating()
        statusLabel.text = "正在解析音频..."
        
        Task {
            do {
                let youtube = YouTube(videoID: video.videoId)
                let streams = try await youtube.streams
                
                print("Total streams: \(streams.count)")
                
                // 优先选择可原生播放的音频流
                var audioStream: YouTubeKit.Stream?
                
                // 1. 尝试获取可原生播放的音频流
                let nativePlayableAudioStreams = streams
                    .filterAudioOnly()
                    .filter { $0.isNativelyPlayable }
                
                if let stream = nativePlayableAudioStreams.highestAudioBitrateStream() {
                    audioStream = stream
                    print("Found natively playable audio stream: itag=\(stream.itag)")
                } else {
                    // 2. 如果没有，选择任意音频流（但可能无法直接播放）
                    audioStream = streams.filterAudioOnly().highestAudioBitrateStream()
                    print("Using non-native audio stream, may not play directly")
                }
                
                guard let selectedStream = audioStream else {
                    throw NSError(domain: "AudioExtraction", code: -1, userInfo: [NSLocalizedDescriptionKey: "未找到音频流"])
                }
                
                print("Selected audio stream: itag=\(selectedStream.itag), fileExtension=\(selectedStream.fileExtension), url=\(selectedStream.url)")
                
                await MainActor.run {
                    self.audioURL = selectedStream.url
                    if selectedStream.isNativelyPlayable {
                        self.statusLabel.text = "音频已就绪 - 点击播放"
                        self.playButton.isEnabled = true
                    } else {
                        self.statusLabel.text = "音频格式不支持直播 - 请下载后播放"
                        self.playButton.isEnabled = false
                    }
                    self.downloadButton.isEnabled = true
                    self.activityIndicator.stopAnimating()
                    self.checkDownloadStatus()
                }
            } catch {
                print("Extract audio error: \(error)")
                await MainActor.run {
                    self.statusLabel.text = "解析失败: \(error.localizedDescription)"
                    self.activityIndicator.stopAnimating()
                }
            }
        }
    }
    
    private func setupPlayer() {
        guard let audioURL = audioURL else { return }
        
        print("🎵 [播放器] 准备音频: \(video.title)")
        
        // 使用 MediaPlayerManager 准备播放器
        playerManager.prepare(
            url: audioURL,
            title: video.title,
            artist: video.channelTitle,
            artwork: thumbnailImage
        )
        
        statusLabel.text = "音频已就绪 - 点击播放"
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
        return String(format: "%02d:%02d", mins, secs)
    }
    
    private func loadImage(from url: URL) {
        URLSession.shared.dataTask(with: url) { [weak self] data, _, _ in
            guard let data = data, let image = UIImage(data: data) else { return }
            DispatchQueue.main.async {
                self?.thumbnailImageView.image = image
                self?.thumbnailImage = image
            }
        }.resume()
    }
    
    @objc private func playButtonTapped() {
        // 如果没有准备好播放器，先设置
        if audioURL != nil && !isPlayingCurrentAudio() {
            setupPlayer()
            // 等待一小段时间让播放器准备好
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
                self?.playerManager.play()
            }
        } else {
            // 切换播放/暂停
            playerManager.togglePlayPause()
        }
    }
    
    // 检查当前播放的是否是这个视频的音频
    private func isPlayingCurrentAudio() -> Bool {
        guard let player = playerManager.player,
              let currentItem = player.currentItem,
              let currentURL = (currentItem.asset as? AVURLAsset)?.url,
              let myAudioURL = audioURL else {
            return false
        }
        return currentURL == myAudioURL
    }
    
    private func updatePlayButton(isPlaying: Bool) {
        let config = UIImage.SymbolConfiguration(pointSize: 24, weight: .semibold)
        if isPlaying {
            playButton.setImage(UIImage(systemName: "pause.fill", withConfiguration: config), for: .normal)
            playButton.setTitle("  暂停", for: .normal)
        } else {
            playButton.setImage(UIImage(systemName: "play.fill", withConfiguration: config), for: .normal)
            playButton.setTitle("  播放", for: .normal)
        }
    }
    
    @objc private func sliderValueChanged() {
        let duration = CMTimeGetSeconds(playerManager.duration())
        let seconds = Double(progressSlider.value) * duration
        let time = CMTime(seconds: seconds, preferredTimescale: CMTimeScale(NSEC_PER_SEC))
        playerManager.seek(to: time)
    }
    
    @objc private func playerDidFinishPlaying() {
        updatePlayButton(isPlaying: false)
        playerManager.seek(to: .zero)
    }
    
    private func setupNotifications() {
        // 监听播放状态变化
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(playbackStateChanged(_:)),
            name: MediaPlayerManager.playbackStateChangedNotification,
            object: nil
        )
        
        // 监听时间更新
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(timeUpdated(_:)),
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
        
        // 监听下载进度
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(downloadProgressUpdated(_:)),
            name: .downloadProgressUpdated,
            object: nil
        )
        
        // 监听下载完成
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(downloadCompleted(_:)),
            name: .downloadCompleted,
            object: nil
        )
        
        // 监听下载失败
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(downloadFailed(_:)),
            name: .downloadFailed,
            object: nil
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
    
    private func checkDownloadStatus() {
        // 检查是否已下载
        if let downloadedAudio = AudioFileManager.shared.isDownloaded(videoId: video.videoId) {
            downloadedFileURL = downloadedAudio.fileURL
            playLocalButton.isHidden = false
            updateDownloadButtonState(downloaded: true)
            print("✅ [下载状态] 已下载")
        } else if AudioFileManager.shared.isDownloading(videoId: video.videoId) {
            // 从全局状态检查是否正在下载
            isDownloading = true
            updateDownloadButtonState(downloading: true)
            print("⏳ [下载状态] 下载中")
        } else {
            isDownloading = false
            updateDownloadButtonState(downloaded: false)
            print("📥 [下载状态] 未下载")
        }
    }
    
    private func updateDownloadButtonState(downloaded: Bool = false, downloading: Bool = false) {
        let config = UIImage.SymbolConfiguration(pointSize: 20, weight: .semibold)
        
        if downloaded {
            downloadButton.setImage(UIImage(systemName: "checkmark.circle.fill", withConfiguration: config), for: .normal)
            downloadButton.setTitle("  已下载", for: .normal)
            downloadButton.tintColor = .systemGreen
            downloadButton.isEnabled = false
            downloadBackgroundLayer.isHidden = true
            downloadProgressLayer.isHidden = true
        } else if downloading {
            downloadButton.setImage(UIImage(systemName: "arrow.down.circle.fill", withConfiguration: config), for: .normal)
            downloadButton.setTitle("  下载中", for: .normal)
            downloadButton.tintColor = .systemBlue
            downloadButton.isEnabled = false
            downloadBackgroundLayer.isHidden = false
            downloadProgressLayer.isHidden = false
        } else {
            downloadButton.setImage(UIImage(systemName: "arrow.down.circle.fill", withConfiguration: config), for: .normal)
            downloadButton.setTitle("  下载", for: .normal)
            downloadButton.tintColor = .systemBlue
            downloadButton.isEnabled = true
            downloadBackgroundLayer.isHidden = true
            downloadProgressLayer.isHidden = true
            downloadProgressLayer.strokeEnd = 0
        }
    }
    
    @objc private func downloadProgressUpdated(_ notification: Notification) {
        guard let userInfo = notification.userInfo,
              let videoId = userInfo["videoId"] as? String,
              videoId == video.videoId,
              let progress = userInfo["progress"] as? Double else {
            return
        }
        
        DispatchQueue.main.async {
            self.downloadProgressLayer.strokeEnd = CGFloat(progress)
        }
    }
    
    @objc private func downloadCompleted(_ notification: Notification) {
        guard let audio = notification.object as? DownloadedAudio,
              audio.videoId == video.videoId else {
            return
        }
        
        DispatchQueue.main.async {
            self.isDownloading = false
            self.downloadedFileURL = audio.fileURL
            self.playLocalButton.isHidden = false
            self.updateDownloadButtonState(downloaded: true)
            
            // 显示成功提示
            let successAlert = UIAlertController(title: "✅ 下载完成", message: "音频已保存到离线列表", preferredStyle: .alert)
            successAlert.addAction(UIAlertAction(title: "确定", style: .default))
            self.present(successAlert, animated: true)
        }
    }
    
    @objc private func downloadFailed(_ notification: Notification) {
        DispatchQueue.main.async {
            self.isDownloading = false
            self.updateDownloadButtonState(downloaded: false)
            
            if let error = notification.object as? Error {
                let errorAlert = UIAlertController(title: "下载失败", message: error.localizedDescription, preferredStyle: .alert)
                errorAlert.addAction(UIAlertAction(title: "确定", style: .default))
                self.present(errorAlert, animated: true)
            }
        }
    }
    
    @objc private func downloadButtonTapped() {
        guard let audioURL = audioURL else {
            print("Audio URL is nil")
            return
        }
        
        print("Starting download from: \(audioURL)")
        
        // 显示下载开始提示
        let hud = UIAlertController(title: "开始下载", message: "下载将在后台进行\n可以退出此页面", preferredStyle: .alert)
        present(hud, animated: true)
        
        // 1秒后自动关闭提示
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            hud.dismiss(animated: true)
        }
        
        // 更新状态
        isDownloading = true
        updateDownloadButtonState(downloading: true)
        
        // 开始后台下载
        AudioFileManager.shared.saveAudio(
            videoId: video.videoId,
            title: video.title,
            channelTitle: video.channelTitle,
            thumbnailURL: video.thumbnailURL,
            sourceURL: audioURL
        ) { [weak self] result in
            guard let self = self else { return }
            
            // 注意：成功和失败都通过通知处理，这里不需要额外处理
            if case .failure(let error) = result {
                print("Download error: \(error.localizedDescription)")
            }
        }
    }
    
    @objc private func playLocalButtonTapped() {
        guard let fileURL = downloadedFileURL else { return }
        
        print("📱 [本地播放] 播放本地文件: \(fileURL.path)")
        
        // 使用 MediaPlayerManager 准备播放器
        playerManager.prepare(
            url: fileURL,
            title: video.title,
            artist: video.channelTitle,
            artwork: thumbnailImage
        )
        
        playButton.isEnabled = true
        statusLabel.text = "本地文件已就绪 - 点击播放"
    }
    
    private func showAlert(title: String, message: String) {
        let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "确定", style: .default))
        present(alert, animated: true)
    }
}
