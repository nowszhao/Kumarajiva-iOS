import Foundation
import Combine

/// YouTube音频提取器 v2.0
/// 使用本地下载模式后端服务，完整下载音频和字幕文件
@MainActor
class YouTubeAudioExtractor: ObservableObject {
    static let shared = YouTubeAudioExtractor()
    
    @Published var isExtracting = false
    @Published var extractionProgress: Double = 0.0
    @Published var errorMessage: String?
    @Published var downloadStatus: String = ""
    
    private var extractionTasks: [String: Task<YouTubeDownloadResult, Error>] = [:]
    private var pollingTasks: [String: Task<Void, Never>] = [:]
    
    // 后端服务配置
    private let backendBaseURL = "http://107.148.21.15:5000"

    private init() {}
    
    /// 获取视频的音频URL（不触发下载，仅返回URL）
    /// - Parameter videoId: YouTube视频ID
    /// - Returns: 音频URL字符串
    func getAudioURL(for videoId: String) -> String {
        return "\(backendBaseURL)/files/audio?id=\(videoId)"
    }
    
    /// 从YouTube视频ID提取音频流URL和字幕
    /// - Parameter videoId: YouTube视频ID
    /// - Returns: 包含音频URL和字幕的结果
    func extractAudioAndSubtitles(from videoId: String) async throws -> YouTubeDownloadResult {
        print("🎵 [YouTubeExtractor] v2.0 开始提取视频: \(videoId)")
        
        // 检查是否已经有正在进行的提取任务
        if let existingTask = extractionTasks[videoId] {
            return try await existingTask.value
        }
        
        // 创建新的提取任务
        let task = Task<YouTubeDownloadResult, Error> {
            return try await performDownloadTask(videoId: videoId)
        }
        
        extractionTasks[videoId] = task
        
        defer {
            extractionTasks.removeValue(forKey: videoId)
            pollingTasks.removeValue(forKey: videoId)?.cancel()
        }
        
        return try await task.value
    }
    
    /// 执行下载任务（新的下载模式）
    private func performDownloadTask(videoId: String) async throws -> YouTubeDownloadResult {
        print("🎵 [YouTubeExtractor] 下载模式: 开始处理视频ID: \(videoId)")
        
        await MainActor.run {
            isExtracting = true
            extractionProgress = 0.0
            errorMessage = nil
            downloadStatus = "初始化..."
        }
        
        defer {
            Task { @MainActor in
                isExtracting = false
                // 不立即清空下载状态，让UI有时间显示完成状态
                DispatchQueue.main.asyncAfter(deadline: .now() + 5.0) {
                    self.extractionProgress = 0.0
                    self.downloadStatus = ""
                }
            }
        }
        
        do {
            // 1. 启动下载任务
            let taskId = try await startDownloadTask(videoId: videoId)
            print("🎵 [YouTubeExtractor] 下载任务已启动，ID: \(taskId)")
            
            // 2. 轮询下载状态直到完成
            let downloadResult = try await pollDownloadStatus(videoId: videoId, taskId: taskId)
            
            // 3. 构建最终结果
            let audioURL = "\(backendBaseURL)/files/audio?id=\(videoId)"
            var subtitles: [Subtitle] = []
            
            // 4. 如果有字幕文件，下载并解析
            if downloadResult.hasSubtitle == true {
                let subtitleURL = "\(backendBaseURL)/files/subtitle?id=\(videoId)"
                do {
                    subtitles = try await SubtitleParser.parseFromURL(subtitleURL)
                    print("🎵 [YouTubeExtractor] ✅ 字幕解析成功: \(subtitles.count) 条")
                } catch {
                    print("🎵 [YouTubeExtractor] ⚠️ 字幕解析失败: \(error.localizedDescription)")
                    // 字幕解析失败不影响音频播放
                }
            } else {
                print("🎵 [YouTubeExtractor] ⚠️ 该视频没有可用的字幕文件")
            }
            
            await MainActor.run { 
                extractionProgress = 1.0 
                downloadStatus = "下载完成"
            }
            
            print("🎵 [YouTubeExtractor] ✅ 下载任务完成")
            
            return YouTubeDownloadResult(
                videoId: videoId,
                audioURL: audioURL,
                subtitles: subtitles,
                videoInfo: downloadResult.videoInfo
            )
            
        } catch let error as YouTubeExtractionError {
            print("🎵 [YouTubeExtractor] ❌ 提取错误: \(error.localizedDescription)")
            await MainActor.run {
                errorMessage = error.localizedDescription
                downloadStatus = "下载失败"
            }
            throw error
        } catch {
            print("🎵 [YouTubeExtractor] ❌ 未知错误: \(error)")
            await MainActor.run {
                errorMessage = error.localizedDescription
                downloadStatus = "下载失败"
            }
            throw YouTubeExtractionError.networkError
        }
    }
    
