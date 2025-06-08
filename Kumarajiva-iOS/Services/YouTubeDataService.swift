import Foundation
import Combine

/*
 使用 yt-dlp 后端服务替代 YouTube Data API v3
 
 后端服务提供的API端点：
 - GET /api/channel/info?id=CHANNEL_ID_OR_USERNAME     # 获取频道信息
 - GET /api/channel/videos?id=CHANNEL_ID&limit=20      # 获取频道视频列表
 - GET /api/video/info?id=VIDEO_ID                     # 获取视频详细信息
 - GET /api/search/channel?q=QUERY&limit=10            # 搜索频道
 
 优势：
 - 无API配额限制
 - 支持多种频道标识格式(@username, 频道ID等)
 - 自动缓存管理
 - 更稳定可靠
 */

@MainActor
class YouTubeDataService: ObservableObject {
    static let shared = YouTubeDataService()
    
    @Published var youtubers: [YouTuber] = []
    @Published var isLoading = false
    @Published var errorMessage: String?
    
    private let persistentStorage = PersistentStorageManager.shared
    private var cancellables = Set<AnyCancellable>()
    
    // 后端服务配置
    private let backendBaseURL: String
    
    // 配置更长的超时时间的URLSession
    private lazy var urlSession: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30.0  // 请求超时30秒
        config.timeoutIntervalForResource = 60.0 // 资源超时60秒
        return URLSession(configuration: config)
    }()
    
    private init() {
        // 从配置文件读取后端服务地址
        if let path = Bundle.main.path(forResource: "Config", ofType: "plist"),
           let config = NSDictionary(contentsOfFile: path) {
            self.backendBaseURL = config["BackendBaseURL"] as? String ?? "http://localhost:5000"
        } else {
            self.backendBaseURL = "http://localhost:5000"
            print("📺 [YouTubeService] 警告：无法读取配置文件，使用默认后端地址")
        }
        
        print("📺 [YouTubeService] 初始化完成，后端地址: \(backendBaseURL)")
        
        loadYouTubers()
        
        // 监听网络状态变化
        NetworkMonitor.shared.$isConnected
            .sink { [weak self] isConnected in
                if isConnected {
                    Task {
                        await self?.refreshAllYouTubers()
                    }
                }
            }
            .store(in: &cancellables)
    }
    
    // MARK: - 数据加载和保存
    
    private func loadYouTubers() {
        print("📺 [YouTubeService] 开始加载YouTuber数据")
        do {
            youtubers = try persistentStorage.loadYouTubers()
            print("📺 [YouTubeService] 成功加载 \(youtubers.count) 个YouTuber")
        } catch {
            print("📺 [YouTubeService] 加载YouTuber失败: \(error)")
            youtubers = []
        }
    }
    
    private func saveYouTubers() {
        do {
            try persistentStorage.saveYouTubers(youtubers)
            print("📺 [YouTubeService] YouTuber数据保存成功")
        } catch {
            print("📺 [YouTubeService] YouTuber数据保存失败: \(error)")
            errorMessage = "保存数据失败: \(error.localizedDescription)"
        }
    }
    
    // MARK: - 订阅管理
    
    func subscribeToYouTuber(channelId: String) async throws {
        print("📺 [YouTubeService] 开始订阅YouTuber: \(channelId)")
        
        // 检查是否已经订阅
        if youtubers.contains(where: { $0.channelId == channelId }) {
            throw YouTubeError.alreadySubscribed
        }
        
        isLoading = true
        errorMessage = nil
        
        do {
            // 获取频道信息
            let youtuber = try await fetchYouTuberInfo(channelId: channelId)
            
            // 添加到订阅列表并立即保存
            youtubers.append(youtuber)
            saveYouTubers()
            
            print("📺 [YouTubeService] 订阅成功: \(youtuber.title)")
            
            // 设置loading状态为false，让UI显示YouTuber
            isLoading = false
            
            // 在后台获取视频列表，不阻塞UI
            Task.detached { [weak self] in
                await self?.refreshYouTuberVideos(youtuber)
            }
            
        } catch {
            print("📺 [YouTubeService] 订阅失败: \(error)")
            
            // 优化错误信息
            if let youtubeError = error as? YouTubeError {
                switch youtubeError {
                case .channelNotFound:
                    errorMessage = "找不到该YouTuber，请检查频道ID或用户名是否正确"
                case .alreadySubscribed:
                    errorMessage = "已经订阅了该YouTuber"
                case .networkError:
                    errorMessage = "网络连接错误，请检查网络并重试"
                default:
                    errorMessage = "订阅失败: \(error.localizedDescription)"
                }
            } else {
                errorMessage = "订阅失败: \(error.localizedDescription)"
            }
            
            isLoading = false
            throw error
        }
    }
    
    func unsubscribeFromYouTuber(_ youtuber: YouTuber) throws {
        print("📺 [YouTubeService] 取消订阅: \(youtuber.title)")
        
        youtubers.removeAll { $0.channelId == youtuber.channelId }
        saveYouTubers()
    }
    
    // MARK: - 后端API调用
    
    private func fetchYouTuberInfo(channelId: String) async throws -> YouTuber {
        print("📺 [YouTubeService] 获取频道信息: \(channelId)")
        
        // 构建API请求URL
        guard var components = URLComponents(string: "\(backendBaseURL)/api/channel/info") else {
            throw YouTubeError.apiError("无效的后端URL")
        }
        
        components.queryItems = [
            URLQueryItem(name: "id", value: channelId)
        ]
        
        guard let url = components.url else {
            throw YouTubeError.apiError("无法构建请求URL")
        }
        
        print("📺 [YouTubeService] 请求URL: \(url.absoluteString)")
        
        do {
            let (data, response) = try await urlSession.data(from: url)
            
            // 检查HTTP响应状态
            if let httpResponse = response as? HTTPURLResponse {
                print("📺 [YouTubeService] HTTP状态码: \(httpResponse.statusCode)")
                
                if httpResponse.statusCode != 200 {
                    // 尝试解析错误信息
                    if let errorData = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                       let errorMessage = errorData["error"] as? String {
                        if errorMessage.contains("频道不存在") || errorMessage.contains("无法访问") {
                            throw YouTubeError.channelNotFound
                        } else {
                            throw YouTubeError.apiError(errorMessage)
                        }
                    }
                    throw YouTubeError.apiError("HTTP \(httpResponse.statusCode)")
                }
            }
            
            // 解析响应数据
            let channelData = try JSONDecoder().decode(BackendChannelInfo.self, from: data)
            
            print("📺 [YouTubeService] 成功获取频道信息: \(channelData.title)")
            
            let youtuber = YouTuber(
                channelId: channelData.channel_id,
                title: channelData.title,
                description: channelData.description,
                thumbnailURL: channelData.thumbnail,
                subscriberCount: formatSubscriberCount(channelData.subscriber_count),
                videoCount: channelData.video_count ?? 0,
                videos: [], // 初始为空，稍后在后台获取
                subscribedAt: Date(),
                updatedAt: Date.distantPast // 设置为过去时间，确保首次刷新能够执行
            )
            
            return youtuber
            
        } catch {
            if error is YouTubeError {
                throw error
            }
            
            print("📺 [YouTubeService] 网络请求失败: \(error)")
            
            if let urlError = error as? URLError {
                switch urlError.code {
                case .notConnectedToInternet, .networkConnectionLost:
                    throw YouTubeError.networkError
                case .timedOut:
                    throw YouTubeError.apiError("请求超时")
                default:
                    throw YouTubeError.apiError("网络错误: \(urlError.localizedDescription)")
                }
            }
            
            throw YouTubeError.apiError("请求失败: \(error.localizedDescription)")
        }
    }
    
    func refreshYouTuberVideos(_ youtuber: YouTuber) async {
        print("📺 [YouTubeService] 刷新视频列表: \(youtuber.title)")
        
        // 如果视频列表为空，总是尝试获取（新订阅的YouTuber需要首次获取）
        let hasNoVideos = youtuber.videos.isEmpty
        let timeSinceLastUpdate = Date().timeIntervalSince(youtuber.updatedAt)
        
        // 检查是否需要跳过（1小时内不重复刷新，但视频为空时强制获取）
        if !hasNoVideos && timeSinceLastUpdate < 3600 {
            print("📺 [YouTubeService] ⏰ 1小时内已更新且有视频缓存，跳过刷新: \(youtuber.title)")
            return
        }
        
        if hasNoVideos {
            print("📺 [YouTubeService] 🆕 视频列表为空，强制获取: \(youtuber.title)")
        } else {
            print("📺 [YouTubeService] 🔄 超过1小时，正常刷新: \(youtuber.title)")
        }
        
        // 添加重试机制，最多重试2次
        var lastError: Error?
        for attempt in 1...3 {
            do {
                print("📺 [YouTubeService] 尝试获取视频列表 (第\(attempt)次): \(youtuber.title)")
                let videos = try await fetchYouTuberVideos(channelId: youtuber.channelId)
                
                // 成功获取，更新数据并退出重试循环
                await MainActor.run {
                    if let index = youtubers.firstIndex(where: { $0.channelId == youtuber.channelId }) {
                        print("📺 [YouTubeService] 找到YouTuber索引: \(index)")
                        print("📺 [YouTubeService] 更新前视频数量: \(youtubers[index].videos.count)")
                        
                        youtubers[index].videos = videos
                        youtubers[index].videoCount = videos.count
                        youtubers[index].updatedAt = Date()
                        
                        print("📺 [YouTubeService] 更新后视频数量: \(youtubers[index].videos.count)")
                        print("📺 [YouTubeService] ✅ 第\(attempt)次尝试成功，获取 \(videos.count) 个视频")
                        
                        // 保存数据
                        saveYouTubers()
                    } else {
                        print("📺 [YouTubeService] 警告：找不到要更新的YouTuber: \(youtuber.channelId)")
                    }
                }
                return // 成功后退出函数
                
            } catch {
                lastError = error
                print("📺 [YouTubeService] 第\(attempt)次尝试失败: \(error)")
                
                // 如果不是最后一次尝试，等待一下再重试
                if attempt < 3 {
                    let delay = attempt == 1 ? 2.0 : 5.0 // 第一次重试等2秒，第二次重试等5秒
                    print("📺 [YouTubeService] ⏳ \(delay)秒后进行第\(attempt + 1)次尝试...")
                    try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                }
            }
        }
        
        // 所有重试都失败了，显示错误信息
        if let lastError = lastError {
            print("📺 [YouTubeService] ❌ 所有重试都失败了: \(lastError)")
            await MainActor.run {
                if let youtubeError = lastError as? YouTubeError {
                    switch youtubeError {
                    case .networkError:
                        errorMessage = "网络连接错误，已重试3次仍无法获取最新视频"
                    case .apiError(let message):
                        if message.contains("请求超时") {
                            errorMessage = "请求超时，已重试3次，请稍后再试"
                        } else {
                            errorMessage = "获取视频失败: \(message)"
                        }
                    default:
                        errorMessage = "获取视频失败: \(lastError.localizedDescription)"
                    }
                } else {
                    errorMessage = "获取视频失败: \(lastError.localizedDescription)"
                }
                print("📺 [YouTubeService] 💡 建议：当前可以正常播放已缓存的视频")
            }
        }
    }
    
    private func fetchYouTuberVideos(channelId: String) async throws -> [YouTubeVideo] {
        print("📺 [YouTubeService] 获取视频列表: \(channelId)")
        
        // 构建API请求URL
        guard var components = URLComponents(string: "\(backendBaseURL)/api/channel/videos") else {
            throw YouTubeError.apiError("无效的后端URL")
        }
        
        components.queryItems = [
            URLQueryItem(name: "id", value: channelId),
            URLQueryItem(name: "limit", value: "100")
        ]
        
        guard let url = components.url else {
            throw YouTubeError.apiError("无法构建请求URL")
        }
        
        do {
            let (data, response) = try await urlSession.data(from: url)
            
            // 检查HTTP响应状态
            if let httpResponse = response as? HTTPURLResponse {
                print("📺 [YouTubeService] 视频列表API响应状态码: \(httpResponse.statusCode)")
                
                if httpResponse.statusCode != 200 {
                    if let errorData = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                       let errorMessage = errorData["error"] as? String {
                        throw YouTubeError.apiError(errorMessage)
                    }
                    throw YouTubeError.apiError("HTTP \(httpResponse.statusCode)")
                }
            }
            
            // 解析响应数据
            let videosResponse = try JSONDecoder().decode(BackendVideosResponse.self, from: data)
            
            let videos = videosResponse.videos.map { videoData in
                YouTubeVideo(
                    videoId: videoData.video_id,
                    title: videoData.title,
                    description: videoData.description,
                    thumbnailURL: videoData.thumbnail,
                    duration: TimeInterval(videoData.duration ?? 0),
                    publishDate: parseDate(videoData.upload_date),
                    viewCount: formatViewCount(videoData.view_count)
                )
            }
            
            print("📺 [YouTubeService] 成功获取 \(videos.count) 个视频详情")
            return videos
            
        } catch {
            if error is YouTubeError {
                throw error
            }
            
            print("📺 [YouTubeService] 获取视频列表失败: \(error)")
            
            if let urlError = error as? URLError {
                switch urlError.code {
                case .notConnectedToInternet, .networkConnectionLost:
                    throw YouTubeError.networkError
                case .timedOut:
                    throw YouTubeError.apiError("请求超时，请稍后重试")
                default:
                    throw YouTubeError.apiError("网络错误: \(urlError.localizedDescription)")
                }
            }
            
            throw YouTubeError.apiError("请求失败: \(error.localizedDescription)")
        }
    }
    
    func refreshAllYouTubers() async {
        print("📺 [YouTubeService] 刷新所有YouTuber数据")
        
        // 检查上次全量刷新时间，避免频繁刷新
        let lastRefreshKey = "last_youtubers_refresh"
        let lastRefresh = UserDefaults.standard.object(forKey: lastRefreshKey) as? Date ?? Date.distantPast
        let timeSinceLastRefresh = Date().timeIntervalSince(lastRefresh)
        
        // 如果30分钟内已经刷新过，跳过
        if timeSinceLastRefresh < 1800 {
            print("📺 [YouTubeService] ⏰ 30分钟内已刷新，跳过全量刷新")
            return
        }
        
        // 更新刷新时间
        UserDefaults.standard.set(Date(), forKey: lastRefreshKey)
        
        // 限制并发数量，避免同时发送太多请求
        let batchSize = 3
        for batchStart in stride(from: 0, to: youtubers.count, by: batchSize) {
            let batchEnd = min(batchStart + batchSize, youtubers.count)
            let batch = Array(youtubers[batchStart..<batchEnd])
            
            // 并发处理一批YouTuber
            await withTaskGroup(of: Void.self) { group in
                for youtuber in batch {
                    group.addTask {
                        await self.refreshYouTuberVideos(youtuber)
                    }
                }
            }
            
            // 批次之间稍作延迟，避免服务器压力
            if batchEnd < youtubers.count {
                try? await Task.sleep(nanoseconds: 1_000_000_000) // 1秒延迟
            }
        }
        
        print("📺 [YouTubeService] 全量刷新完成")
    }
    
    // MARK: - 强制重新加载数据
    
    func forceReloadData() async {
        print("📺 [YouTubeService] 强制重新加载数据")
        await MainActor.run {
            loadYouTubers()
        }
    }
    
    // MARK: - 辅助方法
    
    private func formatSubscriberCount(_ count: Int?) -> String {
        guard let count = count else {
            return "未知"
        }
        
        if count >= 1000000 {
            return String(format: "%.1fM", Double(count) / 1000000.0)
        } else if count >= 1000 {
            return String(format: "%.1fK", Double(count) / 1000.0)
        } else {
            return "\(count)"
        }
    }
    
    private func formatViewCount(_ count: Int?) -> String {
        guard let count = count else {
            return "未知观看量"
        }
        
        if count >= 1000000 {
            return String(format: "%.1fM views", Double(count) / 1000000.0)
        } else if count >= 1000 {
            return String(format: "%.1fK views", Double(count) / 1000.0)
        } else {
            return "\(count) views"
        }
    }
    
    private func parseDate(_ dateString: String?) -> Date {
        guard let dateString = dateString else { return Date() }
        
        // 处理不同的日期格式 (YYYYMMDD)
        if dateString.count == 8 {
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyyMMdd"
            return formatter.date(from: dateString) ?? Date()
        }
        
        // 处理ISO日期格式
        let formatter = ISO8601DateFormatter()
        return formatter.date(from: dateString) ?? Date()
    }
}

// MARK: - 后端API数据模型

struct BackendChannelInfo: Codable {
    let channel_id: String
    let title: String
    let description: String?
    let subscriber_count: Int?
    let video_count: Int?
    let thumbnail: String?
    let uploader: String?
    let webpage_url: String
    let updated_at: String
}

struct BackendVideoInfo: Codable {
    let video_id: String
    let title: String
    let description: String?
    let duration: Int?
    let upload_date: String?
    let view_count: Int?
    let thumbnail: String?
    let webpage_url: String
}

struct BackendVideosResponse: Codable {
    let videos: [BackendVideoInfo]
    let count: Int
}

// MARK: - YouTube错误类型
enum YouTubeError: LocalizedError, Equatable {
    case alreadySubscribed
    case channelNotFound
    case networkError
    case apiError(String)
    
    var errorDescription: String? {
        switch self {
        case .alreadySubscribed:
            return "已经订阅了该YouTuber"
        case .channelNotFound:
            return "找不到该频道"
        case .networkError:
            return "网络连接错误"
        case .apiError(let message):
            return "服务错误: \(message)"
        }
    }
} 
