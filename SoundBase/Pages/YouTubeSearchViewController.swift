//
//  YouTubeSearchViewController.swift
//  SoundBase
//
//  Created by samma on 2026/1/22.
//

import UIKit
import SnapKit
import YouTubeKit

struct VideoSearchResult {
    let videoId: String
    let title: String
    let channelTitle: String
    let thumbnailURL: URL?
}

class YouTubeSearchViewController: UIViewController {
    
    private var searchResults: [VideoSearchResult] = []
    
    private lazy var searchBar: UISearchBar = {
        let bar = UISearchBar()
        bar.placeholder = "搜索YouTube视频"
        bar.delegate = self
        return bar
    }()
    
    private lazy var tableView: UITableView = {
        let table = UITableView()
        table.delegate = self
        table.dataSource = self
        table.register(VideoCell.self, forCellReuseIdentifier: "VideoCell")
        table.rowHeight = 100
        table.keyboardDismissMode = .onDrag
        return table
    }()
    
    private lazy var activityIndicator: UIActivityIndicatorView = {
        let indicator = UIActivityIndicatorView(style: .large)
        indicator.hidesWhenStopped = true
        return indicator
    }()
    
    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
    }
    
    private func setupUI() {
        title = "YouTube音频搜索"
        view.backgroundColor = .systemBackground
        
        view.addSubview(searchBar)
        view.addSubview(tableView)
        view.addSubview(activityIndicator)
        
        searchBar.snp.makeConstraints { make in
            make.top.equalTo(view.safeAreaLayoutGuide)
            make.left.right.equalToSuperview()
        }
        
        tableView.snp.makeConstraints { make in
            make.top.equalTo(searchBar.snp.bottom)
            make.left.right.bottom.equalToSuperview()
        }
        
        activityIndicator.snp.makeConstraints { make in
            make.center.equalToSuperview()
        }
    }
    
    private func searchYouTube(keyword: String) {
        guard !keyword.isEmpty else { return }
        
        activityIndicator.startAnimating()
        
        Task {
            do {
                let results = try await performYouTubeSearch(query: keyword)
                
                await MainActor.run {
                    self.searchResults = results
                    self.tableView.reloadData()
                    self.activityIndicator.stopAnimating()
                }
            } catch {
                await MainActor.run {
                    self.activityIndicator.stopAnimating()
                    self.showAlert(title: "搜索失败", message: error.localizedDescription)
                }
            }
        }
    }
    
    private func performYouTubeSearch(query: String) async throws -> [VideoSearchResult] {
        let encodedQuery = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        let urlString = "https://www.youtube.com/results?search_query=\(encodedQuery)"
        
        guard let url = URL(string: urlString) else {
            throw NSError(domain: "Search", code: -1, userInfo: [NSLocalizedDescriptionKey: "无效的URL"])
        }
        
        var request = URLRequest(url: url)
        request.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36", forHTTPHeaderField: "User-Agent")
        
        let (data, _) = try await URLSession.shared.data(for: request)
        guard let html = String(data: data, encoding: .utf8) else {
            throw NSError(domain: "Search", code: -1, userInfo: [NSLocalizedDescriptionKey: "解析失败"])
        }
        
        return parseSearchResults(from: html)
    }
    
    private func parseSearchResults(from html: String) -> [VideoSearchResult] {
        var results: [VideoSearchResult] = []
        
        // 匹配 videoRenderer 格式，频道名在 longBylineText
        let pattern = #"\{\"videoRenderer\":\{\"videoId\":\"([^\"]+)\".*?\"title\":\{\"runs\":\[\{\"text\":\"([^\"]+)\".*?\"longBylineText\":\{\"runs\":\[\{\"text\":\"([^\"]+)\""#
        
        if let regex = try? NSRegularExpression(pattern: pattern, options: .dotMatchesLineSeparators) {
            let nsString = html as NSString
            let matches = regex.matches(in: html, options: [], range: NSRange(location: 0, length: nsString.length))
            
            var seen = Set<String>()
            for match in matches {
                if match.numberOfRanges >= 4 {
                    let videoId = nsString.substring(with: match.range(at: 1))
                    let title = nsString.substring(with: match.range(at: 2))
                        .replacingOccurrences(of: "\\u0026", with: "&")
                        .replacingOccurrences(of: "\\/", with: "/")
                        .replacingOccurrences(of: "\\u003c", with: "<")
                        .replacingOccurrences(of: "\\u003e", with: ">")
                    let channel = nsString.substring(with: match.range(at: 3))
                    
                    if !seen.contains(videoId) {
                        seen.insert(videoId)
                        let thumbnailURL = URL(string: "https://i.ytimg.com/vi/\(videoId)/hqdefault.jpg")
                        let result = VideoSearchResult(videoId: videoId, title: title, channelTitle: channel, thumbnailURL: thumbnailURL)
                        results.append(result)
                    }
                }
            }
        }
        
        return results
    }
    
    private func showAlert(title: String, message: String) {
        let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "确定", style: .default))
        present(alert, animated: true)
    }
}