    /// 启动下载任务
    private func startDownloadTask(videoId: String) async throws -> String {
        guard let url = URL(string: "\(backendBaseURL)/download?id=\(videoId)") else {
            throw YouTubeExtractionError.invalidURL
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Kumarajiva-iOS/2.0", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 600  
        
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse else {
                print("🎵 [YouTubeExtractor] ❌ 无效的HTTP响应")
                throw YouTubeExtractionError.networkError
            }
            
            print("🎵 [YouTubeExtractor] HTTP状态码: \(httpResponse.statusCode)")
            
            guard httpResponse.statusCode == 200 else {
                if let errorData = try? JSONDecoder().decode(ErrorResponse.self, from: data) {
                    print("🎵 [YouTubeExtractor] ❌ 服务器错误: \(errorData.error)")
                    throw YouTubeExtractionError.serverError(errorData.error)
                }
                print("🎵 [YouTubeExtractor] ❌ HTTP错误: \(httpResponse.statusCode)")
                throw YouTubeExtractionError.serverError("HTTP \(httpResponse.statusCode)")
            }
            
            let startResponse = try JSONDecoder().decode(DownloadStartResponse.self, from: data)
            
            await MainActor.run {
                downloadStatus = startResponse.message
                if startResponse.filesReady == true {
                    extractionProgress = 1.0
                } else {
                    extractionProgress = 0.1
                }
            }
            
            return startResponse.taskId
            
        } catch let error as URLError {
            // 详细的网络错误处理
            print("🎵 [YouTubeExtractor] ❌ 网络错误: \(error.localizedDescription)")
            print("🎵 [YouTubeExtractor] 错误代码: \(error.code.rawValue)")
            
            switch error.code {
            case .timedOut:
                throw YouTubeExtractionError.timeout
            case .notConnectedToInternet, .networkConnectionLost:
                throw YouTubeExtractionError.networkError
            case .cannotFindHost, .cannotConnectToHost:
                throw YouTubeExtractionError.serverError("无法连接到服务器")
            default:
                throw YouTubeExtractionError.networkError
            }
        } catch let error as YouTubeExtractionError {
            throw error
        } catch {
            print("🎵 [YouTubeExtractor] ❌ 未知错误: \(error)")
            throw YouTubeExtractionError.networkError
        }
    }
    
