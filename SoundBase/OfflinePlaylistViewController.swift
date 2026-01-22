//
//  OfflinePlaylistViewController.swift
//  SoundBase
//
//  Created by samma on 2026/1/22.
//

import UIKit
import SnapKit
import AVFoundation

class OfflinePlaylistViewController: UIViewController {
    
    private var downloadedAudios: [DownloadedAudio] = []
    
    private lazy var tableView: UITableView = {
        let table = UITableView()
        table.delegate = self
        table.dataSource = self
        table.register(OfflineAudioCell.self, forCellReuseIdentifier: "OfflineAudioCell")
        table.rowHeight = 80
        return table
    }()
    
    private lazy var emptyLabel: UILabel = {
        let label = UILabel()
        label.text = "暂无离线音频\n请在搜索页下载音频"
        label.font = .systemFont(ofSize: 16)
        label.textColor = .systemGray
        label.textAlignment = .center
        label.numberOfLines = 0
        return label
    }()
    
    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        loadAudios()
    }
    
    private func setupUI() {
        title = "离线音频"
        view.backgroundColor = .systemBackground
        
        view.addSubview(tableView)
        view.addSubview(emptyLabel)
        
        tableView.snp.makeConstraints { make in
            make.edges.equalToSuperview()
        }
        
        emptyLabel.snp.makeConstraints { make in
            make.center.equalToSuperview()
        }
    }
    
    private func loadAudios() {
        downloadedAudios = AudioFileManager.shared.getAllDownloadedAudios()
        tableView.reloadData()
        emptyLabel.isHidden = !downloadedAudios.isEmpty
    }
    
    private func deleteAudio(at indexPath: IndexPath) {
        let audio = downloadedAudios[indexPath.row]
        
        let alert = UIAlertController(title: "删除音频", message: "确定要删除「\(audio.title)」吗？", preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "取消", style: .cancel))
        alert.addAction(UIAlertAction(title: "删除", style: .destructive) { [weak self] _ in
            do {
                try AudioFileManager.shared.deleteAudio(audio)
                self?.downloadedAudios.remove(at: indexPath.row)
                self?.tableView.deleteRows(at: [indexPath], with: .fade)
                self?.emptyLabel.isHidden = !(self?.downloadedAudios.isEmpty ?? true)
            } catch {
                self?.showAlert(title: "删除失败", message: error.localizedDescription)
            }
        })
        present(alert, animated: true)
    }
    
    private func showAlert(title: String, message: String) {
        let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "确定", style: .default))
        present(alert, animated: true)
    }
}

// MARK: - UITableViewDelegate, UITableViewDataSource
extension OfflinePlaylistViewController: UITableViewDelegate, UITableViewDataSource {
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return downloadedAudios.count
    }
    
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "OfflineAudioCell", for: indexPath) as! OfflineAudioCell
        let audio = downloadedAudios[indexPath.row]
        cell.configure(with: audio)
        return cell
    }
    
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        let audio = downloadedAudios[indexPath.row]
        let playerVC = LocalAudioPlayerViewController(audio: audio)
        playerVC.hidesBottomBarWhenPushed = true
        navigationController?.pushViewController(playerVC, animated: true)
    }
    
    func tableView(_ tableView: UITableView, trailingSwipeActionsConfigurationForRowAt indexPath: IndexPath) -> UISwipeActionsConfiguration? {
        let deleteAction = UIContextualAction(style: .destructive, title: "删除") { [weak self] _, _, completionHandler in
            self?.deleteAudio(at: indexPath)
            completionHandler(true)
        }
        return UISwipeActionsConfiguration(actions: [deleteAction])
    }
}

// MARK: - OfflineAudioCell
class OfflineAudioCell: UITableViewCell {
    
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
        label.font = .systemFont(ofSize: 16, weight: .medium)
        label.numberOfLines = 2
        return label
    }()
    
    private let channelLabel: UILabel = {
        let label = UILabel()
        label.font = .systemFont(ofSize: 14)
        label.textColor = .systemGray
        return label
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
        contentView.addSubview(channelLabel)
        
        thumbnailImageView.snp.makeConstraints { make in
            make.left.equalToSuperview().offset(16)
            make.centerY.equalToSuperview()
            make.width.equalTo(100)
            make.height.equalTo(56)
        }
        
        titleLabel.snp.makeConstraints { make in
            make.left.equalTo(thumbnailImageView.snp.right).offset(12)
            make.right.equalToSuperview().offset(-16)
            make.top.equalToSuperview().offset(12)
        }
        
        channelLabel.snp.makeConstraints { make in
            make.left.equalTo(titleLabel)
            make.right.equalTo(titleLabel)
            make.top.equalTo(titleLabel.snp.bottom).offset(4)
        }
    }
    
    func configure(with audio: DownloadedAudio) {
        titleLabel.text = audio.title
        channelLabel.text = audio.channelTitle
        
        if let thumbnailURL = audio.thumbnailURL {
            loadImage(from: thumbnailURL)
        } else {
            thumbnailImageView.image = UIImage(systemName: "music.note")
        }
    }
    
    private func loadImage(from url: URL) {
        URLSession.shared.dataTask(with: url) { [weak self] data, _, _ in
            guard let data = data, let image = UIImage(data: data) else { return }
            DispatchQueue.main.async {
                self?.thumbnailImageView.image = image
            }
        }.resume()
    }
}
