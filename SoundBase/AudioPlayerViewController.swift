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

class AudioPlayerViewController: UIViewController {
    
    private let video: VideoSearchResult
    private var audioURL: URL?
    private var player: AVPlayer?
    private var timeObserver: Any?
    private var downloadedFileURL: URL?
    
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
        setupAudioSession()
        loadVideoInfo()
        extractAudio()
    }
    
    private func setupAudioSession() {
        do {
            let audioSession = AVAudioSession.sharedInstance()
            try audioSession.setCategory(.playback, mode: .default)
            try audioSession.setActive(true)
        } catch {
            print("Failed to set up audio session: \(error.localizedDescription)")
        }
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        player?.pause()
    }
    
    deinit {
        if let observer = timeObserver {
            player?.removeTimeObserver(observer)
        }
        player?.currentItem?.removeObserver(self, forKeyPath: "status")
        player?.currentItem?.removeObserver(self, forKeyPath: "playbackBufferEmpty")
        player?.currentItem?.removeObserver(self, forKeyPath: "playbackLikelyToKeepUp")
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
        
        playButton.isEnabled = false
        downloadButton.isEnabled = false
    }
    
    private func loadVideoInfo() {
        titleLabel.text = video.title
        channelLabel.text = video.channelTitle
        
        if let thumbnailURL = video.thumbnailURL {
            loadImage(from: thumbnailURL)
        }
    }
    
    private func extractAudio() {
        activityIndicator.startAnimating()
        
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
                        self.statusLabel.text = "音频已就绪 - 可播放/下载"
                        self.playButton.isEnabled = true
                        self.setupPlayer()
                    } else {
                        self.statusLabel.text = "音频格式不支持直播 - 请下载后播放"
                        self.playButton.isEnabled = false
                    }
                    self.downloadButton.isEnabled = true
                    self.activityIndicator.stopAnimating()
                    self.checkLocalFile()
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
    
    private func checkLocalFile() {
        if let downloadedAudio = AudioFileManager.shared.isDownloaded(videoId: video.videoId) {
            downloadedFileURL = downloadedAudio.fileURL
            playLocalButton.isHidden = false
            statusLabel.text = "本地文件已存在 - 可播放"
        }
    }
    
    private func setupPlayer() {
        guard let audioURL = audioURL else { return }
        
        print("Setting up player with URL: \(audioURL)")
        
        // 创建 AVAsset 并设置 HTTP headers
        let headers = [
            "User-Agent": "Mozilla/5.0 (iPhone; CPU iPhone OS 15_0 like Mac OS X) AppleWebKit/605.1.15",
            "Accept": "*/*",
            "Accept-Language": "en-US,en;q=0.9"
        ]
        
        let asset = AVURLAsset(url: audioURL, options: ["AVURLAssetHTTPHeaderFieldsKey": headers])
        let playerItem = AVPlayerItem(asset: asset)
        
        player = AVPlayer(playerItem: playerItem)
        
        // 检查播放器状态
        playerItem.addObserver(self, forKeyPath: "status", options: [.new, .initial], context: nil)
        
        // 监听缓冲状态
        playerItem.addObserver(self, forKeyPath: "playbackBufferEmpty", options: .new, context: nil)
        playerItem.addObserver(self, forKeyPath: "playbackLikelyToKeepUp", options: .new, context: nil)
        
        // 使用1秒间隔更新进度，避免时长计算错误
        timeObserver = player?.addPeriodicTimeObserver(forInterval: CMTime(seconds: 1.0, preferredTimescale: CMTimeScale(NSEC_PER_SEC)), queue: .main) { [weak self] time in
            self?.updateProgress()
        }
        
        NotificationCenter.default.addObserver(self, selector: #selector(playerDidFinishPlaying), name: .AVPlayerItemDidPlayToEndTime, object: playerItem)
    }
    
    override func observeValue(forKeyPath keyPath: String?, of object: Any?, change: [NSKeyValueChangeKey : Any]?, context: UnsafeMutableRawPointer?) {
        if keyPath == "status" {
            if let statusNumber = change?[.newKey] as? NSNumber {
                let status = AVPlayerItem.Status(rawValue: statusNumber.intValue)
                switch status {
                case .readyToPlay:
                    print("Player ready to play")
                    DispatchQueue.main.async {
                        self.statusLabel.text = "音频已就绪 - 点击播放"
                    }
                case .failed:
                    let error = player?.currentItem?.error
                    print("Player failed: \(error?.localizedDescription ?? "unknown error")")
                    if let nsError = error as NSError? {
                        print("Error domain: \(nsError.domain)")
                        print("Error code: \(nsError.code)")
                        print("Error userInfo: \(nsError.userInfo)")
                    }
                    DispatchQueue.main.async {
                        self.statusLabel.text = "播放器错误，请尝试下载"
                        self.showAlert(title: "播放失败", message: "音频流可能需要下载后播放")
                    }
                case .unknown:
                    print("Player status unknown")
                default:
                    break
                }
            }
        } else if keyPath == "playbackBufferEmpty" {
            print("Buffer empty")
        } else if keyPath == "playbackLikelyToKeepUp" {
            print("Buffer ready to keep up")
        }
    }
    
    private func updateProgress() {
        guard let player = player,
              let currentItem = player.currentItem else { return }
        
        let currentTime = CMTimeGetSeconds(player.currentTime())
        let duration = CMTimeGetSeconds(currentItem.duration)
        
        // 添加日志查看实际时长
        if duration > 0 && !duration.isNaN && !duration.isInfinite {
            // 只在第一次或时长变化时打印
            var lastLoggedDuration: Double = 0
            if abs(lastLoggedDuration - duration) > 1 {
                print("Duration: \(duration) seconds (\(formatTime(duration)))")
                lastLoggedDuration = duration
            }
            
            progressSlider.value = Float(currentTime / duration)
            currentTimeLabel.text = formatTime(currentTime)
            durationLabel.text = formatTime(duration)
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
        guard let player = player else {
            print("Player is nil")
            return
        }
        
        let config = UIImage.SymbolConfiguration(pointSize: 24, weight: .semibold)
        if player.timeControlStatus == .playing {
            player.pause()
            playButton.setImage(UIImage(systemName: "play.fill", withConfiguration: config), for: .normal)
            playButton.setTitle("  播放", for: .normal)
            print("Paused")
        } else {
            player.play()
            playButton.setImage(UIImage(systemName: "pause.fill", withConfiguration: config), for: .normal)
            playButton.setTitle("  暂停", for: .normal)
            print("Playing")
        }
    }
    
    @objc private func sliderValueChanged() {
        guard let player = player,
              let duration = player.currentItem?.duration else { return }
        
        let seconds = Double(progressSlider.value) * CMTimeGetSeconds(duration)
        let time = CMTime(seconds: seconds, preferredTimescale: CMTimeScale(NSEC_PER_SEC))
        player.seek(to: time)
    }
    
    @objc private func playerDidFinishPlaying() {
        let config = UIImage.SymbolConfiguration(pointSize: 24, weight: .semibold)
        playButton.setImage(UIImage(systemName: "play.fill", withConfiguration: config), for: .normal)
        playButton.setTitle("  播放", for: .normal)
        player?.seek(to: .zero)
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
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            hud.dismiss(animated: true)
        }
        
        // 更新按钮状态
        downloadButton.isEnabled = false
        downloadButton.setTitle("  下载中...", for: .normal)
        
        // 开始后台下载
        AudioFileManager.shared.saveAudio(
            videoId: video.videoId,
            title: video.title,
            channelTitle: video.channelTitle,
            thumbnailURL: video.thumbnailURL,
            sourceURL: audioURL
        ) { [weak self] result in
            guard let self = self else { return }
            
            DispatchQueue.main.async {
                self.downloadButton.isEnabled = true
                self.downloadButton.setTitle("  下载", for: .normal)
                
                switch result {
                case .success(let audio):
                    print("Download success: \(audio.fileURL.path)")
                    self.downloadedFileURL = audio.fileURL
                    self.playLocalButton.isHidden = false
                    
                    // 显示成功提示
                    let successAlert = UIAlertController(title: "✅ 下载完成", message: "音频已保存到离线列表", preferredStyle: .alert)
                    successAlert.addAction(UIAlertAction(title: "确定", style: .default))
                    self.present(successAlert, animated: true)
                    
                case .failure(let error):
                    print("Download error: \(error.localizedDescription)")
                    
                    // 显示失败提示
                    let errorAlert = UIAlertController(title: "下载失败", message: error.localizedDescription, preferredStyle: .alert)
                    errorAlert.addAction(UIAlertAction(title: "确定", style: .default))
                    self.present(errorAlert, animated: true)
                }
            }
        }
    }
    
    @objc private func playLocalButtonTapped() {
        guard let fileURL = downloadedFileURL else { return }
        
        print("Playing local file: \(fileURL.path)")
        
        // 停止当前播放器
        player?.pause()
        if let observer = timeObserver {
            player?.removeTimeObserver(observer)
            timeObserver = nil
        }
        player?.currentItem?.removeObserver(self, forKeyPath: "status")
        player?.currentItem?.removeObserver(self, forKeyPath: "playbackBufferEmpty")
        player?.currentItem?.removeObserver(self, forKeyPath: "playbackLikelyToKeepUp")
        
        // 创建本地文件播放器
        let playerItem = AVPlayerItem(url: fileURL)
        player = AVPlayer(playerItem: playerItem)
        
        playerItem.addObserver(self, forKeyPath: "status", options: [.new, .initial], context: nil)
        
        timeObserver = player?.addPeriodicTimeObserver(forInterval: CMTime(seconds: 1.0, preferredTimescale: CMTimeScale(NSEC_PER_SEC)), queue: .main) { [weak self] time in
            self?.updateProgress()
        }
        
        NotificationCenter.default.addObserver(self, selector: #selector(playerDidFinishPlaying), name: .AVPlayerItemDidPlayToEndTime, object: playerItem)
        
        // 自动开始播放
        player?.play()
        let config = UIImage.SymbolConfiguration(pointSize: 24, weight: .semibold)
        playButton.setImage(UIImage(systemName: "pause.fill", withConfiguration: config), for: .normal)
        playButton.setTitle("  暂停", for: .normal)
        playButton.isEnabled = true
        statusLabel.text = "正在播放本地文件"
    }
    
    private func showAlert(title: String, message: String) {
        let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "确定", style: .default))
        present(alert, animated: true)
    }
}