// MARK: - UISearchBarDelegate
extension YouTubeSearchViewController: UISearchBarDelegate {
    func searchBarSearchButtonClicked(_ searchBar: UISearchBar) {
        searchBar.resignFirstResponder()
        if let text = searchBar.text {
            searchYouTube(keyword: text)
        }
    }
}

// MARK: - UITableViewDelegate, UITableViewDataSource
extension YouTubeSearchViewController: UITableViewDelegate, UITableViewDataSource {
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return searchResults.count
    }
    
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "VideoCell", for: indexPath) as! VideoCell
        let video = searchResults[indexPath.row]
        cell.configure(with: video)
        return cell
    }
    
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        let video = searchResults[indexPath.row]
        showActionSheet(for: video)
    }
    
    private func showActionSheet(for video: VideoSearchResult) {
        let alert = UIAlertController(title: video.title, message: "请选择操作", preferredStyle: .actionSheet)
        
        alert.addAction(UIAlertAction(title: "播放", style: .default) { [weak self] _ in
            self?.playAudio(video: video)
        })
        
        alert.addAction(UIAlertAction(title: "下载", style: .default) { [weak self] _ in
            self?.downloadAudio(video: video)
        })
        
        alert.addAction(UIAlertAction(title: "取消", style: .cancel))
        
        if let popoverController = alert.popoverPresentationController {
            popoverController.sourceView = self.view
            popoverController.sourceRect = CGRect(x: self.view.bounds.midX, y: self.view.bounds.midY, width: 0, height: 0)
            popoverController.permittedArrowDirections = []
        }
        
        present(alert, animated: true)
    }
    
    private func playAudio(video: VideoSearchResult) {
        Task {
            do {
                let audioURL = try await extractAudioURL(for: video)
                
                await MainActor.run {
                    self.startPlaying(video: video, audioURL: audioURL)
                }
            } catch {
                await MainActor.run {
                    self.showAlert(title: "解析失败", message: error.localizedDescription)
                }
            }
        }
    }
    
    private func downloadAudio(video: VideoSearchResult) {
        // 立即创建解析中的下载任务
        AudioFileManager.shared.createParsingTask(
            videoId: video.videoId,
            title: video.title,
            channelTitle: video.channelTitle,
            thumbnailURL: video.thumbnailURL
        )
        
        // 播放掉落动画
        if let cell = findCell(for: video) {
            playDownloadAnimation(from: cell)
        }
        
        // 异步解析下载链接
        Task {
            do {
                let audioURL = try await extractAudioURL(for: video)
                
                await MainActor.run {
                    self.startDownload(video: video, audioURL: audioURL)
                }
            } catch {
                // 解析失败，移除解析任务
                AudioFileManager.shared.removeParsingTask(videoId: video.videoId)
                
                await MainActor.run {
                    self.showAlert(title: "解析失败", message: error.localizedDescription)
                }
            }
        }
    }
    
    // 查找视频对应的cell
    private func findCell(for video: VideoSearchResult) -> VideoCell? {
        guard let index = searchResults.firstIndex(where: { $0.videoId == video.videoId }) else {
            return nil
        }
        let indexPath = IndexPath(row: index, section: 0)
        return tableView.cellForRow(at: indexPath) as? VideoCell
    }
    
    // 播放下载动画
    private func playDownloadAnimation(from cell: VideoCell) {
        guard let thumbnailImage = cell.thumbnailImageView.image,
              let tabBar = tabBarController?.tabBar,
              let window = view.window else {
            return
        }
        
        // 创建动画图片视图
        let animationView = UIImageView(image: thumbnailImage)
        animationView.contentMode = .scaleAspectFill
        animationView.clipsToBounds = true
        animationView.layer.cornerRadius = 8
        
        // 设置初始位置（缩略图位置）
        let startFrame = cell.thumbnailImageView.convert(cell.thumbnailImageView.bounds, to: window)
        animationView.frame = startFrame
        window.addSubview(animationView)
        
        // 设置目标位置（TabBar设置图标）
        let settingsTabIndex = 2
        let tabBarItemWidth = tabBar.bounds.width / CGFloat(tabBar.items?.count ?? 3)
        let settingsIconX = tabBarItemWidth * CGFloat(settingsTabIndex) + tabBarItemWidth / 2
        let settingsIconY = tabBar.frame.minY + tabBar.bounds.height / 2
        let endPoint = CGPoint(x: settingsIconX, y: settingsIconY)
        
        // 执行动画
        UIView.animate(withDuration: 0.6, delay: 0, options: .curveEaseIn, animations: {
            animationView.frame = CGRect(x: endPoint.x - 20, y: endPoint.y - 20, width: 40, height: 40)
            animationView.alpha = 0.3
        }) { _ in
            animationView.removeFromSuperview()
        }
    }
    
    private func extractAudioURL(for video: VideoSearchResult) async throws -> URL {
        let youtube = YouTube(videoID: video.videoId)
        let streams = try await youtube.streams
        
        // 优先选择可原生播放的音频流
        let nativePlayableAudioStreams = streams
            .filterAudioOnly()
            .filter { $0.isNativelyPlayable }
        
        if let stream = nativePlayableAudioStreams.highestAudioBitrateStream() {
            return stream.url
        } else if let stream = streams.filterAudioOnly().highestAudioBitrateStream() {
            return stream.url
        } else {
            throw NSError(domain: "AudioExtraction", code: -1, userInfo: [NSLocalizedDescriptionKey: "未找到音频流"])
        }
    }
    
    private func startPlaying(video: VideoSearchResult, audioURL: URL) {
        // 添加到播放列表并播放（不传artwork，让PlaylistManager异步加载）
        PlaylistManager.shared.addAndPlay(
            videoId: video.videoId,
            title: video.title,
            artist: video.channelTitle,
            thumbnailURL: video.thumbnailURL,
            audioURL: audioURL,
            artwork: nil
        )
    }
    
    private func startDownload(video: VideoSearchResult, audioURL: URL) {
        // 开始下载
        AudioFileManager.shared.saveAudio(
            videoId: video.videoId,
            title: video.title,
            channelTitle: video.channelTitle,
            thumbnailURL: video.thumbnailURL,
            sourceURL: audioURL
        ) { [weak self] result in
            DispatchQueue.main.async {
                switch result {
                case .success:
                    break // 静默下载，状态在下载管理页面显示
                case .failure(let error):
                    self?.showAlert(title: "下载失败", message: error.localizedDescription)
                }
            }
        }
    }
}

