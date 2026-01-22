//
//  AudioFileManager.swift
//  SoundBase
//
//  Created by samma on 2026/1/22.
//

import Foundation

struct DownloadedAudio {
    let videoId: String
    let title: String
    let channelTitle: String
    let fileURL: URL
    let downloadDate: Date
    let thumbnailURL: URL?
}

class AudioFileManager {
    static let shared = AudioFileManager()
    
    private let documentsDirectory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    private let metadataFileName = "audio_metadata.json"
    
    private init() {}
    
    // 保存音频文件和元数据
    func saveAudio(videoId: String, title: String, channelTitle: String, thumbnailURL: URL?, sourceURL: URL, completion: @escaping (Result<DownloadedAudio, Error>) -> Void) {
        
        let fileName = sanitizeFileName(title) + ".m4a"
        let destinationURL = documentsDirectory.appendingPathComponent(fileName)
        
        URLSession.shared.downloadTask(with: sourceURL) { [weak self] tempURL, response, error in
            guard let self = self else { return }
            
            if let error = error {
                completion(.failure(error))
                return
            }
            
            guard let tempURL = tempURL else {
                completion(.failure(NSError(domain: "AudioFileManager", code: -1, userInfo: [NSLocalizedDescriptionKey: "临时文件不存在"])))
                return
            }
            
            do {
                if FileManager.default.fileExists(atPath: destinationURL.path) {
                    try FileManager.default.removeItem(at: destinationURL)
                }
                try FileManager.default.moveItem(at: tempURL, to: destinationURL)
                
                let audio = DownloadedAudio(
                    videoId: videoId,
                    title: title,
                    channelTitle: channelTitle,
                    fileURL: destinationURL,
                    downloadDate: Date(),
                    thumbnailURL: thumbnailURL
                )
                
                self.saveMetadata(audio: audio)
                completion(.success(audio))
            } catch {
                completion(.failure(error))
            }
        }.resume()
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
        
        let dict: [[String: Any]] = audios.map { audio in
            [
                "videoId": audio.videoId,
                "title": audio.title,
                "channelTitle": audio.channelTitle,
                "fileURL": audio.fileURL.path,
                "downloadDate": audio.downloadDate.timeIntervalSince1970,
                "thumbnailURL": audio.thumbnailURL?.absoluteString ?? ""
            ]
        }
        
        if let data = try? JSONSerialization.data(withJSONObject: dict, options: .prettyPrinted) {
            try? data.write(to: metadataURL)
        }
    }
    
    private func loadMetadata() -> [DownloadedAudio] {
        let metadataURL = documentsDirectory.appendingPathComponent(metadataFileName)
        
        guard let data = try? Data(contentsOf: metadataURL),
              let json = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            return []
        }
        
        return json.compactMap { dict in
            guard let videoId = dict["videoId"] as? String,
                  let title = dict["title"] as? String,
                  let channelTitle = dict["channelTitle"] as? String,
                  let filePath = dict["fileURL"] as? String,
                  let timestamp = dict["downloadDate"] as? TimeInterval else {
                return nil
            }
            
            let fileURL = URL(fileURLWithPath: filePath)
            guard FileManager.default.fileExists(atPath: fileURL.path) else {
                return nil
            }
            
            let thumbnailURLString = dict["thumbnailURL"] as? String
            let thumbnailURL = thumbnailURLString.flatMap { URL(string: $0) }
            
            return DownloadedAudio(
                videoId: videoId,
                title: title,
                channelTitle: channelTitle,
                fileURL: fileURL,
                downloadDate: Date(timeIntervalSince1970: timestamp),
                thumbnailURL: thumbnailURL
            )
        }
    }
    
    private func removeMetadata(videoId: String) {
        var audios = loadMetadata()
        audios.removeAll { $0.videoId == videoId }
        
        let metadataURL = documentsDirectory.appendingPathComponent(metadataFileName)
        
        let dict: [[String: Any]] = audios.map { audio in
            [
                "videoId": audio.videoId,
                "title": audio.title,
                "channelTitle": audio.channelTitle,
                "fileURL": audio.fileURL.path,
                "downloadDate": audio.downloadDate.timeIntervalSince1970,
                "thumbnailURL": audio.thumbnailURL?.absoluteString ?? ""
            ]
        }
        
        if let data = try? JSONSerialization.data(withJSONObject: dict, options: .prettyPrinted) {
            try? data.write(to: metadataURL)
        }
    }
}
