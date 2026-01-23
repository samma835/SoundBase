//
//  PlaylistViewController.swift
//  SoundBase
//
//  Created by samma on 2026/1/23.
//

import UIKit
import SnapKit

class PlaylistViewController: UIViewController {
    
    private let playlistManager = PlaylistManager.shared
    private var playlist: [PlaylistItem] = []
    
    private lazy var tableView: UITableView = {
        let table = UITableView()
        table.delegate = self
        table.dataSource = self
        table.register(PlaylistCell.self, forCellReuseIdentifier: "PlaylistCell")
        table.rowHeight = 70
        table.backgroundColor = .systemBackground
        return table
    }()
    
    private lazy var emptyLabel: UILabel = {
        let label = UILabel()
        label.text = "播放列表为空"
        label.font = .systemFont(ofSize: 16)
        label.textColor = .systemGray
        label.textAlignment = .center
        return label
    }()
    
    private lazy var clearButton: UIBarButtonItem = {
        let button = UIBarButtonItem(
            title: "清空",
            style: .plain,
            target: self,
            action: #selector(clearButtonTapped)
        )
        button.tintColor = .systemRed
        return button
    }()
    
    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
        loadPlaylist()
        setupNotifications()
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
    }
    
    private func setupUI() {
        title = "播放列表"
        view.backgroundColor = .systemBackground
        
        navigationItem.rightBarButtonItem = clearButton
        
        view.addSubview(tableView)
        view.addSubview(emptyLabel)
        
        tableView.snp.makeConstraints { make in
            make.edges.equalToSuperview()
        }
        
        emptyLabel.snp.makeConstraints { make in
            make.center.equalToSuperview()
        }
    }
    
    private func setupNotifications() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(playlistUpdated),
            name: .playlistUpdated,
            object: nil
        )
        
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(currentTrackChanged),
            name: .currentTrackChanged,
            object: nil
        )
    }
    
    private func loadPlaylist() {
        playlist = playlistManager.getPlaylist()
        tableView.reloadData()
        updateEmptyState()
        updateClearButton()
    }
    
    private func updateEmptyState() {
        emptyLabel.isHidden = !playlist.isEmpty
    }
    
    private func updateClearButton() {
        clearButton.isEnabled = !playlist.isEmpty
    }
    
    @objc private func playlistUpdated() {
        loadPlaylist()
    }
    
    @objc private func currentTrackChanged() {
        tableView.reloadData()
    }
    
    @objc private func clearButtonTapped() {
        let alert = UIAlertController(
            title: "清空播放列表",
            message: "确定要清空所有歌曲吗？",
            preferredStyle: .alert
        )
        
        alert.addAction(UIAlertAction(title: "取消", style: .cancel))
        alert.addAction(UIAlertAction(title: "清空", style: .destructive) { [weak self] _ in
            self?.playlistManager.clearAll()
        })
        
        present(alert, animated: true)
    }
}

// MARK: - UITableViewDelegate, UITableViewDataSource
extension PlaylistViewController: UITableViewDelegate, UITableViewDataSource {
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return playlist.count
    }
    
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "PlaylistCell", for: indexPath) as! PlaylistCell
        let item = playlist[indexPath.row]
        let isCurrent = (playlistManager.currentIndex == indexPath.row)
        cell.configure(with: item, isCurrent: isCurrent)
        return cell
    }
    
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        playlistManager.play(at: indexPath.row)
    }
    
    func tableView(_ tableView: UITableView, trailingSwipeActionsConfigurationForRowAt indexPath: IndexPath) -> UISwipeActionsConfiguration? {
        let deleteAction = UIContextualAction(style: .destructive, title: "删除") { [weak self] _, _, completionHandler in
            self?.playlistManager.remove(at: indexPath.row)
            completionHandler(true)
        }
        deleteAction.image = UIImage(systemName: "trash")
        
        return UISwipeActionsConfiguration(actions: [deleteAction])
    }
}

// MARK: - PlaylistCell
class PlaylistCell: UITableViewCell {
    
    private let thumbnailImageView: UIImageView = {
        let imageView = UIImageView()
        imageView.contentMode = .scaleAspectFill
        imageView.clipsToBounds = true
        imageView.backgroundColor = .systemGray5
        imageView.layer.cornerRadius = 4
        return imageView
    }()
    
    private let titleLabel: UILabel = {
        let label = UILabel()
        label.font = .systemFont(ofSize: 15, weight: .medium)
        label.numberOfLines = 1
        return label
    }()
    
    private let artistLabel: UILabel = {
        let label = UILabel()
        label.font = .systemFont(ofSize: 13)
        label.textColor = .systemGray
        label.numberOfLines = 1
        return label
    }()
    
    private let playingIndicator: UIImageView = {
        let imageView = UIImageView()
        imageView.image = UIImage(systemName: "waveform")
        imageView.tintColor = .systemBlue
        imageView.contentMode = .scaleAspectFit
        imageView.isHidden = true
        return imageView
    }()
    
    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        setupUI()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    private func setupUI() {
        contentView.addSubview(thumbnailImageView)
        contentView.addSubview(titleLabel)
        contentView.addSubview(artistLabel)
        contentView.addSubview(playingIndicator)
        
        thumbnailImageView.snp.makeConstraints { make in
            make.left.equalToSuperview().offset(16)
            make.centerY.equalToSuperview()
            make.width.height.equalTo(50)
        }
        
        playingIndicator.snp.makeConstraints { make in
            make.right.equalToSuperview().offset(-16)
            make.centerY.equalToSuperview()
            make.width.height.equalTo(24)
        }
        
        titleLabel.snp.makeConstraints { make in
            make.left.equalTo(thumbnailImageView.snp.right).offset(12)
            make.right.equalTo(playingIndicator.snp.left).offset(-12)
            make.top.equalToSuperview().offset(14)
        }
        
        artistLabel.snp.makeConstraints { make in
            make.left.equalTo(titleLabel)
            make.right.equalTo(titleLabel)
            make.top.equalTo(titleLabel.snp.bottom).offset(4)
        }
    }
    
    func configure(with item: PlaylistItem, isCurrent: Bool) {
        titleLabel.text = item.title
        artistLabel.text = item.artist
        playingIndicator.isHidden = !isCurrent
        
        // 高亮当前播放的歌曲
        if isCurrent {
            titleLabel.textColor = .systemBlue
            artistLabel.textColor = .systemBlue
        } else {
            titleLabel.textColor = .label
            artistLabel.textColor = .systemGray
        }
        
        // 加载缩略图
        if let thumbnailURL = item.thumbnailURL {
            loadImage(from: thumbnailURL)
        } else {
            thumbnailImageView.image = UIImage(systemName: "music.note")
        }
    }
    
    private func loadImage(from url: URL) {
        if url.isFileURL {
            if let data = try? Data(contentsOf: url), let image = UIImage(data: data) {
                thumbnailImageView.image = image
            }
        } else {
            URLSession.shared.dataTask(with: url) { [weak self] data, _, _ in
                guard let data = data, let image = UIImage(data: data) else { return }
                DispatchQueue.main.async {
                    self?.thumbnailImageView.image = image
                }
            }.resume()
        }
    }
}
