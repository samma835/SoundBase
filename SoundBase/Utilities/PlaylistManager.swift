//
//  PlaylistManager.swift
//  SoundBase
//
//  Created by samma on 2026/1/23.
//

import Foundation
import UIKit

// 播放列表项
struct PlaylistItem: Codable, Equatable {
    let id: String  // 唯一标识
    let videoId: String
    let title: String
    let artist: String
    let thumbnailURL: URL?
    let audioURL: URL  // 本地文件或远程URL
    let addedDate: Date
    
    static func == (lhs: PlaylistItem, rhs: PlaylistItem) -> Bool {
        return lhs.id == rhs.id
    }
}

// 播放列表通知
extension Notification.Name {
    static let playlistUpdated = Notification.Name("playlistUpdated")
    static let currentTrackChanged = Notification.Name("currentTrackChanged")
}

class PlaylistManager {
    static let shared = PlaylistManager()
    
    private let playlistFileName = "playlist.json"
    private let documentsDirectory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    
    // 播放列表
    private(set) var playlist: [PlaylistItem] = []
    
    // 当前播放的索引
    private(set) var currentIndex: Int? = nil
    
    private init() {
        loadPlaylist()
        setupNotifications()
    }
    
    // MARK: - Public Methods
    
    // 添加并播放（插入到当前播放的下一个位置）
    func addAndPlay(videoId: String, title: String, artist: String, thumbnailURL: URL?, audioURL: URL, artwork: UIImage?) {
        let item = PlaylistItem(
            id: UUID().uuidString,
            videoId: videoId,
            title: title,
            artist: artist,
            thumbnailURL: thumbnailURL,
            audioURL: audioURL,
            addedDate: Date()
        )
        
        // 检查是否已存在相同的视频
        if let existingIndex = playlist.firstIndex(where: { $0.videoId == videoId }) {
            // 如果是当前播放的，直接返回
            if currentIndex == existingIndex {
                print("🎵 [播放列表] 已经在播放该音频")
                return
            }
            // 删除旧的
            playlist.remove(at: existingIndex)
            // 调整当前索引
            if let current = currentIndex, existingIndex < current {
                currentIndex = current - 1
            }
        }
        
        // 插入到当前播放的下一个位置
        if let current = currentIndex {
            let insertIndex = current + 1
            playlist.insert(item, at: insertIndex)
            currentIndex = insertIndex
        } else {
            // 没有当前播放，插入到头部
            playlist.insert(item, at: 0)
            currentIndex = 0
        }
        
        savePlaylist()
        notifyPlaylistUpdated()
        
        // 播放
        playItem(at: currentIndex!)
        
        print("🎵 [播放列表] 添加并播放: \(title), 当前位置: \(currentIndex!)")
    }
    
    // 播放指定索引的音频
    func play(at index: Int) {
        guard index >= 0 && index < playlist.count else {
            print("❌ [播放列表] 索引越界: \(index)")
            return
        }
        
        currentIndex = index
        playItem(at: index)
        notifyCurrentTrackChanged()
        
        print("🎵 [播放列表] 播放索引: \(index)")
    }
    
    // 播放下一首
    func playNext() -> Bool {
        guard let current = currentIndex else { return false }
        let nextIndex = current + 1
        
        if nextIndex < playlist.count {
            play(at: nextIndex)
            return true
        }
        
        print("🎵 [播放列表] 已经是最后一首")
        return false
    }
    
    // 播放上一首
    func playPrevious() -> Bool {
        guard let current = currentIndex else { return false }
        let previousIndex = current - 1
        
        if previousIndex >= 0 {
            play(at: previousIndex)
            return true
        }
        
        print("🎵 [播放列表] 已经是第一首")
        return false
    }
    
    // 删除指定索引的音频
    func remove(at index: Int) {
        guard index >= 0 && index < playlist.count else { return }
        
        let isCurrentPlaying = (currentIndex == index)
        playlist.remove(at: index)
        
        // 调整当前索引
        if let current = currentIndex {
            if index < current {
                currentIndex = current - 1
            } else if index == current {
                // 删除的是当前播放的
                if isCurrentPlaying {
                    stopCurrentPlayback()
                }
                currentIndex = nil
            }
        }
        
        savePlaylist()
        notifyPlaylistUpdated()
        
        print("🎵 [播放列表] 删除索引: \(index)")
    }
    
    // 清空播放列表
    func clearAll() {
        let wasPlaying = currentIndex != nil
        
        playlist.removeAll()
        currentIndex = nil
        
        if wasPlaying {
            stopCurrentPlayback()
        }
        
        savePlaylist()
        notifyPlaylistUpdated()
        
        print("🎵 [播放列表] 已清空")
    }
    
    // 获取当前播放的项
    func getCurrentItem() -> PlaylistItem? {
        guard let index = currentIndex, index < playlist.count else {
            return nil
        }
        return playlist[index]
    }
    
    // 获取播放列表
    func getPlaylist() -> [PlaylistItem] {
        return playlist
    }
    
    // MARK: - Private Methods
    