    /// 轮询下载状态
    private func pollDownloadStatus(videoId: String, taskId: String) async throws -> DownloadStatusResponse {
        let maxPollingTime: TimeInterval = 900 // 增加到15分钟超时
        let pollingInterval: TimeInterval = 2.0 // 2秒轮询一次
        let startTime = Date()
        
        // 创建轮询任务
        let pollingTask = Task<DownloadStatusResponse, Error> {
            while !Task.isCancelled {
                let elapsed = Date().timeIntervalSince(startTime)
                if elapsed > maxPollingTime {
                    throw YouTubeExtractionError.timeout
                }
                
                // 获取状态
                let status = try await getDownloadStatus(videoId: videoId)
                
                await MainActor.run {
                    self.extractionProgress = 0.1 + 0.9 * status.progress
                    self.downloadStatus = status.message
                }
                
                print("🎵 [YouTubeExtractor] 状态轮询: \(status.status) - \(status.message) (\(Int(status.progress * 100))%)")
                
                switch status.status {
                case "completed":
                    return status
                case "failed":
                    let errorMsg = status.error ?? "下载失败"
                    throw YouTubeExtractionError.downloadFailed(errorMsg)
                case "cancelled":
                    throw YouTubeExtractionError.taskCancelled
                default:
                    // 继续轮询
                    try await Task.sleep(nanoseconds: UInt64(pollingInterval * 1_000_000_000))
                }
            }
            
            throw CancellationError()
        }
        
        pollingTasks[videoId] = Task {
            _ = try? await pollingTask.value
        }
        
        return try await pollingTask.value
    }
    
    /// 获取下载状态
    private func getDownloadStatus(videoId: String) async throws -> DownloadStatusResponse {
        guard let url = URL(string: "\(backendBaseURL)/status?id=\(videoId)") else {
            throw YouTubeExtractionError.invalidURL
        }
        
        var request = URLRequest(url: url)
        request.setValue("Kumarajiva-iOS/2.0", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 30  // 增加到30秒
        
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200 else {
                print("🎵 [YouTubeExtractor] ❌ 状态查询失败: HTTP \((response as? HTTPURLResponse)?.statusCode ?? -1)")
                throw YouTubeExtractionError.networkError
            }
            
            return try JSONDecoder().decode(DownloadStatusResponse.self, from: data)
            
        } catch let error as URLError {
            print("🎵 [YouTubeExtractor] ❌ 状态查询网络错误: \(error.localizedDescription)")
            switch error.code {
            case .timedOut:
                throw YouTubeExtractionError.timeout
            case .notConnectedToInternet, .networkConnectionLost:
                throw YouTubeExtractionError.networkError
            case .cannotFindHost, .cannotConnectToHost:
                throw YouTubeExtractionError.serverError("无法连接到服务器")
            default:
                throw YouTubeExtractionError.networkError
            }
        } catch let error as YouTubeExtractionError {
            throw error
        } catch {
            print("🎵 [YouTubeExtractor] ❌ 状态查询解析错误: \(error)")
            throw YouTubeExtractionError.parseError
        }
    }
    
    /// 取消下载任务
    func cancelDownload(for videoId: String) async {
        print("🎵 [YouTubeExtractor] 取消下载任务: \(videoId)")
        
        // 取消本地任务
        extractionTasks.removeValue(forKey: videoId)?.cancel()
        pollingTasks.removeValue(forKey: videoId)?.cancel()
        
        // 通知后端取消
        do {
            guard let url = URL(string: "\(backendBaseURL)/cancel?id=\(videoId)") else { return }
            
            var request = URLRequest(url: url)
            request.httpMethod = "DELETE"
            request.setValue("Kumarajiva-iOS/2.0", forHTTPHeaderField: "User-Agent")
            request.timeoutInterval = 30  // 增加到30秒
            
            let (_, _) = try await URLSession.shared.data(for: request)
            print("🎵 [YouTubeExtractor] 后端取消请求已发送")
        } catch {
            print("🎵 [YouTubeExtractor] ⚠️ 后端取消请求失败: \(error)")
        }
        
        await MainActor.run {
            isExtracting = false
            extractionProgress = 0.0
            downloadStatus = ""
        }
    }
    
    /// 获取视频信息（快速接口）
    func getVideoInfo(for videoId: String) async throws -> VideoInfo {
        guard let url = URL(string: "\(backendBaseURL)/info?id=\(videoId)") else {
            throw YouTubeExtractionError.invalidURL
        }
        
        var request = URLRequest(url: url)
        request.setValue("Kumarajiva-iOS/2.0", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 60  // 增加到60秒
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw YouTubeExtractionError.networkError
        }
        
        return try JSONDecoder().decode(VideoInfo.self, from: data)
    }
    
