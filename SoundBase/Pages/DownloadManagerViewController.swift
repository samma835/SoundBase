//
//  DownloadManagerViewController.swift
//  SoundBase
//
//  Created by samma on 2026/1/23.
//

import UIKit
import SnapKit

class DownloadManagerViewController: UIViewController {
    
    private enum Section: Int, CaseIterable {
        case downloading = 0
        case failed = 1
        
        var title: String {
            switch self {
            case .downloading: return "正在下载"
            case .failed: return "下载失败"
            }
        }
    }
    
    private lazy var tableView: UITableView = {
        let table = UITableView(frame: .zero, style: .insetGrouped)
        table.delegate = self
        table.dataSource = self
        table.register(DownloadTaskCell.self, forCellReuseIdentifier: "DownloadTaskCell")
        table.register(FailedDownloadCell.self, forCellReuseIdentifier: "FailedDownloadCell")
        return table
    }()
    
    private var activeDownloads: [DownloadTask] = []
    private var failedDownloads: [FailedDownload] = []
    private var downloadProgress: [String: Double] = [:] // videoId -> progress
    
    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
        loadDownloads()
        setupNotifications()
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
    }
    
    private func setupUI() {
        title = "下载管理"
        view.backgroundColor = .systemBackground
        
        view.addSubview(tableView)
        tableView.snp.makeConstraints { make in
            make.edges.equalToSuperview()
        }
    }
    
    private func loadDownloads() {
        activeDownloads = AudioFileManager.shared.getActiveDownloadTasks()
        failedDownloads = AudioFileManager.shared.getFailedDownloads()
        tableView.reloadData()
    }
    
    private func setupNotifications() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleDownloadProgress(_:)),
            name: .downloadProgressUpdated,
            object: nil
        )
        
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleDownloadCompleted(_:)),
            name: .downloadCompleted,
            object: nil
        )
        
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleDownloadFailed(_:)),
            name: .downloadFailed,
            object: nil
        )
    }
    
    @objc private func handleDownloadProgress(_ notification: Notification) {
        guard let userInfo = notification.userInfo,
              let videoId = userInfo["videoId"] as? String,
              let progress = userInfo["progress"] as? Double else { return }
        
        downloadProgress[videoId] = progress
        
        // 更新对应的cell
        if let index = activeDownloads.firstIndex(where: { $0.videoId == videoId }) {
            let indexPath = IndexPath(row: index, section: Section.downloading.rawValue)
            if let cell = tableView.cellForRow(at: indexPath) as? DownloadTaskCell {
                cell.updateProgress(progress)
            }
        }
    }
    
    @objc private func handleDownloadCompleted(_ notification: Notification) {
        loadDownloads()
    }
    
    @objc private func handleDownloadFailed(_ notification: Notification) {
        loadDownloads()
    }
}

// MARK: - UITableViewDataSource
extension DownloadManagerViewController: UITableViewDataSource {
    
    func numberOfSections(in tableView: UITableView) -> Int {
        return Section.allCases.count
    }
    
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        guard let sectionType = Section(rawValue: section) else { return 0 }
        
        switch sectionType {
        case .downloading:
            return activeDownloads.count
        case .failed:
            return failedDownloads.count
        }
    }
    
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        guard let sectionType = Section(rawValue: indexPath.section) else {
            return UITableViewCell()
        }
        
        switch sectionType {
        case .downloading:
            let cell = tableView.dequeueReusableCell(withIdentifier: "DownloadTaskCell", for: indexPath) as! DownloadTaskCell
            let task = activeDownloads[indexPath.row]
            let progress = downloadProgress[task.videoId] ?? 0
            cell.configure(with: task, progress: progress)
            return cell
            
        case .failed:
            let cell = tableView.dequeueReusableCell(withIdentifier: "FailedDownloadCell", for: indexPath) as! FailedDownloadCell
            let failedDownload = failedDownloads[indexPath.row]
            cell.configure(with: failedDownload)
            cell.onRetry = { [weak self] in
                self?.retryDownload(failedDownload)
            }
            return cell
        }
    }
    
    func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        guard let sectionType = Section(rawValue: section) else { return nil }
        
        switch sectionType {
        case .downloading:
            return activeDownloads.isEmpty ? nil : sectionType.title
        case .failed:
            return failedDownloads.isEmpty ? nil : sectionType.title
        }
    }
}

// MARK: - UITableViewDelegate
extension DownloadManagerViewController: UITableViewDelegate {
    
    func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        return 80
    }
    
    func tableView(_ tableView: UITableView, trailingSwipeActionsConfigurationForRowAt indexPath: IndexPath) -> UISwipeActionsConfiguration? {
        guard let sectionType = Section(rawValue: indexPath.section) else { return nil }
        
        if sectionType == .failed {
            let deleteAction = UIContextualAction(style: .destructive, title: "删除") { [weak self] _, _, completionHandler in
                guard let self = self else { return }
                let failedDownload = self.failedDownloads[indexPath.row]
                AudioFileManager.shared.removeFailedDownload(failedDownload)
                self.loadDownloads()
                completionHandler(true)
            }
            
            return UISwipeActionsConfiguration(actions: [deleteAction])
        }
        
        return nil
    }
}