    private func playItem(at index: Int) {
        let item = playlist[index]
        
        // 加载缩略图
        var artwork: UIImage?
        if let thumbnailURL = item.thumbnailURL {
            if thumbnailURL.isFileURL {
                if let data = try? Data(contentsOf: thumbnailURL) {
                    artwork = UIImage(data: data)
                }
            } else {
                // 异步加载远程图片
                URLSession.shared.dataTask(with: thumbnailURL) { data, _, _ in
                    guard let data = data, let image = UIImage(data: data) else { return }
                    DispatchQueue.main.async {
                        // 更新全局播放器的封面
                        GlobalPlayerContainer.shared.updateInfo(
                            title: item.title,
                            artist: item.artist,
                            artwork: image,
                            video: nil
                        )
                    }
                }.resume()
            }
        }
        
        // 播放音频
        MediaPlayerManager.shared.play(
            url: item.audioURL,
            title: item.title,
            artist: item.artist,
            artwork: artwork
        )
        
        // 构造 VideoSearchResult
        let videoResult = VideoSearchResult(
            videoId: item.videoId,
            title: item.title,
            channelTitle: item.artist,
            thumbnailURL: item.thumbnailURL
        )
        
        // 显示全局播放器
        GlobalPlayerContainer.shared.show(
            title: item.title,
            artist: item.artist,
            artwork: artwork,
            video: videoResult
        )
    }
    
    private func stopCurrentPlayback() {
        MediaPlayerManager.shared.pause()
        GlobalPlayerContainer.shared.hide()
        print("⏹️ [播放列表] 停止播放")
    }
    
    private func setupNotifications() {
        // 监听播放完成
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(playbackFinished),
            name: MediaPlayerManager.playbackFinishedNotification,
            object: nil
        )
    }
    
    @objc private func playbackFinished() {
        print("🎵 [播放列表] 当前音频播放完成，尝试播放下一首")
        // 自动播放下一首
        _ = playNext()
    }
    
    private func notifyPlaylistUpdated() {
        NotificationCenter.default.post(name: .playlistUpdated, object: nil)
    }
    
    private func notifyCurrentTrackChanged() {
        NotificationCenter.default.post(name: .currentTrackChanged, object: nil)
    }
    
    // MARK: - Persistence
    
    private func savePlaylist() {
        let playlistURL = documentsDirectory.appendingPathComponent(playlistFileName)
        
        let data: [String: Any] = [
            "playlist": playlist.map { item in
                [
                    "id": item.id,
                    "videoId": item.videoId,
                    "title": item.title,
                    "artist": item.artist,
                    "thumbnailURL": item.thumbnailURL?.absoluteString ?? "",
                    "audioURL": item.audioURL.absoluteString,
                    "addedDate": ISO8601DateFormatter().string(from: item.addedDate)
                ]
            },
            "currentIndex": currentIndex ?? -1
        ]
        
        do {
            let jsonData = try JSONSerialization.data(withJSONObject: data, options: .prettyPrinted)
            try jsonData.write(to: playlistURL, options: .atomic)
            print("💾 [播放列表] 已保存: \(playlist.count) 首")
        } catch {
            print("❌ [播放列表] 保存失败: \(error.localizedDescription)")
        }
    }
    
    private func loadPlaylist() {
        let playlistURL = documentsDirectory.appendingPathComponent(playlistFileName)
        
        guard FileManager.default.fileExists(atPath: playlistURL.path) else {
            print("💾 [播放列表] 文件不存在")
            return
        }
        
        do {
            let jsonData = try Data(contentsOf: playlistURL)
            guard let data = try JSONSerialization.jsonObject(with: jsonData) as? [String: Any] else {
                return
            }
            
            // 加载播放列表
            if let playlistArray = data["playlist"] as? [[String: Any]] {
                playlist = playlistArray.compactMap { dict in
                    guard let id = dict["id"] as? String,
                          let videoId = dict["videoId"] as? String,
                          let title = dict["title"] as? String,
                          let artist = dict["artist"] as? String,
                          let audioURLString = dict["audioURL"] as? String,
                          let audioURL = URL(string: audioURLString),
                          let addedDateString = dict["addedDate"] as? String,
                          let addedDate = ISO8601DateFormatter().date(from: addedDateString) else {
                        return nil
                    }
                    
                    let thumbnailURL: URL?
                    if let thumbnailURLString = dict["thumbnailURL"] as? String, !thumbnailURLString.isEmpty {
                        thumbnailURL = URL(string: thumbnailURLString)
                    } else {
                        thumbnailURL = nil
                    }
                    
                    return PlaylistItem(
                        id: id,
                        videoId: videoId,
                        title: title,
                        artist: artist,
                        thumbnailURL: thumbnailURL,
                        audioURL: audioURL,
                        addedDate: addedDate
                    )
                }
            }
            
            // 加载当前索引
            if let index = data["currentIndex"] as? Int, index >= 0 {
                currentIndex = index
            }
            
            print("💾 [播放列表] 已加载: \(playlist.count) 首, 当前索引: \(currentIndex ?? -1)")
        } catch {
            print("❌ [播放列表] 加载失败: \(error.localizedDescription)")
        }
    }
}
