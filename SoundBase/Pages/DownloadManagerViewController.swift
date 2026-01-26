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
        case completed = 1
        case failed = 2
        
        var title: String {
            switch self {
            case .downloading: return "正在下载/暂停"
            case .completed: return "已完成"
            case .failed: return "下载失败"
            }
        }
    }
    
    private lazy var tableView: UITableView = {
        let table = UITableView(frame: .zero, style: .insetGrouped)
        table.delegate = self
        table.dataSource = self
        table.register(DownloadTaskCell.self, forCellReuseIdentifier: "DownloadTaskCell")
        table.register(CompletedDownloadCell.self, forCellReuseIdentifier: "CompletedDownloadCell")
        table.register(FailedDownloadCell.self, forCellReuseIdentifier: "FailedDownloadCell")
        return table
    }()
    
    private var activeDownloads: [DownloadTask] = []
    private var completedDownloads: [DownloadedAudio] = []
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
        
        // 添加清理按钮
        navigationItem.rightBarButtonItem = UIBarButtonItem(
            title: "清理",
            style: .plain,
            target: self,
            action: #selector(showCleanupOptions)
        )
        
        view.addSubview(tableView)
        tableView.snp.makeConstraints { make in
            make.edges.equalToSuperview()
        }
    }
    
    @objc private func showCleanupOptions() {
        let alert = UIAlertController(title: "清理下载", message: "选择要清理的内容", preferredStyle: .actionSheet)
        
        if !failedDownloads.isEmpty {
            alert.addAction(UIAlertAction(title: "清理失败的下载", style: .destructive) { [weak self] _ in
                self?.clearFailedDownloads()
            })
        }
        
        if failedDownloads.isEmpty {
            alert.message = "没有可清理的内容"
        }
        
        alert.addAction(UIAlertAction(title: "取消", style: .cancel))
        
        // iPad 支持
        if let popover = alert.popoverPresentationController {
            popover.barButtonItem = navigationItem.rightBarButtonItem
        }
        
        present(alert, animated: true)
    }
    
    private func clearFailedDownloads() {
        AudioFileManager.shared.clearAllFailedDownloads()
        loadDownloads()
    }
    
    private func loadDownloads() {
        activeDownloads = AudioFileManager.shared.getActiveDownloadTasks()
        completedDownloads = AudioFileManager.shared.getAllDownloadedAudios()
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
        
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleDownloadTaskCreated(_:)),
            name: .downloadTaskCreated,
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
    
    @objc private func handleDownloadTaskCreated(_ notification: Notification) {
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
        case .completed:
            return completedDownloads.count
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
            cell.onPause = { [weak self] in
                self?.pauseDownload(task)
            }
            cell.onResume = { [weak self] in
                self?.resumeDownload(task)
            }
            cell.onCancel = { [weak self] in
                self?.cancelDownload(task)
            }
            return cell
            
        case .completed:
            let cell = tableView.dequeueReusableCell(withIdentifier: "CompletedDownloadCell", for: indexPath) as! CompletedDownloadCell
            let audio = completedDownloads[indexPath.row]
            cell.configure(with: audio)
            cell.onRedownload = { [weak self] in
                self?.redownloadAudio(audio)
            }
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
        case .completed:
            return completedDownloads.isEmpty ? nil : sectionType.title
        case .failed:
            return failedDownloads.isEmpty ? nil : sectionType.title
        }
    }
}

// MARK: - UITableViewDelegate
extension DownloadManagerViewController: UITableViewDelegate {
    
    func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        guard let sectionType = Section(rawValue: indexPath.section) else { return 80 }
        
