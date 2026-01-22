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
        setupAudioSession()
        loadAudioInfo()
        setupPlayer()
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
        do {
            let audioSession = AVAudioSession.sharedInstance()
            try audioSession.setCategory(.playback, mode: .default)
            try audioSession.setActive(true)
        } catch {
            print("Failed to set up audio session: \(error.localizedDescription)")
        }
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
        let playerItem = AVPlayerItem(url: audio.fileURL)
        player = AVPlayer(playerItem: playerItem)
        
        playerItem.addObserver(self, forKeyPath: "status", options: [.new, .initial], context: nil)
        
        timeObserver = player?.addPeriodicTimeObserver(forInterval: CMTime(seconds: 0.5, preferredTimescale: CMTimeScale(NSEC_PER_SEC)), queue: .main) { [weak self] time in
            self?.updateProgress()
        }
        
        NotificationCenter.default.addObserver(self, selector: #selector(playerDidFinishPlaying), name: .AVPlayerItemDidPlayToEndTime, object: playerItem)
    }
    
    override func observeValue(forKeyPath keyPath: String?, of object: Any?, change: [NSKeyValueChangeKey : Any]?, context: UnsafeMutableRawPointer?) {
        if keyPath == "status" {
            if let statusNumber = change?[.newKey] as? NSNumber {
                let status = AVPlayerItem.Status(rawValue: statusNumber.intValue)
                if status == .readyToPlay {
                    print("Local player ready")
                } else if status == .failed {
                    print("Local player failed: \(player?.currentItem?.error?.localizedDescription ?? "unknown")")
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
        guard let player = player else { return }
        
        if player.timeControlStatus == .playing {
            player.pause()
            playButton.setImage(UIImage(systemName: "play.circle.fill"), for: .normal)
        } else {
            player.play()
            playButton.setImage(UIImage(systemName: "pause.circle.fill"), for: .normal)
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
}