    /// 兼容性方法：提取音频流URL（保持向后兼容）
    func extractAudioStreamURL(from videoId: String) async throws -> String {
        let result = try await extractAudioAndSubtitles(from: videoId)
        return result.audioURL
    }
    
    /// 从YouTube URL中提取视频ID
    func extractVideoId(from url: String) -> String? {
        // 支持多种YouTube URL格式
        let patterns = [
            "(?:youtube\\.com/watch\\?v=|youtu\\.be/)([\\w-]+)",
            "youtube\\.com/embed/([\\w-]+)",
            "youtube\\.com/v/([\\w-]+)"
        ]
        
        for pattern in patterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) {
                let range = NSRange(location: 0, length: url.utf16.count)
                if let match = regex.firstMatch(in: url, options: [], range: range) {
                    let matchRange = match.range(at: 1)
                    if let swiftRange = Range(matchRange, in: url) {
                        return String(url[swiftRange])
                    }
                }
            }
        }
        
        return nil
    }
    
    /// 检查URL是否为YouTube URL
    func isYouTubeURL(_ url: String) -> Bool {
        return url.contains("youtube.com") || url.contains("youtu.be")
    }
}

// MARK: - 数据模型

/// 下载结果
struct YouTubeDownloadResult {
    let videoId: String
    let audioURL: String
    let subtitles: [Subtitle]
    let videoInfo: VideoInfo?
}

/// 下载任务启动响应
struct DownloadStartResponse: Codable {
    let taskId: String
    let status: String
    let message: String
    let filesReady: Bool?
    
    private enum CodingKeys: String, CodingKey {
        case taskId = "task_id"
        case status
        case message
        case filesReady = "files_ready"
    }
}

/// 下载状态响应
struct DownloadStatusResponse: Codable {
    let taskId: String
    let videoId: String
    let status: String
    let progress: Double
    let message: String
    let filesReady: Bool
    let hasAudio: Bool?
    let hasSubtitle: Bool?
    let videoInfo: VideoInfo?
    let error: String?
    
    private enum CodingKeys: String, CodingKey {
        case taskId = "task_id"
        case videoId = "video_id"
        case status
        case progress
        case message
        case filesReady = "files_ready"
        case hasAudio = "has_audio"
        case hasSubtitle = "has_subtitle"
        case videoInfo = "video_info"
        case error
    }
}

/// 视频信息
struct VideoInfo: Codable {
    let id: String
    let title: String
    let duration: TimeInterval
    let uploader: String
    let viewCount: Int
    let description: String
    let uploadDate: String
    let thumbnail: String
    let webpageUrl: String?
    
    private enum CodingKeys: String, CodingKey {
        case id
        case title
        case duration
        case uploader
        case viewCount = "view_count"
        case description
        case uploadDate = "upload_date"
        case thumbnail
        case webpageUrl = "webpage_url"
    }
}

/// 错误响应
struct ErrorResponse: Codable {
    let error: String
}

// MARK: - 错误枚举更新
enum YouTubeExtractionError: LocalizedError {
    case invalidURL
    case invalidVideoId
    case networkError
    case videoNotFound
    case serverError(String)
    case parseError
    case audioNotAvailable
    case downloadFailed(String)
    case taskCancelled
    case timeout
    
    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "无效的URL"
        case .invalidVideoId:
            return "无效的视频ID"
        case .networkError:
            return "网络连接错误"
        case .videoNotFound:
            return "视频未找到"
        case .serverError(let message):
            return "服务器错误: \(message)"
        case .parseError:
            return "数据解析错误"
        case .audioNotAvailable:
            return "音频流不可用"
        case .downloadFailed(let message):
            return "下载失败: \(message)"
        case .taskCancelled:
            return "任务已取消"
        case .timeout:
            return "下载超时"
        }
    }
} 