        switch sectionType {
        case .downloading:
            return 100  // 增加高度以容纳更多元素
        case .completed:
            return 90
        case .failed:
            return 100
        }
    }
    
    func tableView(_ tableView: UITableView, trailingSwipeActionsConfigurationForRowAt indexPath: IndexPath) -> UISwipeActionsConfiguration? {
        guard let sectionType = Section(rawValue: indexPath.section) else { return nil }
        
        switch sectionType {
        case .downloading:
            let cancelAction = UIContextualAction(style: .destructive, title: "取消") { [weak self] _, _, completionHandler in
                guard let self = self else { return }
                let task = self.activeDownloads[indexPath.row]
                AudioFileManager.shared.cancelDownload(videoId: task.videoId)
                self.loadDownloads()
                completionHandler(true)
            }
            return UISwipeActionsConfiguration(actions: [cancelAction])
            
        case .completed:
            let deleteAction = UIContextualAction(style: .destructive, title: "删除") { [weak self] _, _, completionHandler in
                guard let self = self else { return }
                let audio = self.completedDownloads[indexPath.row]
                try? AudioFileManager.shared.deleteAudio(audio)
                self.loadDownloads()
                completionHandler(true)
            }
            return UISwipeActionsConfiguration(actions: [deleteAction])
            
        case .failed:
            let deleteAction = UIContextualAction(style: .destructive, title: "删除") { [weak self] _, _, completionHandler in
                guard let self = self else { return }
                let failedDownload = self.failedDownloads[indexPath.row]
                AudioFileManager.shared.removeFailedDownload(failedDownload)
                self.loadDownloads()
                completionHandler(true)
            }
            return UISwipeActionsConfiguration(actions: [deleteAction])
        }
    }
}

// MARK: - Private Methods
private extension DownloadManagerViewController {
    
