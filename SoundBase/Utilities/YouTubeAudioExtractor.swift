//
//  YouTubeAudioExtractor.swift
//  SoundBase
//
//  Created by samma on 2026/1/29.
//

import Foundation
import YouTubeKit

class YouTubeAudioExtractor {
    static let shared = YouTubeAudioExtractor()
    
    private init() {}
    
    // 根据videoId提取音频URL
    func extractAudioURL(videoId: String) async throws -> URL {
        print("🔍 [YouTube] 开始解析视频: \(videoId)")
        
        let youtube = YouTube(videoID: videoId)
        let streams = try await youtube.streams
        
        print("📺 [YouTube] 获取到 \(streams.count) 个流")
        
        // 优先选择可原生播放的音频流
        let nativePlayableAudioStreams = streams
            .filterAudioOnly()
            .filter { $0.isNativelyPlayable }
        
        if let stream = nativePlayableAudioStreams.highestAudioBitrateStream() {
            print("✅ [YouTube] 找到原生音频流 (比特率: \(stream.bitrate ?? 0))")
            return stream.url
        } else if let stream = streams.filterAudioOnly().highestAudioBitrateStream() {
            print("✅ [YouTube] 找到音频流 (比特率: \(stream.bitrate ?? 0))")
            return stream.url
        } else {
            print("❌ [YouTube] 未找到音频流")
            throw NSError(domain: "YouTubeAudioExtractor", code: -1, userInfo: [NSLocalizedDescriptionKey: "未找到音频流"])
        }
    }
    
    // 验证音频URL是否有效（简单的HEAD请求）
    func validateAudioURL(_ url: URL) async throws -> Bool {
        var request = URLRequest(url: url)
        request.httpMethod = "HEAD"
        request.timeoutInterval = 10
        
        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            if let httpResponse = response as? HTTPURLResponse {
                print("🔍 [验证] URL状态码: \(httpResponse.statusCode)")
                return httpResponse.statusCode == 200
            }
            return false
        } catch {
            print("❌ [验证] URL验证失败: \(error.localizedDescription)")
            return false
        }
    }
}
