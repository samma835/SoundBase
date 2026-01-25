//
//  GlobalPlayerContainer.swift
//  SoundBase
//
//  Created by samma on 2026/1/23.
//

import UIKit
import SnapKit

class GlobalPlayerContainer {
    static let shared = GlobalPlayerContainer()
    
    private var miniPlayerView: MiniPlayerView?
    private weak var containerViewController: UIViewController?
    private let miniPlayerHeight: CGFloat = 64
    
    // 保存当前播放的视频信息
    var currentVideo: VideoSearchResult?
    
    private init() {}
    
    func setup(in viewController: UIViewController) {
        containerViewController = viewController
        
        // 创建 mini player
        let miniPlayer = MiniPlayerView()
        miniPlayer.isHidden = true
        miniPlayer.alpha = 0
        miniPlayer.onTap = { [weak self] in
            self?.showPlayerDetail()
        }
        miniPlayer.onPlaylistTap = { [weak self] in
            self?.showPlaylist()
        }
        
        viewController.view.addSubview(miniPlayer)
        
        // 约束到 TabBar 上方，避免遮挡 TabBar
        if let tabBarController = viewController as? UITabBarController {
            miniPlayer.snp.makeConstraints { make in
                make.left.right.equalToSuperview()
                make.bottom.equalTo(tabBarController.tabBar.snp.top)
                make.height.equalTo(miniPlayerHeight)
            }
        } else {
            miniPlayer.snp.makeConstraints { make in
                make.left.right.equalToSuperview()
                make.bottom.equalTo(viewController.view.safeAreaLayoutGuide.snp.bottom)
                make.height.equalTo(miniPlayerHeight)
            }
        }
        
        miniPlayerView = miniPlayer
        
        // 监听播放器状态
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(playbackStateChanged),
            name: MediaPlayerManager.playbackStateChangedNotification,
            object: nil
        )
    }
    
    func show(title: String?, artist: String?, artwork: UIImage?, video: VideoSearchResult? = nil) {
        if let video = video {
            currentVideo = video
        }
        
        // 无论迷你播放器是否显示，都要更新信息
        miniPlayerView?.updateInfo(title: title, artist: artist, artwork: artwork)
        
        // 如果已经显示，不需要再次显示动画
        guard miniPlayerView?.isHidden == true else { return }
        
        // 检查是否在播放器详情页，如果是则不显示迷你播放器（但信息已经更新了）
        if isInPlayerDetailPage() {
            return
        }
        
        // 显示迷你播放器
        miniPlayerView?.isHidden = false
        
        UIView.animate(withDuration: 0.3, delay: 0, options: .curveEaseOut) {
            self.miniPlayerView?.alpha = 1
        }
    }
    
    func hide() {
        UIView.animate(withDuration: 0.3, delay: 0, options: .curveEaseIn) {
            self.miniPlayerView?.alpha = 0
        } completion: { _ in
            self.miniPlayerView?.isHidden = true
        }
    }
    
    func updateInfo(title: String?, artist: String?, artwork: UIImage?, video: VideoSearchResult? = nil) {
        if let video = video {
            currentVideo = video
        }
        miniPlayerView?.updateInfo(title: title, artist: artist, artwork: artwork)
    }
    
    private func showPlayerDetail() {
        // 从当前显示的 navigation controller 推入播放器详情页
        guard let tabBarController = containerViewController as? UITabBarController,
              let selectedNav = tabBarController.selectedViewController as? UINavigationController,
              let video = currentVideo else {
            print("📱 [全局播放器] 无法获取导航控制器或视频信息")
            return
        }
        
        // 检查当前是否已经在播放器页面
        if let topVC = selectedNav.topViewController as? AudioPlayerViewController {
            print("📱 [全局播放器] 已经在播放器详情页")
            return
        }
        
        // 推入播放器详情页
        let playerVC = AudioPlayerViewController(video: video)
        playerVC.hidesBottomBarWhenPushed = true
        selectedNav.pushViewController(playerVC, animated: true)
        
        print("📱 [全局播放器] 进入播放器详情页: \(video.title)")
    }
    
    private func showPlaylist() {
        // 从当前显示的 navigation controller 推入播放列表页
        guard let tabBarController = containerViewController as? UITabBarController,
              let selectedNav = tabBarController.selectedViewController as? UINavigationController else {
            print("📱 [全局播放器] 无法获取导航控制器")
            return
        }
        
        let playlistVC = PlaylistViewController()
        playlistVC.hidesBottomBarWhenPushed = true
        selectedNav.pushViewController(playlistVC, animated: true)
        
        print("📱 [全局播放器] 打开播放列表")
    }
    
    // 检查当前是否在播放器详情页
    private func isInPlayerDetailPage() -> Bool {
        guard let tabBarController = containerViewController as? UITabBarController,
              let selectedNav = tabBarController.selectedViewController as? UINavigationController else {
            return false
        }
        return selectedNav.topViewController is AudioPlayerViewController
    }
    
    @objc private func playbackStateChanged(_ notification: Notification) {
        guard let userInfo = notification.userInfo,
              let isPlaying = userInfo["isPlaying"] as? Bool else { return }
        
        // 当开始播放时显示 mini player，但如果在播放器详情页则不显示
        if isPlaying && miniPlayerView?.isHidden == true && !isInPlayerDetailPage() {
            let playerManager = MediaPlayerManager.shared
            show(
                title: playerManager.currentTitle,
                artist: playerManager.currentArtist,
                artwork: playerManager.currentArtwork
            )
        }
    }
}