// MARK: - Private Methods
private extension DownloadManagerViewController {
    
    func retryDownload(_ failedDownload: FailedDownload) {
        // 显示加载提示
        let alert = UIAlertController(title: "正在重新获取下载链接...", message: nil, preferredStyle: .alert)
        present(alert, animated: true)
        
        // 这里需要重新获取下载链接
        // 由于我们需要sourceURL，这里需要集成YouTube API或者保存sourceURL
        // 暂时显示提示，需要用户重新搜索
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
            alert.dismiss(animated: true) {
                let errorAlert = UIAlertController(
                    title: "需要重新搜索",
                    message: "下载链接已过期，请返回搜索页面重新搜索并下载",
                    preferredStyle: .alert
                )
                errorAlert.addAction(UIAlertAction(title: "确定", style: .default))
                self.present(errorAlert, animated: true)
            }
        }
    }
}

// MARK: - DownloadTaskCell
class DownloadTaskCell: UITableViewCell {
    
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
    
    private let progressView: UIProgressView = {
        let progress = UIProgressView(progressViewStyle: .default)
        return progress
    }()
    
    private let progressLabel: UILabel = {
        let label = UILabel()
        label.font = .systemFont(ofSize: 12)
        label.textColor = .systemGray
        label.textAlignment = .right
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
        selectionStyle = .none
        
        contentView.addSubview(titleLabel)
        contentView.addSubview(channelLabel)
        contentView.addSubview(progressView)
        contentView.addSubview(progressLabel)
        
        titleLabel.snp.makeConstraints { make in
            make.top.equalToSuperview().offset(12)
            make.left.equalToSuperview().offset(16)
            make.right.equalToSuperview().offset(-16)
        }
        
        channelLabel.snp.makeConstraints { make in
            make.top.equalTo(titleLabel.snp.bottom).offset(4)
            make.left.equalTo(titleLabel)
            make.right.equalTo(titleLabel)
        }
        
        progressView.snp.makeConstraints { make in
            make.top.equalTo(channelLabel.snp.bottom).offset(8)
            make.left.equalTo(titleLabel)
            make.right.equalTo(progressLabel.snp.left).offset(-8)
        }
        
        progressLabel.snp.makeConstraints { make in
            make.centerY.equalTo(progressView)
            make.right.equalTo(titleLabel)
            make.width.equalTo(60)
        }
    }
    
    func configure(with task: DownloadTask, progress: Double) {
        titleLabel.text = task.title
        channelLabel.text = task.channelTitle
        updateProgress(progress)
    }
    
    func updateProgress(_ progress: Double) {
        progressView.progress = Float(progress)
        progressLabel.text = "\(Int(progress * 100))%"
    }
}

// MARK: - FailedDownloadCell
class FailedDownloadCell: UITableViewCell {
    
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
    
    private let errorLabel: UILabel = {
        let label = UILabel()
        label.font = .systemFont(ofSize: 12)
        label.textColor = .systemRed
        label.numberOfLines = 1
        return label
    }()
    
    private let retryButton: UIButton = {
        let button = UIButton(type: .system)
        button.setTitle("重试", for: .normal)
        button.titleLabel?.font = .systemFont(ofSize: 14, weight: .medium)
        return button
    }()
    
    var onRetry: (() -> Void)?
    
    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        setupUI()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    private func setupUI() {
        selectionStyle = .none
        
        contentView.addSubview(titleLabel)
        contentView.addSubview(channelLabel)
        contentView.addSubview(errorLabel)
        contentView.addSubview(retryButton)
        
        titleLabel.snp.makeConstraints { make in
            make.top.equalToSuperview().offset(12)
            make.left.equalToSuperview().offset(16)
            make.right.equalTo(retryButton.snp.left).offset(-8)
        }
        
        channelLabel.snp.makeConstraints { make in
            make.top.equalTo(titleLabel.snp.bottom).offset(4)
            make.left.equalTo(titleLabel)
            make.right.equalTo(titleLabel)
        }
        
        errorLabel.snp.makeConstraints { make in
            make.top.equalTo(channelLabel.snp.bottom).offset(4)
            make.left.equalTo(titleLabel)
            make.right.equalTo(titleLabel)
        }
        
        retryButton.snp.makeConstraints { make in
            make.centerY.equalToSuperview()
            make.right.equalToSuperview().offset(-16)
            make.width.equalTo(60)
        }
        
        retryButton.addTarget(self, action: #selector(retryTapped), for: .touchUpInside)
    }
    
    func configure(with failedDownload: FailedDownload) {
        titleLabel.text = failedDownload.title
        channelLabel.text = failedDownload.channelTitle
        errorLabel.text = "错误: \(failedDownload.errorMessage)"
    }
    
    @objc private func retryTapped() {
        onRetry?()
    }
}
