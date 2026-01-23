//
//  AudioFileManager.swift
//  SoundBase
//
//  Created by samma on 2026/1/22.
//

import Foundation
import UIKit

struct DownloadedAudio: Codable {
    let videoId: String
    let title: String
    let channelTitle: String
    let fileName: String  // 只存储文件名，不存储绝对路径
    let downloadDate: Date
    let thumbnailURL: URL?
    
    // 动态计算文件完整路径
    var fileURL: URL {
        let documentsDirectory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return documentsDirectory.appendingPathComponent(fileName)
    }
}

// 下载任务模型
struct DownloadTask {
    let videoId: String
    let title: String
    let channelTitle: String
    let thumbnailURL: URL?
    var progress: Double
    var status: DownloadTaskStatus
    let sourceURL: URL?
    let taskIdentifier: String?
}

enum DownloadTaskStatus {
    case downloading
    case paused
    case failed(String)
}

// 失败的下载任务
struct FailedDownload: Codable {
    let videoId: String
    let title: String
    let channelTitle: String
    let thumbnailURL: URL?
    let failureDate: Date
    let errorMessage: String
}

// 下载任务状态
enum DownloadStatus {
    case downloading(progress: Double)
    case completed
    case failed(Error)
}

// 下载任务通知
extension Notification.Name {
    static let downloadProgressUpdated = Notification.Name("downloadProgressUpdated")
    static let downloadCompleted = Notification.Name("downloadCompleted")
    static let downloadFailed = Notification.Name("downloadFailed")
}

class AudioFileManager: NSObject, URLSessionDownloadDelegate {
    static let shared = AudioFileManager()
    
    private let documentsDirectory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    private let metadataFileName = "audio_metadata.json"
    private let failedDownloadsFileName = "failed_downloads.json"
    private var urlSession: URLSession!
    private var activeDownloads: [String: (completion: (Result<DownloadedAudio, Error>) -> Void, startTime: Date, videoId: String, title: String, channelTitle: String, thumbnailURL: URL?, destinationURL: URL, sourceURL: URL, task: URLSessionDownloadTask)] = [:]
    
    // 跟踪正在下载的videoId
    private var downloadingVideoIds: Set<String> = []
    
    // 暂停的下载任务 - 保存恢复数据
    private var pausedDownloads: [String: (resumeData: Data, videoId: String, title: String, channelTitle: String, thumbnailURL: URL?, sourceURL: URL)] = [:]
    
    // 失败的下载任务
    private var failedDownloads: [FailedDownload] = []
    
    override private init() {
        super.init()
        // 使用后台配置，支持退出后继续下载
        let config = URLSessionConfiguration.background(withIdentifier: "com.soundbase.download")
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 600
        config.isDiscretionary = false // 不等待最佳网络条件
        config.sessionSendsLaunchEvents = true
        urlSession = URLSession(configuration: config, delegate: self, delegateQueue: nil)
        
        print("📁 [文件管理] 文档目录: \(documentsDirectory.path)")
        print("📁 [文件管理] 元数据文件: \(documentsDirectory.appendingPathComponent(metadataFileName).path)")
        
        // 加载失败的下载任务
        loadFailedDownloads()
    }
    
    // 保存音频文件和元数据（后台下载）
    func saveAudio(videoId: String, title: String, channelTitle: String, thumbnailURL: URL?, sourceURL: URL, completion: @escaping (Result<DownloadedAudio, Error>) -> Void) {
        
        print("📥 [下载] 开始下载: \(title)")
        print("📥 [下载] 下载链接: \(sourceURL.absoluteString)")
        
        let fileName = sanitizeFileName(title) + ".m4a"
        let destinationURL = documentsDirectory.appendingPathComponent(fileName)
        
        let task = urlSession.downloadTask(with: sourceURL)
        let taskIdentifier = "\(task.taskIdentifier)"
        
        activeDownloads[taskIdentifier] = (
            completion: completion,
            startTime: Date(),
            videoId: videoId,
            title: title,
            channelTitle: channelTitle,
            thumbnailURL: thumbnailURL,
            destinationURL: destinationURL,
            sourceURL: sourceURL,
            task: task
        )
        
        // 标记为下载中
        downloadingVideoIds.insert(videoId)
        
        // 如果之前失败过，从失败列表中移除
        removeFromFailedDownloads(videoId: videoId)
        
        task.resume()
        print("📥 [下载] 下载任务已启动 (ID: \(taskIdentifier))")
        print("📥 [下载] 可以退出页面，下载将在后台继续")
    }
    
