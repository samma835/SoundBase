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
    let audioFileName: String?  // 本地文件名（如果是下载的音频）
    var audioURLString: String?  // 远程URL字符串（如果是在线音频）
    let addedDate: Date
    var isParsing: Bool  // 是否正在解析链接
    
    // 动态计算实际的音频URL
    var audioURL: URL? {
        if isParsing {
            return nil  // 解析中，还没有URL
        }
        
        if let fileName = audioFileName {
            // 本地文件 - 动态构建完整路径
            let documentsDirectory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            return documentsDirectory.appendingPathComponent(fileName)
        } else if let urlString = audioURLString, let url = URL(string: urlString) {
            // 远程URL
            return url
        } else {
            // 默认返回空URL（不应该发生）
            return URL(fileURLWithPath: "")
        }
    }
    
    static func == (lhs: PlaylistItem, rhs: PlaylistItem) -> Bool {
        return lhs.id == rhs.id
    }
}

// 播放列表通知
extension Notification.Name {
    static let playlistUpdated = Notification.Name("playlistUpdated")
    static let currentTrackChanged = Notification.Name("currentTrackChanged")
    static let playModeChanged = Notification.Name("playModeChanged")
}

// 循环模式
enum RepeatMode: String, Codable {
    case off = "off"           // 不循环
    case all = "all"           // 全部循环
    case one = "one"           // 单曲循环
}

class PlaylistManager {
    static let shared = PlaylistManager()
    
    private let playlistFileName = "playlist.json"
    private let documentsDirectory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    
    // 播放列表
    private(set) var playlist: [PlaylistItem] = []
    
    // 当前播放的索引
    private(set) var currentIndex: Int? = nil
    
    // 播放模式
    private(set) var repeatMode: RepeatMode = .off
    private(set) var isShuffleEnabled: Bool = false
    
    // 随机播放的历史记录（避免重复播放）
    private var shuffleHistory: [Int] = []
    
    private init() {
        loadPlaylist()
        setupNotifications()
    }
    
    // MARK: - Public Methods
    