// MARK: - VideoCell
class VideoCell: UITableViewCell {
    
    let thumbnailImageView: UIImageView = {
        let imageView = UIImageView()
        imageView.contentMode = .scaleAspectFill
        imageView.clipsToBounds = true
        imageView.backgroundColor = .systemGray5
        return imageView
    }()
    
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
    
    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        setupUI()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    private func setupUI() {
        contentView.addSubview(thumbnailImageView)
        contentView.addSubview(titleLabel)
        contentView.addSubview(channelLabel)
        
        thumbnailImageView.snp.makeConstraints { make in
            make.left.equalToSuperview().offset(16)
            make.centerY.equalToSuperview()
            make.width.equalTo(120)
            make.height.equalTo(68)
        }
        
        titleLabel.snp.makeConstraints { make in
            make.left.equalTo(thumbnailImageView.snp.right).offset(12)
            make.right.equalToSuperview().offset(-16)
            make.top.equalToSuperview().offset(12)
        }
        
        channelLabel.snp.makeConstraints { make in
            make.left.equalTo(titleLabel)
            make.right.equalTo(titleLabel)
            make.top.equalTo(titleLabel.snp.bottom).offset(4)
        }
    }
    
    func configure(with video: VideoSearchResult) {
        titleLabel.text = video.title
        channelLabel.text = video.channelTitle
        
        if let thumbnailURL = video.thumbnailURL {
            loadImage(from: thumbnailURL)
        }
    }
    
    private func loadImage(from url: URL) {
        URLSession.shared.dataTask(with: url) { [weak self] data, _, _ in
            guard let data = data, let image = UIImage(data: data) else { return }
            DispatchQueue.main.async {
                self?.thumbnailImageView.image = image
            }
        }.resume()
    }
}