    // MARK: - URLSessionDownloadDelegate
    
    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        let taskIdentifier = "\(downloadTask.taskIdentifier)"
        guard let downloadInfo = activeDownloads[taskIdentifier] else {
            print("⚠️ [下载] 找不到任务信息: \(taskIdentifier)")
            return
        }
        
        print("📥 [下载] 下载数据完成，临时位置: \(location.path)")
        
        do {
            let destinationURL = downloadInfo.destinationURL
            
            // 如果目标文件已存在，先删除
            if FileManager.default.fileExists(atPath: destinationURL.path) {
                try FileManager.default.removeItem(at: destinationURL)
                print("📁 [文件管理] 已删除旧文件: \(destinationURL.lastPathComponent)")
            }
            
            // 移动文件到目标位置
            try FileManager.default.copyItem(at: location, to: destinationURL)
            print("📁 [文件管理] 文件已保存到: \(destinationURL.path)")
            
            // 验证文件是否存在
            if FileManager.default.fileExists(atPath: destinationURL.path) {
                print("✅ [文件管理] 文件验证成功")
            } else {
                print("❌ [文件管理] 文件验证失败")
            }
            
            let audio = DownloadedAudio(
                videoId: downloadInfo.videoId,
                title: downloadInfo.title,
                channelTitle: downloadInfo.channelTitle,
                fileName: destinationURL.lastPathComponent,  // 只存储文件名
                downloadDate: Date(),
                thumbnailURL: downloadInfo.thumbnailURL
            )
            
            // 保存元数据
            saveMetadata(audio: audio)
            
            let duration = Date().timeIntervalSince(downloadInfo.startTime)
            print("✅ [下载] 下载完成: \(downloadInfo.title) (耗时: \(String(format: "%.1f", duration))秒)")
            
            // 发送通知
            DispatchQueue.main.async {
                NotificationCenter.default.post(name: .downloadCompleted, object: audio)
                downloadInfo.completion(.success(audio))
            }
            
        } catch {
            print("❌ [下载] 文件处理失败: \(error.localizedDescription)")
            DispatchQueue.main.async {
                NotificationCenter.default.post(name: .downloadFailed, object: error)
                downloadInfo.completion(.failure(error))
            }
        }
        