    func pauseDownload(_ task: DownloadTask) {
        AudioFileManager.shared.pauseDownload(videoId: task.videoId)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            self.loadDownloads()
        }
    }
    
    func resumeDownload(_ task: DownloadTask) {
        AudioFileManager.shared.resumeDownload(videoId: task.videoId) { result in
            DispatchQueue.main.async {
                switch result {
                case .success(let audio):
                    print("✅ 下载完成: \(audio.title)")
                    self.loadDownloads()
                case .failure(let error):
                    print("❌ 下载失败: \(error.localizedDescription)")
                    self.loadDownloads()
                }
            }
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            self.loadDownloads()
        }
    }
    
    func cancelDownload(_ task: DownloadTask) {
        let alert = UIAlertController(
            title: "取消下载",
            message: "确定要取消下载 \"\(task.title)\" 吗？",
            preferredStyle: .alert
        )
        
        alert.addAction(UIAlertAction(title: "取消", style: .cancel))
        alert.addAction(UIAlertAction(title: "确定", style: .destructive) { [weak self] _ in
            AudioFileManager.shared.cancelDownload(videoId: task.videoId)
            self?.loadDownloads()
        })
        
        present(alert, animated: true)
    }
    
    func redownloadAudio(_ audio: DownloadedAudio) {
        let alert = UIAlertController(
            title: "重新下载",
            message: "下载链接已过期，请返回搜索页面重新搜索并下载",
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "确定", style: .default))
        present(alert, animated: true)
    }
    
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
        label.font = .systemFont(ofSize: 13)
        label.textColor = .systemGray
        label.numberOfLines = 1
        label.lineBreakMode = .byTruncatingTail
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
    
    private let actionButton: UIButton = {
        let button = UIButton(type: .system)
        button.titleLabel?.font = .systemFont(ofSize: 14, weight: .medium)
        return button
    }()
    
    var onPause: (() -> Void)?
    var onResume: (() -> Void)?
    var onCancel: (() -> Void)?
    
    private var currentStatus: DownloadTaskStatus?
    
    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        setupUI()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    private func setupUI() {
        selectionStyle = .none
        
        contentView.addSubview(actionButton)
        contentView.addSubview(titleLabel)
        contentView.addSubview(channelLabel)
        contentView.addSubview(progressView)
        contentView.addSubview(progressLabel)
        
        // 先布局按钮，确保它有固定位置
        actionButton.snp.makeConstraints { make in
            make.top.equalToSuperview().offset(12)
            make.right.equalToSuperview().offset(-16)
            make.width.equalTo(50)
            make.height.equalTo(32)
        }
        
        // 标题标签，留出按钮的空间
        titleLabel.snp.makeConstraints { make in
            make.top.equalToSuperview().offset(10)
            make.left.equalToSuperview().offset(16)
            make.right.equalTo(actionButton.snp.left).offset(-12)
        }
        
        // 频道标签
        channelLabel.snp.makeConstraints { make in
            make.top.equalTo(titleLabel.snp.bottom).offset(4)
            make.left.equalTo(titleLabel)
            make.right.equalTo(titleLabel)
        }
        
        // 进度条
        progressView.snp.makeConstraints { make in
            make.top.equalTo(channelLabel.snp.bottom).offset(10)
            make.left.equalTo(titleLabel)
            make.bottom.lessThanOrEqualToSuperview().offset(-12)
        }
        
        // 进度标签
        progressLabel.snp.makeConstraints { make in
            make.centerY.equalTo(progressView)
            make.left.equalTo(progressView.snp.right).offset(8)
            make.right.lessThanOrEqualToSuperview().offset(-16)
            make.width.greaterThanOrEqualTo(50)
        }
        
        actionButton.addTarget(self, action: #selector(actionTapped), for: .touchUpInside)
    }
    
    func configure(with task: DownloadTask, progress: Double) {
        titleLabel.text = task.title
        channelLabel.text = task.channelTitle
        currentStatus = task.status
        
        switch task.status {
        case .parsing:
            progressView.isHidden = false
            progressLabel.isHidden = false
            progressView.progress = 0
            progressLabel.text = "解析链接中..."
            actionButton.setTitle("取消", for: .normal)
            actionButton.isEnabled = true
            
        case .downloading:
            updateProgress(progress)
            actionButton.setTitle("暂停", for: .normal)
            actionButton.isEnabled = true
            progressView.isHidden = false
            progressLabel.isHidden = false
            
        case .paused:
            progressView.progress = Float(progress)
            progressLabel.text = "已暂停"
            actionButton.setTitle("继续", for: .normal)
            actionButton.isEnabled = true
            progressView.isHidden = false
            progressLabel.isHidden = false
            
        case .failed:
            progressView.isHidden = true
            progressLabel.isHidden = true
            actionButton.setTitle("重试", for: .normal)
            actionButton.isEnabled = true
        }
    }
    
    func updateProgress(_ progress: Double) {
        progressView.progress = Float(progress)
        progressLabel.text = "\(Int(progress * 100))%"
    }
    
    @objc private func actionTapped() {
        guard let status = currentStatus else { return }
        
        switch status {
        case .parsing:
            onCancel?()
        case .downloading:
            onPause?()
        case .paused:
            onResume?()
        case .failed:
            onCancel?()
        }
    }
}

// MARK: - CompletedDownloadCell
class CompletedDownloadCell: UITableViewCell {
    
    private let titleLabel: UILabel = {
        let label = UILabel()
        label.font = .systemFont(ofSize: 16, weight: .medium)
        label.numberOfLines = 2
        return label
    }()
    
    private let channelLabel: UILabel = {
        let label = UILabel()
        label.font = .systemFont(ofSize: 13)
        label.textColor = .systemGray
        label.numberOfLines = 1
        label.lineBreakMode = .byTruncatingTail
        return label
    }()
    
    private let dateLabel: UILabel = {
        let label = UILabel()
        label.font = .systemFont(ofSize: 11)
        label.textColor = .systemGray2
        label.numberOfLines = 1
        return label
    }()
    
    private let redownloadButton: UIButton = {
        let button = UIButton(type: .system)
        button.setTitle("重新下载", for: .normal)
        button.titleLabel?.font = .systemFont(ofSize: 14, weight: .medium)
        return button
    }()
    