    // 添加并播放（插入到当前播放的下一个位置）
    func addAndPlay(videoId: String, title: String, artist: String, thumbnailURL: URL?, audioURL: URL, artwork: UIImage?) {
        // 判断是本地文件还是远程URL
        let fileName: String?
        let urlString: String?
        
        if audioURL.isFileURL {
            // 本地文件 - 只保存文件名
            fileName = audioURL.lastPathComponent
            urlString = nil
        } else {
            // 远程URL - 保存URL字符串
            fileName = nil
            urlString = audioURL.absoluteString
        }
        
        let item = PlaylistItem(
            id: UUID().uuidString,
            videoId: videoId,
            title: title,
            artist: artist,
            thumbnailURL: thumbnailURL,
            audioFileName: fileName,
            audioURLString: urlString,
            addedDate: Date(),
            isParsing: false
        )
        
        // 检查是否已存在相同的视频
        if let existingIndex = playlist.firstIndex(where: { $0.videoId == videoId }) {
            // 如果是当前播放的，重新播放（确保显示播放器）
            if currentIndex == existingIndex {
                print("🎵 [播放列表] 重新播放当前音频")
                playItem(at: existingIndex)
                notifyCurrentTrackChanged()
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
    
    // 添加解析中的播放项（立即反馈，稍后更新URL）
    func addAndPlayPending(videoId: String, title: String, artist: String, thumbnailURL: URL?) -> String {
        let item = PlaylistItem(
            id: UUID().uuidString,
            videoId: videoId,
            title: title,
            artist: artist,
            thumbnailURL: thumbnailURL,
            audioFileName: nil,
            audioURLString: nil,
            addedDate: Date(),
            isParsing: true
        )
        
        // 检查是否已存在相同的视频
        if let existingIndex = playlist.firstIndex(where: { $0.videoId == videoId }) {
            // 如果是当前播放的，重新显示播放器
            if currentIndex == existingIndex {
                print("🎵 [播放列表] 重新显示当前音频")
                let existingItem = playlist[existingIndex]
                showPlayerWithParsingState(item: existingItem)
                return existingItem.id
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
        
        // 显示播放器，显示解析中状态
        showPlayerWithParsingState(item: item)
        
        print("🎵 [播放列表] 添加解析中的项: \(title), 当前位置: \(currentIndex!)")
        return item.id
    }
    
    // 更新播放项的音频URL并开始播放
    func updateItemAudioURLAndPlay(itemId: String, audioURL: URL) {
        guard let index = playlist.firstIndex(where: { $0.id == itemId }) else {
            print("❌ [播放列表] 找不到播放项: \(itemId)")
            return
        }
        
        var item = playlist[index]
        
        // 更新URL
        if audioURL.isFileURL {
            item.audioURLString = nil
        } else {
            item.audioURLString = audioURL.absoluteString
        }
        item.isParsing = false
        
        playlist[index] = item
        savePlaylist()
        notifyPlaylistUpdated()
        
        // 如果是当前项，开始播放
        if currentIndex == index {
            playItem(at: index)
        }
        
        print("🎵 [播放列表] 更新并播放: \(item.title)")
    }
    
    // 显示播放器（解析中状态）
    private func showPlayerWithParsingState(item: PlaylistItem) {
        // 更新全局播放器信息，显示解析中
        GlobalPlayerContainer.shared.updateInfo(
            title: item.title,
            artist: "解析链接中...",
            artwork: nil,
            video: nil
        )
        
        // 通知当前曲目变化
        notifyCurrentTrackChanged()
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
        guard playlist.count > 0 else { return false }
        
        // 如果开启了随机，随机播放
        if isShuffleEnabled {
            playRandomNext()
            return true
        }
        
        guard let current = currentIndex else {
            // 如果没有当前索引，播放第一首
            play(at: 0)
            return true
        }
        
        let nextIndex = current + 1
        
        if nextIndex < playlist.count {
            play(at: nextIndex)
            return true
        }
        
        // 已经是最后一首
        if repeatMode == .all {
            // 全部循环 - 从头开始
            play(at: 0)
            print("🎵 [播放列表] 循环到第一首")
            return true
        }
        
        print("🎵 [播放列表] 已经是最后一首")
        return false
    }
    
    // 播放上一首
    func playPrevious() -> Bool {
        guard playlist.count > 0 else { return false }
        
        // 如果开启了随机，随机播放
        if isShuffleEnabled {
            playRandomPrevious()
            return true
        }
        
        guard let current = currentIndex else {
            // 如果没有当前索引，播放最后一首
            play(at: playlist.count - 1)
            return true
        }
        
        let previousIndex = current - 1
        
        if previousIndex >= 0 {
            play(at: previousIndex)
            return true
        }
        
        // 已经是第一首
        if repeatMode == .all {
            // 全部循环 - 跳到最后一首
            play(at: playlist.count - 1)
            print("🎵 [播放列表] 循环到最后一首")
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
    
    // 通过itemId移除播放项
    func removeItem(byId itemId: String) {
        guard let index = playlist.firstIndex(where: { $0.id == itemId }) else {
            print("❌ [播放列表] 找不到播放项: \(itemId)")
            return
        }
        remove(at: index)
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
    
    // 切换循环模式
    func toggleRepeatMode() -> RepeatMode {
        switch repeatMode {
        case .off:
            repeatMode = .all
        case .all:
            repeatMode = .one
        case .one:
            repeatMode = .off
        }
        savePlaylist()
        notifyPlayModeChanged()
        print("🔁 [播放模式] 循环: \(repeatMode.rawValue)")
        return repeatMode
    }
    
    // 切换随机模式
    func toggleShuffle() -> Bool {
        isShuffleEnabled.toggle()
        if !isShuffleEnabled {
            shuffleHistory.removeAll()
        }
        savePlaylist()
        notifyPlayModeChanged()
        print("🔀 [播放模式] 随机: \(isShuffleEnabled)")
        return isShuffleEnabled
    }
    
    // 获取循环模式
    func getRepeatMode() -> RepeatMode {
        return repeatMode
    }
    
    // 获取随机模式
    func getShuffleEnabled() -> Bool {
        return isShuffleEnabled
    }
    
    // MARK: - Private Methods
    
    private func playItem(at index: Int) {
        let item = playlist[index]
        
        // 如果正在解析，只显示状态，不播放
        if item.isParsing {
            GlobalPlayerContainer.shared.updateInfo(
                title: item.title,
                artist: "解析链接中...",
                artwork: nil,
                video: nil
            )
            print("⏳ [播放列表] 等待解析完成: \(item.title)")
            return
        }
        
        // 检查是否有有效的音频URL
        guard let audioURL = item.audioURL else {
            print("❌ [播放列表] 无效的音频URL: \(item.title)")
            return
        }
        
        // 加载缩略图（全部异步）
        var artwork: UIImage?
        if let thumbnailURL = item.thumbnailURL {
            if thumbnailURL.isFileURL {
                // 本地文件也用异步加载
                DispatchQueue.global(qos: .userInitiated).async {
                    if let data = try? Data(contentsOf: thumbnailURL),
                       let image = UIImage(data: data) {
                        DispatchQueue.main.async {
                            GlobalPlayerContainer.shared.updateInfo(
                                title: item.title,
                                artist: item.artist,
                                artwork: image,
                                video: nil
                            )
                        }
                    }
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
            url: audioURL,
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
        
        // 单曲循环
        if repeatMode == .one {
            guard let index = currentIndex else { return }
            playItem(at: index)
            return
        }
        
        // 随机播放
        if isShuffleEnabled {
            playRandomNext()
            return
        }
        
        // 顺序播放
        if let current = currentIndex {
            let nextIndex = current + 1
            
            if nextIndex < playlist.count {
                play(at: nextIndex)
            } else if repeatMode == .all {
                // 全部循环 - 回到第一首
                play(at: 0)
            } else {
                // 不循环 - 停止播放
                print("🎵 [播放列表] 已播放完所有音频")
            }
        }
    }
    
    // 随机播放下一首
    private func playRandomNext() {
        guard playlist.count > 0 else { return }
        
        // 如果只有一首歌，重复播放
        if playlist.count == 1 {
            playItem(at: 0)
            return
        }
        
        // 如果已经播放完所有歌曲，清空历史
        if shuffleHistory.count >= playlist.count {
            shuffleHistory.removeAll()
        }
        
        // 获取未播放过的索引
        var availableIndices = Array(0..<playlist.count)
        availableIndices = availableIndices.filter { !shuffleHistory.contains($0) }
        
        // 如果没有可用的，清空历史重新开始
        if availableIndices.isEmpty {
            shuffleHistory.removeAll()
            availableIndices = Array(0..<playlist.count)
        }
        
        // 随机选择一个
        if let randomIndex = availableIndices.randomElement() {
            shuffleHistory.append(randomIndex)
            play(at: randomIndex)
        }
    }
    
    // 随机播放上一首
    private func playRandomPrevious() {
        guard playlist.count > 0 else { return }
        
        // 如果只有一首歌，重复播放
        if playlist.count == 1 {
            playItem(at: 0)
            return
        }
        
        // 随机选择一个不同的索引
        var availableIndices = Array(0..<playlist.count)
        
        // 排除当前播放的索引
        if let current = currentIndex {
            availableIndices.removeAll { $0 == current }
        }
        
        // 随机选择一个
        if let randomIndex = availableIndices.randomElement() {
            play(at: randomIndex)
        }
    }
    
    private func notifyPlaylistUpdated() {
        NotificationCenter.default.post(name: .playlistUpdated, object: nil)
    }
    
    private func notifyCurrentTrackChanged() {
        NotificationCenter.default.post(name: .currentTrackChanged, object: nil)
    }
    
    private func notifyPlayModeChanged() {
        NotificationCenter.default.post(name: .playModeChanged, object: nil, userInfo: [
            "repeatMode": repeatMode.rawValue,
            "isShuffleEnabled": isShuffleEnabled
        ])
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
                    "audioFileName": item.audioFileName ?? "",
                    "audioURLString": item.audioURLString ?? "",
                    "addedDate": ISO8601DateFormatter().string(from: item.addedDate)
                ]
            },
            "currentIndex": currentIndex ?? -1,
            "repeatMode": repeatMode.rawValue,
            "isShuffleEnabled": isShuffleEnabled
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
                    
                    // 兼容旧格式和新格式
                    let audioFileName = dict["audioFileName"] as? String
                    let audioURLString = dict["audioURLString"] as? String
                    
                    // 如果都为空，尝试从旧的 audioURL 字段读取
                    var finalFileName: String? = audioFileName
                    var finalURLString: String? = audioURLString
                    
                    if audioFileName == nil && audioURLString == nil {
                        // 兼容旧数据格式
                        if let oldAudioURLString = dict["audioURL"] as? String,
                           let oldURL = URL(string: oldAudioURLString) {
                            if oldURL.isFileURL {
                                finalFileName = oldURL.lastPathComponent
                            } else {
                                finalURLString = oldAudioURLString
                            }
                        }
                    }
                    
                    return PlaylistItem(
                        id: id,
                        videoId: videoId,
                        title: title,
                        artist: artist,
                        thumbnailURL: thumbnailURL,
                        audioFileName: finalFileName,
                        audioURLString: finalURLString,
                        addedDate: addedDate,
                        isParsing: dict["isParsing"] as? Bool ?? false
                    )
                }
            }
            
            // 加载当前索引
            if let index = data["currentIndex"] as? Int, index >= 0 {
                currentIndex = index
            }
            
            // 加载播放模式
            if let repeatModeString = data["repeatMode"] as? String,
               let mode = RepeatMode(rawValue: repeatModeString) {
                repeatMode = mode
            }
            
            if let shuffle = data["isShuffleEnabled"] as? Bool {
                isShuffleEnabled = shuffle
            }
            
            print("💾 [播放列表] 已加载: \(playlist.count) 首, 当前索引: \(currentIndex ?? -1), 循环: \(repeatMode.rawValue), 随机: \(isShuffleEnabled)")
        } catch {
            print("❌ [播放列表] 加载失败: \(error.localizedDescription)")
        }
    }
}