        // 移除下载状态
        downloadingVideoIds.remove(downloadInfo.videoId)
        activeDownloads.removeValue(forKey: taskIdentifier)
    }
    
    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        let taskIdentifier = "\(downloadTask.taskIdentifier)"
        guard let downloadInfo = activeDownloads[taskIdentifier] else { return }
        
        let progress = Double(totalBytesWritten) / Double(totalBytesExpectedToWrite)
        let mbWritten = Double(totalBytesWritten) / 1024.0 / 1024.0
        let mbTotal = Double(totalBytesExpectedToWrite) / 1024.0 / 1024.0
        
        let elapsed = Date().timeIntervalSince(downloadInfo.startTime)
        let speed = Double(totalBytesWritten) / elapsed / 1024.0 / 1024.0 // MB/s
        
        print("📊 [下载进度] \(downloadInfo.title): \(String(format: "%.1f", progress * 100))% (\(String(format: "%.2f", mbWritten))MB/\(String(format: "%.2f", mbTotal))MB) - 速度: \(String(format: "%.2f", speed))MB/s")
        
        // 发送进度通知
        DispatchQueue.main.async {
            NotificationCenter.default.post(
                name: .downloadProgressUpdated,
                object: nil,
                userInfo: [
                    "videoId": downloadInfo.videoId,
                    "progress": progress,
                    "title": downloadInfo.title
                ]
            )
        }
    }
    
    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        let taskIdentifier = "\(task.taskIdentifier)"
        
        if let error = error {
            print("❌ [下载] 任务完成时出错: \(error.localizedDescription)")
            
            if let downloadInfo = activeDownloads[taskIdentifier] {
                // 保存失败的下载任务
                let failedDownload = FailedDownload(
                    videoId: downloadInfo.videoId,
                    title: downloadInfo.title,
                    channelTitle: downloadInfo.channelTitle,
                    thumbnailURL: downloadInfo.thumbnailURL,
                    failureDate: Date(),
                    errorMessage: error.localizedDescription
                )
                saveFailedDownload(failedDownload)
                
                DispatchQueue.main.async {
                    NotificationCenter.default.post(name: .downloadFailed, object: error)
                    downloadInfo.completion(.failure(error))
                }
                // 移除下载状态
                downloadingVideoIds.remove(downloadInfo.videoId)
                activeDownloads.removeValue(forKey: taskIdentifier)
            }
        }
    }
    
    // 后台下载完成回调
    func urlSessionDidFinishEvents(forBackgroundURLSession session: URLSession) {
        print("📥 [下载] 后台下载会话完成")
        DispatchQueue.main.async {
            // 通知应用代理后台任务完成
            if let appDelegate = UIApplication.shared.delegate as? AppDelegate,
               let completionHandler = appDelegate.backgroundCompletionHandler {
                appDelegate.backgroundCompletionHandler = nil
                completionHandler()
            }
        }
    }
    
    // 获取所有已下载的音频
    func getAllDownloadedAudios() -> [DownloadedAudio] {
        return loadMetadata()
    }
    
    // 删除音频
    func deleteAudio(_ audio: DownloadedAudio) throws {
        try FileManager.default.removeItem(at: audio.fileURL)
        removeMetadata(videoId: audio.videoId)
    }
    
    // 检查是否已下载
    func isDownloaded(videoId: String) -> DownloadedAudio? {
        return getAllDownloadedAudios().first { $0.videoId == videoId }
    }
    
    // 检查是否正在下载
    func isDownloading(videoId: String) -> Bool {
        return downloadingVideoIds.contains(videoId)
    }
    
    // 获取所有正在下载的任务
    func getActiveDownloadTasks() -> [DownloadTask] {
        var tasks: [DownloadTask] = []
        
        // 正在下载的任务
        for (taskId, downloadInfo) in activeDownloads {
            tasks.append(DownloadTask(
                videoId: downloadInfo.videoId,
                title: downloadInfo.title,
                channelTitle: downloadInfo.channelTitle,
                thumbnailURL: downloadInfo.thumbnailURL,
                progress: 0,
                status: .downloading,
                sourceURL: downloadInfo.sourceURL,
                taskIdentifier: taskId
            ))
        }
        
        // 暂停的任务
        for (videoId, pausedInfo) in pausedDownloads {
            tasks.append(DownloadTask(
                videoId: pausedInfo.videoId,
                title: pausedInfo.title,
                channelTitle: pausedInfo.channelTitle,
                thumbnailURL: pausedInfo.thumbnailURL,
                progress: 0,
                status: .paused,
                sourceURL: pausedInfo.sourceURL,
                taskIdentifier: videoId
            ))
        }
        
        return tasks
    }
    
    // 暂停下载
    func pauseDownload(videoId: String) {
        guard let (taskId, downloadInfo) = activeDownloads.first(where: { $0.value.videoId == videoId }) else {
            print("⚠️ [下载] 找不到正在下载的任务: \(videoId)")
            return
        }
        
        let task = downloadInfo.task
        task.cancel { [weak self] resumeData in
            guard let self = self, let data = resumeData else {
                print("❌ [下载] 无法获取恢复数据")
                return
            }
            
            // 保存暂停信息
            self.pausedDownloads[videoId] = (
                resumeData: data,
                videoId: downloadInfo.videoId,
                title: downloadInfo.title,
                channelTitle: downloadInfo.channelTitle,
                thumbnailURL: downloadInfo.thumbnailURL,
                sourceURL: downloadInfo.sourceURL
            )
            
            // 从活动下载中移除
            self.activeDownloads.removeValue(forKey: taskId)
            self.downloadingVideoIds.remove(videoId)
            
            print("⏸️ [下载] 已暂停: \(downloadInfo.title)")
            
            DispatchQueue.main.async {
                NotificationCenter.default.post(
                    name: .downloadProgressUpdated,
                    object: nil,
                    userInfo: ["videoId": videoId, "status": "paused"]
                )
            }
        }
    }
    
    // 继续下载
    func resumeDownload(videoId: String, completion: @escaping (Result<DownloadedAudio, Error>) -> Void) {
        guard let pausedInfo = pausedDownloads[videoId] else {
            print("⚠️ [下载] 找不到暂停的任务: \(videoId)")
            return
        }
        
        let fileName = sanitizeFileName(pausedInfo.title) + ".m4a"
        let destinationURL = documentsDirectory.appendingPathComponent(fileName)
        
        let task = urlSession.downloadTask(withResumeData: pausedInfo.resumeData)
        let taskIdentifier = "\(task.taskIdentifier)"
        
        activeDownloads[taskIdentifier] = (
            completion: completion,
            startTime: Date(),
            videoId: pausedInfo.videoId,
            title: pausedInfo.title,
            channelTitle: pausedInfo.channelTitle,
            thumbnailURL: pausedInfo.thumbnailURL,
            destinationURL: destinationURL,
            sourceURL: pausedInfo.sourceURL,
            task: task
        )
        
        downloadingVideoIds.insert(videoId)
        pausedDownloads.removeValue(forKey: videoId)
        
        task.resume()
        print("▶️ [下载] 已继续: \(pausedInfo.title)")
        
        DispatchQueue.main.async {
            NotificationCenter.default.post(
                name: .downloadProgressUpdated,
                object: nil,
                userInfo: ["videoId": videoId, "status": "resumed"]
            )
        }
    }
    
    // 取消下载
    func cancelDownload(videoId: String) {
        // 从活动下载中取消
        if let (taskId, downloadInfo) = activeDownloads.first(where: { $0.value.videoId == videoId }) {
            downloadInfo.task.cancel()
            activeDownloads.removeValue(forKey: taskId)
            downloadingVideoIds.remove(videoId)
            print("❌ [下载] 已取消: \(downloadInfo.title)")
        }
        
        // 从暂停列表中移除
        if pausedDownloads.removeValue(forKey: videoId) != nil {
            print("❌ [下载] 已从暂停列表移除: \(videoId)")
        }
    }
    
    // 获取所有失败的下载任务
    func getFailedDownloads() -> [FailedDownload] {
        return failedDownloads
    }
    
    // 重试下载
    func retryDownload(_ failedDownload: FailedDownload, sourceURL: URL, completion: @escaping (Result<DownloadedAudio, Error>) -> Void) {
        saveAudio(
            videoId: failedDownload.videoId,
            title: failedDownload.title,
            channelTitle: failedDownload.channelTitle,
            thumbnailURL: failedDownload.thumbnailURL,
            sourceURL: sourceURL,
            completion: completion
        )
    }
    
    // 移除失败的下载任务
    func removeFailedDownload(_ failedDownload: FailedDownload) {
        removeFromFailedDownloads(videoId: failedDownload.videoId)
    }
    
    // 一键清理失败的下载
    func clearAllFailedDownloads() {
        failedDownloads.removeAll()
        saveFailedDownloads()
        print("🧹 [清理] 已清理所有失败的下载")
    }
    
    // 一键清理已完成的下载
    func clearAllCompletedDownloads() throws {
        let audios = getAllDownloadedAudios()
        for audio in audios {
            try? FileManager.default.removeItem(at: audio.fileURL)
        }
        
        let metadataURL = documentsDirectory.appendingPathComponent(metadataFileName)
        try? FileManager.default.removeItem(at: metadataURL)
        
        print("🧹 [清理] 已清理所有已完成的下载")
    }
    
    // MARK: - Private Methods
    
    private func sanitizeFileName(_ fileName: String) -> String {
        let invalidCharacters = CharacterSet(charactersIn: ":/\\?%*|\"<>")
        return fileName
            .components(separatedBy: invalidCharacters)
            .joined(separator: "-")
            .trimmingCharacters(in: .whitespaces)
    }
    
    private func saveMetadata(audio: DownloadedAudio) {
        var audios = loadMetadata()
        audios.removeAll { $0.videoId == audio.videoId }
        audios.append(audio)
        
        let metadataURL = documentsDirectory.appendingPathComponent(metadataFileName)
        
        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = .prettyPrinted
            let data = try encoder.encode(audios)
            try data.write(to: metadataURL, options: .atomic)
            
            print("💾 [持久化] 元数据已保存: \(audios.count) 个音频")
            print("💾 [持久化] 文件路径: \(metadataURL.path)")
            
            // 验证保存
            if FileManager.default.fileExists(atPath: metadataURL.path) {
                let fileSize = try? FileManager.default.attributesOfItem(atPath: metadataURL.path)[.size] as? Int64
                print("💾 [持久化] 文件大小: \(fileSize ?? 0) bytes")
            }
        } catch {
            print("❌ [持久化] 保存失败: \(error.localizedDescription)")
        }
    }
    
    private func loadMetadata() -> [DownloadedAudio] {
        let metadataURL = documentsDirectory.appendingPathComponent(metadataFileName)
        
        print("💾 [持久化] 尝试加载元数据: \(metadataURL.path)")
        
        guard FileManager.default.fileExists(atPath: metadataURL.path) else {
            print("💾 [持久化] 元数据文件不存在，返回空数组")
            return []
        }
        
        do {
            let data = try Data(contentsOf: metadataURL)
            
            // 检查文件是否为空
            if data.isEmpty {
                print("⚠️ [持久化] 元数据文件为空，删除并返回空数组")
                try? FileManager.default.removeItem(at: metadataURL)
                return []
            }
            
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let audios = try decoder.decode([DownloadedAudio].self, from: data)
            
            // 验证文件是否真实存在
            let validAudios = audios.filter { audio in
                let exists = FileManager.default.fileExists(atPath: audio.fileURL.path)
                if !exists {
                    print("⚠️ [持久化] 音频文件不存在: \(audio.fileURL.path)")
                }
                return exists
            }
            
            print("💾 [持久化] 成功加载 \(validAudios.count) 个音频 (原始: \(audios.count))")
            
            // 如果有文件被删除，更新元数据
            if validAudios.count < audios.count {
                let encoder = JSONEncoder()
                encoder.dateEncodingStrategy = .iso8601
                encoder.outputFormatting = .prettyPrinted
                if let data = try? encoder.encode(validAudios) {
                    try? data.write(to: metadataURL, options: .atomic)
                    print("💾 [持久化] 已清理无效记录")
                }
            }
            
            return validAudios
        } catch let error as DecodingError {
            print("❌ [持久化] JSON解码失败: \(error)")
            print("⚠️ [持久化] 元数据文件损坏，删除并返回空数组")
            try? FileManager.default.removeItem(at: metadataURL)
            return []
        } catch {
            print("❌ [持久化] 加载失败: \(error.localizedDescription)")
            print("⚠️ [持久化] 删除损坏的元数据文件")
            try? FileManager.default.removeItem(at: metadataURL)
            return []
        }
    }
    
    private func removeMetadata(videoId: String) {
        var audios = loadMetadata()
        audios.removeAll { $0.videoId == videoId }
        
        let metadataURL = documentsDirectory.appendingPathComponent(metadataFileName)
        
        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = .prettyPrinted
            let data = try encoder.encode(audios)
            try data.write(to: metadataURL, options: .atomic)
            print("💾 [持久化] 已删除音频元数据: \(videoId)")
        } catch {
            print("❌ [持久化] 删除元数据失败: \(error.localizedDescription)")
        }
    }
    
    // MARK: - Failed Downloads Management
    
    private func saveFailedDownload(_ failedDownload: FailedDownload) {
        failedDownloads.removeAll { $0.videoId == failedDownload.videoId }
        failedDownloads.append(failedDownload)
        saveFailedDownloads()
    }
    
    private func removeFromFailedDownloads(videoId: String) {
        failedDownloads.removeAll { $0.videoId == videoId }
        saveFailedDownloads()
    }
    
    private func saveFailedDownloads() {
        let fileURL = documentsDirectory.appendingPathComponent(failedDownloadsFileName)
        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = .prettyPrinted
            let data = try encoder.encode(failedDownloads)
            try data.write(to: fileURL, options: .atomic)
            print("💾 [持久化] 失败任务已保存: \(failedDownloads.count) 个")
        } catch {
            print("❌ [持久化] 保存失败任务出错: \(error.localizedDescription)")
        }
    }
    
    private func loadFailedDownloads() {
        let fileURL = documentsDirectory.appendingPathComponent(failedDownloadsFileName)
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            print("💾 [持久化] 失败任务文件不存在")
            return
        }
        
        do {
            let data = try Data(contentsOf: fileURL)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            failedDownloads = try decoder.decode([FailedDownload].self, from: data)
            print("💾 [持久化] 成功加载 \(failedDownloads.count) 个失败任务")
        } catch {
            print("❌ [持久化] 加载失败任务出错: \(error.localizedDescription)")
            failedDownloads = []
        }
    }
}