    var onRedownload: (() -> Void)?
    
    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        setupUI()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    private func setupUI() {
        selectionStyle = .none
        
        contentView.addSubview(redownloadButton)
        contentView.addSubview(titleLabel)
        contentView.addSubview(channelLabel)
        contentView.addSubview(dateLabel)
        
        // 先布局按钮
        redownloadButton.snp.makeConstraints { make in
            make.top.equalToSuperview().offset(12)
            make.right.equalToSuperview().offset(-16)
            make.width.equalTo(70)
            make.height.equalTo(32)
        }
        
        // 标题标签
        titleLabel.snp.makeConstraints { make in
            make.top.equalToSuperview().offset(10)
            make.left.equalToSuperview().offset(16)
            make.right.equalTo(redownloadButton.snp.left).offset(-12)
        }
        
        // 频道标签
        channelLabel.snp.makeConstraints { make in
            make.top.equalTo(titleLabel.snp.bottom).offset(4)
            make.left.equalTo(titleLabel)
            make.right.equalTo(titleLabel)
        }
        
        // 日期标签
        dateLabel.snp.makeConstraints { make in
            make.top.equalTo(channelLabel.snp.bottom).offset(4)
            make.left.equalTo(titleLabel)
            make.right.equalTo(titleLabel)
            make.bottom.lessThanOrEqualToSuperview().offset(-10)
        }
        
        redownloadButton.addTarget(self, action: #selector(redownloadTapped), for: .touchUpInside)
    }
    
    func configure(with audio: DownloadedAudio) {
        titleLabel.text = audio.title
        channelLabel.text = audio.channelTitle
        
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        dateLabel.text = "下载于: \(formatter.string(from: audio.downloadDate))"
    }
    
    @objc private func redownloadTapped() {
        onRedownload?()
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
        label.font = .systemFont(ofSize: 13)
        label.textColor = .systemGray
        label.numberOfLines = 1
        label.lineBreakMode = .byTruncatingTail
        return label
    }()
    
    private let errorLabel: UILabel = {
        let label = UILabel()
        label.font = .systemFont(ofSize: 11)
        label.textColor = .systemRed
        label.numberOfLines = 2
        label.lineBreakMode = .byTruncatingTail
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
        
        contentView.addSubview(retryButton)
        contentView.addSubview(titleLabel)
        contentView.addSubview(channelLabel)
        contentView.addSubview(errorLabel)
        
        // 先布局按钮
        retryButton.snp.makeConstraints { make in
            make.top.equalToSuperview().offset(12)
            make.right.equalToSuperview().offset(-16)
            make.width.equalTo(50)
            make.height.equalTo(32)
        }
        
        // 标题标签
        titleLabel.snp.makeConstraints { make in
            make.top.equalToSuperview().offset(10)
            make.left.equalToSuperview().offset(16)
            make.right.equalTo(retryButton.snp.left).offset(-12)
        }
        
        // 频道标签
        channelLabel.snp.makeConstraints { make in
            make.top.equalTo(titleLabel.snp.bottom).offset(4)
            make.left.equalTo(titleLabel)
            make.right.equalTo(titleLabel)
        }
        
        // 错误标签 - 允许换行显示完整错误信息
        errorLabel.snp.makeConstraints { make in
            make.top.equalTo(channelLabel.snp.bottom).offset(4)
            make.left.equalTo(titleLabel)
            make.right.equalTo(titleLabel)
            make.bottom.lessThanOrEqualToSuperview().offset(-10)
        }
        
        retryButton.addTarget(self, action: #selector(retryTapped), for: .touchUpInside)
    }
    
    func configure(with failedDownload: FailedDownload) {
        titleLabel.text = failedDownload.title
        channelLabel.text = failedDownload.channelTitle
        
        // 简化错误信息显示
        let errorMessage = failedDownload.errorMessage
        if errorMessage.count > 50 {
            errorLabel.text = "错误: \(String(errorMessage.prefix(47)))..."
        } else {
            errorLabel.text = "错误: \(errorMessage)"
        }
    }
    
    @objc private func retryTapped() {
        onRetry?()
    }
}
