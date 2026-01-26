//
//  SettingsViewController.swift
//  SoundBase
//
//  Created by samma on 2026/1/22.
//

import UIKit
import SnapKit

class SettingsViewController: UIViewController {
    
    private lazy var tableView: UITableView = {
        let table = UITableView(frame: .zero, style: .insetGrouped)
        table.delegate = self
        table.dataSource = self
        table.register(UITableViewCell.self, forCellReuseIdentifier: "Cell")
        return table
    }()
    
    private let settingsItems = [
        ("下载管理", "查看正在下载和失败的任务")
    ]
    
    private var downloadCount: Int = 0
    
    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
        setupNotifications()
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        updateDownloadCount()
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
    }
    
    private func setupUI() {
        title = "设置"
        view.backgroundColor = .systemBackground
        
        view.addSubview(tableView)
        
        tableView.snp.makeConstraints { make in
            make.edges.equalToSuperview()
        }
    }
    
    private func setupNotifications() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleDownloadCountChanged(_:)),
            name: .downloadCountChanged,
            object: nil
        )
    }
    
    @objc private func handleDownloadCountChanged(_ notification: Notification) {
        updateDownloadCount()
    }
    
    private func updateDownloadCount() {
        downloadCount = AudioFileManager.shared.getActiveDownloadCount()
        tableView.reloadData()
    }
}

// MARK: - UITableViewDataSource
extension SettingsViewController: UITableViewDataSource {
    
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return settingsItems.count
    }
    
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "Cell", for: indexPath)
        let item = settingsItems[indexPath.row]
        
        cell.textLabel?.text = item.0
        cell.detailTextLabel?.text = item.1
        cell.accessoryType = .disclosureIndicator
        
        // 为下载管理添加数量标识
        if indexPath.row == 0 && downloadCount > 0 {
            let badgeLabel = UILabel()
            badgeLabel.text = "\(downloadCount)"
            badgeLabel.font = .systemFont(ofSize: 14, weight: .medium)
            badgeLabel.textColor = .white
            badgeLabel.backgroundColor = .systemRed
            badgeLabel.textAlignment = .center
            badgeLabel.layer.cornerRadius = 10
            badgeLabel.clipsToBounds = true
            badgeLabel.frame = CGRect(x: 0, y: 0, width: 20, height: 20)
            
            let containerView = UIView(frame: CGRect(x: 0, y: 0, width: 30, height: 20))
            containerView.addSubview(badgeLabel)
            cell.accessoryView = containerView
        } else {
            cell.accessoryView = nil
        }
        
        return cell
    }
}

// MARK: - UITableViewDelegate
extension SettingsViewController: UITableViewDelegate {
    
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        
        switch indexPath.row {
        case 0:
            let downloadManagerVC = DownloadManagerViewController()
            navigationController?.pushViewController(downloadManagerVC, animated: true)
        default:
            break
        }
    }
}
