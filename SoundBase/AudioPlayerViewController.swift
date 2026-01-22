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
    
    private lazy var downloadButton: UIButton = {
        let button = UIButton(type: .system)
        button.setTitle("下载音频", for: .normal)
        button.addTarget(self, action: #selector(downloadButtonTapped), for: .touchUpInside)
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
            make.top.equalTo(progressSlider.snp.bottom).offset(24)
            make.centerX.equalToSuperview()
            make.width.height.equalTo(80)
        }
        
        downloadButton.snp.makeConstraints { make in
            make.top.equalTo(playButton.snp.bottom).offset(24)
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
                
                guard let audioStream = streams.filterAudioOnly().highestAudioBitrateStream() else {
                    throw NSError(domain: "AudioExtraction", code: -1, userInfo: [NSLocalizedDescriptionKey: "未找到音频流"])
                }
                
                await MainActor.run {
                    self.audioURL = audioStream.url
                    self.statusLabel.text = "音频已就绪"
                    self.playButton.isEnabled = true
                    self.downloadButton.isEnabled = true
                    self.activityIndicator.stopAnimating()
                    self.setupPlayer()
                }
            } catch {
                await MainActor.run {
                    self.statusLabel.text = "解析失败: \(error.localizedDescription)"
                    self.activityIndicator.stopAnimating()
                }
            }
        }
    }
    
    private func setupPlayer() {
        guard let audioURL = audioURL else { return }
        
        print("Setting up player with URL: \(audioURL)")
        
        player = AVPlayer(url: audioURL)
        
        // 检查播放器状态
        player?.currentItem?.addObserver(self, forKeyPath: "status", options: [.new, .initial], context: nil)
        
        timeObserver = player?.addPeriodicTimeObserver(forInterval: CMTime(seconds: 0.5, preferredTimescale: CMTimeScale(NSEC_PER_SEC)), queue: .main) { [weak self] time in
            self?.updateProgress()
        }
        
        NotificationCenter.default.addObserver(self, selector: #selector(playerDidFinishPlaying), name: .AVPlayerItemDidPlayToEndTime, object: player?.currentItem)
    }
    
    override func observeValue(forKeyPath keyPath: String?, of object: Any?, change: [NSKeyValueChangeKey : Any]?, context: UnsafeMutableRawPointer?) {
        if keyPath == "status" {
            if let statusNumber = change?[.newKey] as? NSNumber {
                let status = AVPlayerItem.Status(rawValue: statusNumber.intValue)
                switch status {
                case .readyToPlay:
                    print("Player ready to play")
                case .failed:
                    print("Player failed: \(player?.currentItem?.error?.localizedDescription ?? "unknown error")")
                    DispatchQueue.main.async {
                        self.statusLabel.text = "播放器错误: \(self.player?.currentItem?.error?.localizedDescription ?? "未知错误")"
                    }
                case .unknown:
                    print("Player status unknown")
                default:
                    break
                }
            }
        }
    }
    
    private func updateProgress() {
        guard let player = player else { return }
        
        let currentTime = CMTimeGetSeconds(player.currentTime())
        let duration = CMTimeGetSeconds(player.currentItem?.duration ?? .zero)
        
        if !duration.isNaN && !duration.isInfinite {
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
        
        if player.timeControlStatus == .playing {
            player.pause()
            playButton.setImage(UIImage(systemName: "play.circle.fill"), for: .normal)
            print("Paused")
        } else {
            player.play()
            playButton.setImage(UIImage(systemName: "pause.circle.fill"), for: .normal)
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
        playButton.setImage(UIImage(systemName: "play.circle.fill"), for: .normal)
        player?.seek(to: .zero)
    }
    
    @objc private func downloadButtonTapped() {
        guard let audioURL = audioURL else {
            print("Audio URL is nil")
            return
        }
        
        print("Starting download from: \(audioURL)")
        
        let alert = UIAlertController(title: "下载音频", message: "正在下载...", preferredStyle: .alert)
        present(alert, animated: true)
        
        let fileName = "\(video.title.replacingOccurrences(of: "/", with: "-")).m4a"
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let destinationURL = documentsPath.appendingPathComponent(fileName)
        
        print("Destination: \(destinationURL.path)")
        
        URLSession.shared.downloadTask(with: audioURL) { [weak self] tempURL, response, error in
            DispatchQueue.main.async {
                alert.dismiss(animated: true) {
                    if let error = error {
                        print("Download error: \(error.localizedDescription)")
                        self?.showAlert(title: "下载失败", message: error.localizedDescription)
                        return
                    }
                    
                    guard let tempURL = tempURL else {
                        print("Temp URL is nil")
                        self?.showAlert(title: "下载失败", message: "临时文件不存在")
                        return
                    }
                    
                    do {
                        if FileManager.default.fileExists(atPath: destinationURL.path) {
                            try FileManager.default.removeItem(at: destinationURL)
                        }
                        try FileManager.default.moveItem(at: tempURL, to: destinationURL)
                        print("Download success: \(destinationURL.path)")
                        self?.showAlert(title: "下载成功", message: "文件已保存至: \(destinationURL.path)")
                    } catch {
                        print("File move error: \(error.localizedDescription)")
                        self?.showAlert(title: "保存失败", message: error.localizedDescription)
                    }
                }
            }
        }.resume()
    }
    
    private func showAlert(title: String, message: String) {
        let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "确定", style: .default))
        present(alert, animated: true)
    }
}
