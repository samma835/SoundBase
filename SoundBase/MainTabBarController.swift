//
//  MainTabBarController.swift
//  SoundBase
//
//  Created by samma on 2026/1/22.
//

import UIKit

class MainTabBarController: UITabBarController {
    
    override func viewDidLoad() {
        super.viewDidLoad()
        setupTabBar()
        setupGlobalPlayer()
        setupNotifications()
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
    }
    
    private func setupTabBar() {
        // 搜索页
        let searchVC = YouTubeSearchViewController()
        let searchNav = UINavigationController(rootViewController: searchVC)
        searchNav.tabBarItem = UITabBarItem(title: "搜索", image: UIImage(systemName: "magnifyingglass"), tag: 0)
        
        // 离线播放列表页
        let offlineVC = OfflinePlaylistViewController()
        let offlineNav = UINavigationController(rootViewController: offlineVC)
        offlineNav.tabBarItem = UITabBarItem(title: "离线", image: UIImage(systemName: "music.note.list"), tag: 1)
        
        // 设置页
        let settingsVC = SettingsViewController()
        let settingsNav = UINavigationController(rootViewController: settingsVC)
        settingsNav.tabBarItem = UITabBarItem(title: "设置", image: UIImage(systemName: "gear"), tag: 2)
        
        viewControllers = [searchNav, offlineNav, settingsNav]
        
        tabBar.tintColor = .systemBlue
        
        // 初始化badge
        updateDownloadBadge()
    }
    
    private func setupGlobalPlayer() {
        GlobalPlayerContainer.shared.setup(in: self)
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
        updateDownloadBadge()
    }
    
    private func updateDownloadBadge() {
        let count = AudioFileManager.shared.getActiveDownloadCount()
        if let settingsNav = viewControllers?[2] {
            settingsNav.tabBarItem.badgeValue = count > 0 ? "\(count)" : nil
        }
    }
}
