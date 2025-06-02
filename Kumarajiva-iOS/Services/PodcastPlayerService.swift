import Foundation
import Combine
import AVFoundation
import WhisperKit
import MediaPlayer

class PodcastPlayerService: NSObject, ObservableObject {
    static let shared = PodcastPlayerService()
    
    // MARK: - Published Properties
    @Published var playbackState = PodcastPlaybackState()
    @Published var currentSubtitles: [Subtitle] = []
    @Published var errorMessage: String?
    
    // 新增：音频准备状态
    @Published var audioPreparationState: AudioPreparationState = .idle
    @Published var audioPreparationProgress: Double = 0.0
    
    // 字幕生成状态（基于任务管理器）
    @Published var isGeneratingSubtitles: Bool = false
    @Published var subtitleGenerationProgress: Double = 0.0
    
    // 播放历史记录
    @Published var playbackRecords: [String: EpisodePlaybackRecord] = [:]
    
    // MARK: - Private Properties
    private var audioPlayer: AVPlayer?
    private var playbackTimer: Timer?
    private var cancellables = Set<AnyCancellable>()
    private var shouldContinueGeneration = true
    private var whisperService: WhisperKitService!
    private var isSubtitleLooping = false // 标记是否正在进行字幕循环播放
    private let playbackRecordsKey = "podcast_playback_records"
    
    // AVPlayer观察者
    private var timeObserver: Any?
    private var playerItemObserver: NSKeyValueObservation?
    private var playerStatusObserver: NSKeyValueObservation?
    
    // 新增：时长观察者
    private var durationObserver: NSKeyValueObservation?
    private var loadedTimeRangesObserver: NSKeyValueObservation?
    
    // MARK: - 生词解析相关
    @Published var vocabularyAnalysisState: VocabularyAnalysisState = .idle
    private let llmService = LLMService.shared
    
    // 设置加载超时
    private var loadingTimeoutTimer: Timer?
    
    // YouTube音频加载进度跟踪
    private var lastLoggedLoadedDuration: TimeInterval = 0
    
    // 异步加载任务跟踪
    private var currentAssetLoadingTask: DispatchWorkItem?
    
    private override init() {
        super.init()
        Task { @MainActor in
        whisperService = WhisperKitService.shared
        }
        setupAudioSession()
        setupRemoteCommandCenter()
        observeTaskManagerUpdates()
        loadPlaybackRecords()
    }
    
    // MARK: - 任务管理器状态监听
    private func observeTaskManagerUpdates() {
        taskManager.$activeTasks
            .map { tasks in
                // 检查是否有当前节目的字幕生成任务
                guard let episode = self.playbackState.currentEpisode else { return false }
                return tasks.contains { $0.episodeId == episode.id && $0.isActive }
            }
            .assign(to: &$isGeneratingSubtitles)
        
        taskManager.$activeTasks
            .compactMap { tasks in
                // 获取当前节目的字幕生成进度
                guard let episode = self.playbackState.currentEpisode else { return nil }
                return tasks.first { $0.episodeId == episode.id && $0.isActive }?.progress
            }
            .assign(to: &$subtitleGenerationProgress)
    }
    
    private var taskManager: SubtitleGenerationTaskManager {
        return SubtitleGenerationTaskManager.shared
    }
    
    var subtitleGenerationStatusText: String {
        guard let episode = playbackState.currentEpisode else { return "" }
        
        if let task = taskManager.getTask(for: episode.id) {
            return task.statusMessage
        }
        
        return "等待开始"
    }
    
    var subtitleGenerationProgressValue: Double {
        guard let episode = playbackState.currentEpisode else { return 0.0 }
        
        if let task = taskManager.getTask(for: episode.id) {
            return task.progress
        }
        
        return 0.0
    }
    
    // MARK: - Computed Properties
    var hasPreviousSubtitle: Bool {
        guard !currentSubtitles.isEmpty,
              let currentIndex = playbackState.currentSubtitleIndex else {
            return false
        }
        return currentIndex > 0
    }
    
    var hasNextSubtitle: Bool {
        guard !currentSubtitles.isEmpty,
              let currentIndex = playbackState.currentSubtitleIndex else {
            return false
        }
        return currentIndex < currentSubtitles.count - 1
    }
    
    var isPlaying: Bool {
        let hasEpisode = playbackState.currentEpisode != nil
        let isPlayingState = playbackState.isPlaying
        let hasAudioPlayer = audioPlayer != nil
        let audioPlayerIsPlaying = audioPlayer?.rate != 0
        
        // 如果有音频播放器且正在播放，但状态不一致，修正状态
        if hasAudioPlayer && audioPlayerIsPlaying && !isPlayingState {
            DispatchQueue.main.async {
                self.playbackState.isPlaying = true
            }
        }
        
        // 如果没有音频播放器但状态显示正在播放，修正状态
        if !hasAudioPlayer && isPlayingState {
            DispatchQueue.main.async {
                self.playbackState.isPlaying = false
            }
        }
        
        // 只要有节目且音频播放器存在就认为是活跃状态
        let finalIsPlaying = hasEpisode && (hasAudioPlayer || isPlayingState)
        
        return finalIsPlaying
    }
    
    var currentEpisodeTitle: String? {
        return playbackState.currentEpisode?.title
    }
    
    // MARK: - 音频会话设置
    private func setupAudioSession() {
        do {
            // 设置音频会话类别为播放类型，确保可以在锁屏时控制
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default, options: [])
            try AVAudioSession.sharedInstance().setActive(true)
        } catch {
            print("🎧 [Player] 音频会话设置失败: \(error)")
        }
    }
    
    // MARK: - 远程控制设置
    private func setupRemoteCommandCenter() {
        let commandCenter = MPRemoteCommandCenter.shared()
        
        // 启用播放/暂停命令
        commandCenter.playCommand.isEnabled = true
        commandCenter.pauseCommand.isEnabled = true
        commandCenter.togglePlayPauseCommand.isEnabled = true
        
        // 启用上一个/下一个命令
        commandCenter.previousTrackCommand.isEnabled = true
        commandCenter.nextTrackCommand.isEnabled = true
        
        // 禁用其他不需要的命令
        commandCenter.seekBackwardCommand.isEnabled = false
        commandCenter.seekForwardCommand.isEnabled = false
        commandCenter.skipBackwardCommand.isEnabled = false
        commandCenter.skipForwardCommand.isEnabled = false
        commandCenter.ratingCommand.isEnabled = false
        commandCenter.changePlaybackRateCommand.isEnabled = false
        commandCenter.likeCommand.isEnabled = false
        commandCenter.dislikeCommand.isEnabled = false
        commandCenter.bookmarkCommand.isEnabled = false
        
        // 播放命令
        commandCenter.playCommand.addTarget { [weak self] _ in
            self?.resumePlayback()
            return .success
        }
        
        // 暂停命令
        commandCenter.pauseCommand.addTarget { [weak self] _ in
            self?.pausePlayback()
            return .success
        }
        
        // 切换播放/暂停命令
        commandCenter.togglePlayPauseCommand.addTarget { [weak self] _ in
            self?.togglePlayPause()
            return .success
        }
        
        // 上一个命令（快退5个单词）
        commandCenter.previousTrackCommand.addTarget { [weak self] _ in
            self?.seekBackwardWords(wordCount: 5)
            return .success
        }
        
        // 下一个命令（快进5个单词）
        commandCenter.nextTrackCommand.addTarget { [weak self] _ in
            self?.seekForwardWords(wordCount: 5)
            return .success
        }
    }
    
    // MARK: - 播放控制
    func playEpisode(_ episode: PodcastEpisode) {
        
        
        // 在播放新节目前停止现有播放
        if playbackState.currentEpisode?.id != episode.id {
            cleanupAudioPlayer()
        }
        
        // 设置新的当前节目
        playbackState.currentEpisode = episode
        currentSubtitles = episode.subtitles
        
        
        // 根据音频类型设置时长逻辑
        if isYouTubeAudio(episode.audioURL) {
            // YouTube音频：直接使用Episode中的准确时长（来自YouTube官方数据）
            playbackState.duration = episode.duration
            print("🎧 [Player] YouTube音频使用Episode准确时长: \(formatTime(episode.duration))")
        } else {
            // 播客音频：优先使用Episode时长，但允许音频流覆盖
            if episode.duration > 0 {
                playbackState.duration = episode.duration
                print("🎧 [Player] 播客音频使用Episode时长: \(formatTime(episode.duration))")
            } else {
                // 如果Episode没有时长，会在Duration观察者中设置
                print("🎧 [Player] 播客音频等待从音频流获取时长")
            }
        }
        
        
        // 检查是否已经有音频播放器且URL相同
        if let currentURL = (audioPlayer?.currentItem?.asset as? AVURLAsset)?.url,
           currentURL.absoluteString == episode.audioURL {
            print("🎧 [Player] 音频URL相同，继续使用现有播放器")
            resumePlayback()
            return
        }
        
        
        // 为新的音频URL准备播放器
        prepareAudioForPlayback(episode: episode)
        
    }
    
    /// 准备播放节目但不自动开始播放
    func prepareEpisode(_ episode: PodcastEpisode) {
                
        // 重置生成标志
        shouldContinueGeneration = true
        
        // 检查是否是同一个节目
        let isSameEpisode = playbackState.currentEpisode?.id == episode.id
        
        if isSameEpisode && audioPreparationState == .audioReady {
            print("🎧 [Player] 节目已准备且音频就绪: \(episode.title)")
            return
        }
        
        // 如果是不同的节目或音频未准备好，重新准备
        if !isSameEpisode {
            // 重置所有状态
            playbackState.currentEpisode = episode
            playbackState.isPlaying = false
            playbackState.currentTime = 0
            playbackState.currentSubtitleIndex = nil
            audioPreparationState = .idle
            audioPreparationProgress = 0.0
            
            print("🎧 [Player] 切换到新节目，重置状态: \(episode.title)")
        }
        
        playbackState.currentEpisode = episode
        
        // 加载已有字幕
        loadExistingSubtitles(for: episode)
        
        // 准备音频但不播放
       prepareAudio(from: episode.audioURL)
        
        print("🎧 [Player] 准备节目（不自动播放）: \(episode.title)")
    }
    
    /// 为新的Episode准备音频播放
    private func prepareAudioForPlayback(episode: PodcastEpisode) {
        
        
        // 重置生成标志
        shouldContinueGeneration = true
        
        // 重置播放状态
        playbackState.isPlaying = false
        playbackState.currentTime = 0
        playbackState.currentSubtitleIndex = nil
        audioPreparationState = .idle
        audioPreparationProgress = 0.0
        
        // 开始播放音频
        loadAndPlayAudio(from: episode.audioURL)
        
        print("🎧 [Player] 为新Episode准备音频播放: \(episode.title)")
        
    }
    
    private func loadExistingSubtitles(for episode: PodcastEpisode) {
        currentSubtitles = episode.subtitles
        print("🎧 [Player] 加载已有字幕: \(episode.subtitles.count) 条")
    }
    
    private func loadAndPlayAudio(from urlString: String) {
        
        
        guard let url = URL(string: urlString) else {
            errorMessage = "无效的音频URL"
            audioPreparationState = .failed(URLError(.badURL))
            return
        }
        
        // 设置准备状态
        audioPreparationState = .preparing
        audioPreparationProgress = 0.0
        lastLoggedLoadedDuration = 0  // 重置加载进度跟踪
        print("🎧 [Player] 开始加载并播放音频: \(urlString)")
        
        
        // 检查是否仍有当前节目（防止在加载过程中被停止）
        guard self.playbackState.currentEpisode != nil else {
            print("🎧 [Player] 音频加载时发现没有当前节目，跳过播放")
            self.audioPreparationState = .idle
            return
        }
        
        
        // 清理旧的播放器和观察者
        cleanupAudioPlayer()
        
        
        
        // 先检查音频文件是否可访问
        checkAudioFileAccessibility(url: url) { [weak self] isAccessible, fileSize, serverResponse in
            DispatchQueue.main.async {
                if isAccessible {
                    print("🎧 [Player] ✅ 音频文件可访问，大小: \(fileSize ?? "未知"), 响应: \(serverResponse ?? "无")")
                    self?.proceedWithAudioLoading(url: url, urlString: urlString)
                } else {
                    print("🎧 [Player] ❌ 音频文件不可访问")
                    self?.errorMessage = "音频文件不可访问，请重新下载"
                    self?.audioPreparationState = .failed(URLError(.cannotConnectToHost))
                }
            }
        }
        
    }
    
    /// 检查音频文件可访问性
    private func checkAudioFileAccessibility(url: URL, completion: @escaping (Bool, String?, String?) -> Void) {
        
        
        var request = URLRequest(url: url)
        request.httpMethod = "HEAD"  // 只获取头部信息，不下载内容
        request.timeoutInterval = 10.0  // 10秒超时
        
        // 添加适当的请求头
        request.setValue("Kumarajiva-iOS/2.0 (iPhone; iOS)", forHTTPHeaderField: "User-Agent")
        request.setValue("*/*", forHTTPHeaderField: "Accept")
        
        print("🎧 [Player] 检查音频文件可访问性: \(url.absoluteString)")
        
        let task = URLSession.shared.dataTask(with: request) { data, response, error in
            if let error = error {
                print("🎧 [Player] 文件检查失败: \(error.localizedDescription)")
                completion(false, nil, error.localizedDescription)
                return
            }
            
            if let httpResponse = response as? HTTPURLResponse {
                print("🎧 [Player] 服务器响应状态: \(httpResponse.statusCode)")
                
                let isAccessible = (200...299).contains(httpResponse.statusCode)
                let contentLength = httpResponse.value(forHTTPHeaderField: "Content-Length")
                let serverInfo = "Status: \(httpResponse.statusCode)"
                
                if let length = contentLength, let size = Int64(length) {
                    let sizeInMB = Double(size) / (1024 * 1024)
                    completion(isAccessible, String(format: "%.1f MB", sizeInMB), serverInfo)
                } else {
                    completion(isAccessible, "未知大小", serverInfo)
                }
            } else {
                completion(false, nil, "无效响应")
            }
        }
        
        task.resume()
        
    }
    
    /// 继续音频加载流程
    private func proceedWithAudioLoading(url: URL, urlString: String) {
        
        
        // 为YouTube文件服务创建优化的AVAsset配置
        let asset: AVURLAsset
        if urlString.contains("107.148.21.15:5000/files/audio") {
            
            asset = AVURLAsset(url: url)

            print("🎧 [Player] YouTube文件服务使用简化配置，减少网络协商时间")
            
            
            // YouTube音频：跳过异步加载，直接创建播放器让AVPlayer自己处理
            print("🎧 [Player] YouTube音频跳过异步加载，直接创建播放器")
            handleAssetLoadingDirectly(asset: asset, url: url)
            
            
            return
        } else {
            // 标准音频流
            asset = AVURLAsset(url: url)
            print("🎧 [Player] 标准音频流创建AVAsset")
        }
        
        
        // 播客音频：保持原有的异步加载流程
        let requiredKeys = ["duration", "playable"]  // 移除tracks，减少加载时间
        print("🎧 [Player] 开始异步加载音频属性: \(requiredKeys)")
        
        
        // 创建异步加载任务
        currentAssetLoadingTask = DispatchWorkItem { [weak self] in
            DispatchQueue.main.async {
                // 检查任务是否已被取消
                guard let self = self, let task = self.currentAssetLoadingTask, !task.isCancelled else {
                    print("🎧 [Player] 异步加载任务已取消")
                    return
                }
                
                self.handleAssetLoading(asset: asset, requiredKeys: requiredKeys, url: url)
                self.currentAssetLoadingTask = nil
            }
        }
        
        // 添加加载进度监控
        let startTime = Date()
        print("🎧 [Player] 开始异步加载，时间: \(startTime)")
        
        asset.loadValuesAsynchronously(forKeys: requiredKeys) { [weak self] in
            let loadTime = Date().timeIntervalSince(startTime)
            print("🎧 [Player] 异步加载完成，耗时: \(String(format: "%.2f", loadTime))秒")
            
            guard let self = self, let task = self.currentAssetLoadingTask, !task.isCancelled else {
                print("🎧 [Player] 异步加载完成但任务已取消")
                return
            }
            
            // 清除超时定时器（在主线程）
            DispatchQueue.main.async {
                self.clearLoadingTimeout()
            }
            
            // 执行处理任务
            DispatchQueue.main.async(execute: task)
        }
        
        // 设置更短的超时监控（播客音频30秒）
        setupLoadingTimeout(timeout: 30.0)
    }
    
    /// 直接处理资源（跳过异步加载）
    private func handleAssetLoadingDirectly(asset: AVURLAsset, url: URL) {
        
        
        // 确保仍在准备状态且有当前节目
        guard audioPreparationState == .preparing,
              playbackState.currentEpisode != nil else {
            print("🎧 [Player] 直接加载时状态已改变，跳过处理")
            return
        }
        
        print("🎧 [Player] ✅ 跳过属性验证，直接创建播放器")
        
        // 先检查网络连接状态
        checkNetworkConditions(for: url)
        
        // 创建播放项，YouTube音频使用最激进的快速配置
        let playerItem = AVPlayerItem(asset: asset)
        
        // YouTube音频：优化缓冲策略，平衡启动速度和播放稳定性
        playerItem.preferredForwardBufferDuration = 2.0  // 增加到2秒缓冲，确保播放稳定性
        playerItem.canUseNetworkResourcesForLiveStreamingWhilePaused = false  // 暂停时不使用网络
        
        // 尝试设置更激进的缓冲策略
        if #available(iOS 10.0, *) {
            playerItem.preferredMaximumResolution = CGSize(width: 1, height: 1)  // 最小分辨率（音频无效果）
        }
        
        print("🎧 [Player] YouTube音频优化缓冲：2秒缓冲，禁用暂停时网络请求")
        
        
        
        // 创建新的AVPlayer
        self.audioPlayer = AVPlayer(playerItem: playerItem)
        
        
        // 平衡的播放器配置
        if #available(iOS 10.0, *) {
            audioPlayer?.automaticallyWaitsToMinimizeStalling = true  // 改为true，让AVPlayer决定最佳时机
            print("🎧 [Player] YouTube音频配置：让AVPlayer智能决定播放时机")
        }
        
        // 设置播放器观察者（在设置播放速率之前）
        setupPlayerObservers()
        
        print("🎧 [Player] AVPlayer创建完成，等待缓冲后开始播放")
        
        
        
        // 智能播放启动：等待最少缓冲后立即开始
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            if let player = self.audioPlayer, let item = player.currentItem {
                // 检查是否有足够的缓冲或者播放项已准备好
                if !item.isPlaybackBufferEmpty || item.isPlaybackLikelyToKeepUp {
                    print("🎧 [Player] 🚀 检测到缓冲数据，立即开始播放")
                    player.play()
                    self.playbackState.isPlaying = true
                } else {
                    print("🎧 [Player] ⏳ 等待更多缓冲数据...")
                    // 设置自动播放监听
                    self.waitForBufferAndPlay()
                }
            }
        }
        
        // 更新锁屏显示信息
        if let episode = playbackState.currentEpisode {
            updateNowPlayingInfo()
            print("🎧 [Player] 更新锁屏显示信息: \(episode.title)")
        }
        
        print("🎧 [Player] 开始播放: \(playbackState.currentEpisode?.title ?? "未知")")
        
        // 监控播放启动状态（使用更频繁的检查和网络诊断）
        monitorYouTubePlaybackWithNetworkDiagnosis()
    }
    
    /// 等待缓冲并自动播放
    private func waitForBufferAndPlay() {
        guard let player = audioPlayer, let item = player.currentItem else { return }
        
        // 设置缓冲观察者
        let observer = item.observe(\.isPlaybackLikelyToKeepUp, options: [.new]) { [weak self] item, _ in
            if item.isPlaybackLikelyToKeepUp && self?.playbackState.isPlaying == false {
                print("🎧 [Player] ✅ 缓冲充足，自动开始播放")
                player.play()
                self?.playbackState.isPlaying = true
            }
        }
        
        // 3秒后强制播放（即使缓冲不足）
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
            observer.invalidate()
            if player.rate == 0 && self.playbackState.isPlaying == false {
                print("🎧 [Player] ⏰ 3秒超时，强制开始播放")
                player.play()
                self.playbackState.isPlaying = true
            }
        }
    }
    
    /// 检查网络连接状况
    private func checkNetworkConditions(for url: URL) {
        print("🌐 [Network] 开始网络状况检查...")
        
        // 简单的ping测试
        var request = URLRequest(url: url)
        request.httpMethod = "HEAD"
        request.timeoutInterval = 5.0
        request.setValue("Kumarajiva-iOS/2.0", forHTTPHeaderField: "User-Agent")
        
        let startTime = Date()
        let task = URLSession.shared.dataTask(with: request) { _, response, error in
            let responseTime = Date().timeIntervalSince(startTime)
            
            DispatchQueue.main.async {
                if let httpResponse = response as? HTTPURLResponse {
                    print("🌐 [Network] 网络检查完成: 状态=\(httpResponse.statusCode), 响应时间=\(String(format: "%.3f", responseTime))秒")
                    
                    if responseTime > 2.0 {
                        print("🌐 [Network] ⚠️ 网络响应较慢，可能影响音频加载")
                    } else if responseTime < 0.5 {
                        print("🌐 [Network] ✅ 网络响应良好")
                    }
                } else {
                    print("🌐 [Network] ❌ 网络检查失败: \(error?.localizedDescription ?? "未知错误")")
                }
            }
        }
        task.resume()
    }
    
    /// 处理资源加载完成
    private func handleAssetLoading(asset: AVURLAsset, requiredKeys: [String], url: URL) {
        // 确保仍在准备状态且有当前节目
        guard audioPreparationState == .preparing,
              playbackState.currentEpisode != nil else {
            print("🎧 [Player] 音频属性加载完成，但状态已改变，跳过处理")
            return
        }
        
        print("🎧 [Player] 开始验证音频属性...")
        
        // 检查每个关键属性的加载状态
        for key in requiredKeys {
            var error: NSError?
            let status = asset.statusOfValue(forKey: key, error: &error)
            
            switch status {
            case .loaded:
                print("🎧 [Player] ✅ 属性加载成功: \(key)")
            case .failed:
                print("🎧 [Player] ❌ 属性加载失败: \(key), 错误: \(error?.localizedDescription ?? "未知")")
                errorMessage = "音频文件损坏或格式不支持"
                audioPreparationState = .failed(error ?? URLError(.cannotDecodeContentData))
                return
            case .cancelled:
                print("🎧 [Player] ⚠️ 属性加载被取消: \(key)")
                return
            default:
                print("🎧 [Player] ⚠️ 属性加载状态未知: \(key)")
            }
        }
        
        // 快速检查音频是否可播放
        if !asset.isPlayable {
            print("🎧 [Player] ❌ 音频资源不可播放")
            errorMessage = "音频文件不可播放，可能格式不支持"
            audioPreparationState = .failed(URLError(.cannotDecodeContentData))
            return
        }
        
        print("🎧 [Player] ✅ 音频属性验证通过，开始创建播放器")
        
        // 创建播放项，YouTube音频使用快速配置
        let playerItem = AVPlayerItem(asset: asset)
        
        // 优化YouTube音频的缓冲设置
        if let episode = playbackState.currentEpisode, isYouTubeAudio(episode.audioURL) {
            // 设置较小的缓冲时间，快速开始播放
            playerItem.preferredForwardBufferDuration = 3.0  // 减少到3秒缓冲
            print("🎧 [Player] YouTube音频优化：设置3秒前向缓冲，快速启动")
        } else {
            // 播客音频使用默认缓冲策略
            playerItem.preferredForwardBufferDuration = 10.0  // 10秒缓冲
        }
        
        // 创建新的AVPlayer
        self.audioPlayer = AVPlayer(playerItem: playerItem)
        
        // 对YouTube音频，启用自动等待网络
        if let episode = playbackState.currentEpisode, isYouTubeAudio(episode.audioURL) {
            if #available(iOS 10.0, *) {
                audioPlayer?.automaticallyWaitsToMinimizeStalling = false  // 关闭自动等待，快速开始
                print("🎧 [Player] YouTube音频关闭自动等待，优先快速启动")
            }
        }
        
        // 设置播放器观察者
        setupPlayerObservers()
        
        print("🎧 [Player] AVPlayer创建完成，开始流式播放")
        
        // 更新锁屏显示信息
        if let episode = playbackState.currentEpisode {
            updateNowPlayingInfo()
            print("🎧 [Player] 更新锁屏显示信息: \(episode.title)")
        }
        
        // 开始播放
        audioPlayer?.play()
        playbackState.isPlaying = true
        
        print("🎧 [Player] 开始播放: \(playbackState.currentEpisode?.title ?? "未知")")
        
        // 监控播放启动状态（播客音频）
        monitorPlaybackStartup()
    }
    
    /// 监控播放启动状态（播客音频）
    private func monitorPlaybackStartup() {
        let checkTimes: [TimeInterval] = [0.5, 1.0, 2.0, 5.0]
        
        for (index, delay) in checkTimes.enumerated() {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                guard let player = self.audioPlayer else { return }
                
                let rate = player.rate
                let currentTime = player.currentTime().seconds
                let isPlaying = self.playbackState.isPlaying
                
                print("🎧 [Player] 播放检查 #\(index + 1) (\(delay)秒后): rate=\(rate), time=\(self.formatTime(currentTime)), isPlaying=\(isPlaying)")
                
                // 检查播放项状态
                if let item = player.currentItem {
                    print("🎧 [Player] 播放项状态: 缓冲空=\(item.isPlaybackBufferEmpty), 可流畅播放=\(item.isPlaybackLikelyToKeepUp)")
                    
                    // 如果缓冲为空但应该播放，尝试恢复
                    if isPlaying && rate == 0 && item.isPlaybackBufferEmpty {
                        print("🎧 [Player] ⚠️ 缓冲为空，等待加载...")
                    } else if isPlaying && rate == 0 && item.isPlaybackLikelyToKeepUp {
                        print("🎧 [Player] ⚠️ 缓冲充足但未播放，尝试恢复")
                        player.play()
                    }
                }
                
                // 最后一次检查，如果还是没有开始播放，报告问题
                if index == checkTimes.count - 1 && isPlaying && rate == 0 {
                    print("🎧 [Player] ❌ 5秒后播放仍未开始，可能存在问题")
                    
                    if let item = player.currentItem, let error = item.error {
                        print("🎧 [Player] 播放项错误: \(error.localizedDescription)")
                        self.errorMessage = "播放启动失败: \(error.localizedDescription)"
                    } else {
                        self.errorMessage = "播放启动缓慢，请检查网络连接"
                    }
                }
            }
        }
    }
    
    /// 设置加载超时
    private func setupLoadingTimeout(timeout: TimeInterval) {
        // 清除之前的定时器
        loadingTimeoutTimer?.invalidate()
        
        // 设置超时
        loadingTimeoutTimer = Timer.scheduledTimer(withTimeInterval: timeout, repeats: false) { [weak self] _ in
            guard let self = self else { return }
            
            // 检查是否仍在准备状态
            if self.audioPreparationState == .preparing {
                print("🎧 [Player] ❌ 音频加载超时 (\(timeout)秒)")
                
                // 取消异步加载任务
                self.currentAssetLoadingTask?.cancel()
                self.currentAssetLoadingTask = nil
                
                self.errorMessage = "音频加载超时，请检查网络连接或重试"
                self.audioPreparationState = .failed(URLError(.timedOut))
                
                // 清理播放器
                self.cleanupAudioPlayer()
            }
        }
    }
    
    /// 清除加载超时定时器
    private func clearLoadingTimeout() {
        loadingTimeoutTimer?.invalidate()
        loadingTimeoutTimer = nil
        print("🎧 [Player] 清除加载超时定时器")
    }
    
    private func prepareAudio(from urlString: String) {
        guard let url = URL(string: urlString) else {
            errorMessage = "无效的音频URL"
            audioPreparationState = .failed(URLError(.badURL))
            return
        }
        
        // 设置准备状态
        audioPreparationState = .preparing
        audioPreparationProgress = 0.0
        print("🎧 [Player] 开始准备音频: \(urlString)")
        
        // 检查是否仍有当前节目（防止在加载过程中被停止）
        guard self.playbackState.currentEpisode != nil else {
            print("🎧 [Player] 音频准备时发现没有当前节目，跳过准备")
            self.audioPreparationState = .idle
            return
        }
        
        // 清理旧的播放器和观察者
        cleanupAudioPlayer()
    
        
        self.audioPlayer = AVPlayer(url: url)
        print("🎧 [Player] 标准音频流准备AVPlayer")
        
        
        
        // 设置播放器观察者
        setupPlayerObservers()
        
        // 启用速度控制
        self.audioPlayer?.rate = self.playbackState.playbackRate
        
        print("🎧 [Player] AVPlayer创建完成，音频已准备")
    }
    
    /// 安全清理音频播放器和相关观察者
    private func cleanupAudioPlayer() {
        // 先移除观察者
        removePlayerObservers()
        
        // 清除所有定时器
        clearLoadingTimeout()
        
        // 取消异步加载任务
        currentAssetLoadingTask?.cancel()
        currentAssetLoadingTask = nil
        
        // 暂停并清理播放器
        audioPlayer?.pause()
        audioPlayer = nil
        
        print("🎧 [Player] 旧音频播放器已清理")
    }
    
    // MARK: - AVPlayer观察者设置
    private func setupPlayerObservers() {
        guard let player = audioPlayer else { return }
        
        // 清除之前的观察者（安全清理）
        removePlayerObservers()
        
        // 观察播放器状态
        playerStatusObserver = player.observe(\.status, options: [.new]) { [weak self] player, _ in
            DispatchQueue.main.async {
                self?.handlePlayerStatusChange(player.status)
            }
        }
        
        // 观察播放项状态
        if let playerItem = player.currentItem {
            playerItemObserver = playerItem.observe(\.status, options: [.new]) { [weak self] item, _ in
                DispatchQueue.main.async {
                    self?.handlePlayerItemStatusChange(item.status)
                }
            }
            
            // 观察时长变化（根据音频类型采用不同策略）
            durationObserver = playerItem.observe(\.duration, options: [.new]) { [weak self] item, _ in
                DispatchQueue.main.async {
                    let duration = item.duration.seconds
                    if duration.isFinite && !duration.isNaN && duration > 0 {
                        guard let self = self, let episode = self.playbackState.currentEpisode else { return }
                        
                        if self.isYouTubeAudio(episode.audioURL) {
                            // YouTube音频：保持Episode准确时长，忽略音频流时长
                            print("🎧 [Player] YouTube音频保持Episode准确时长(\(self.formatTime(episode.duration)))，忽略音频流时长(\(self.formatTime(duration)))")
                        } else {
                            // 播客音频：使用音频流时长（原有逻辑）
                            if episode.duration <= 0 {
                                self.playbackState.duration = duration
                                print("🎧 [Player] 播客音频从音频流获取时长: \(self.formatTime(duration))")
                            } else {
                                // 检查是否有显著差异
                                let timeDifference = abs(duration - episode.duration)
                                if timeDifference > 10 {
                                    self.playbackState.duration = duration
                                    print("🎧 [Player] 播客音频流时长(\(self.formatTime(duration)))与Episode时长(\(self.formatTime(episode.duration)))差异较大，使用音频流时长")
                                } else {
                                    // 保持Episode时长，但需要显式设置到playbackState
                                    self.playbackState.duration = episode.duration
                                    print("🎧 [Player] 播客音频保持Episode时长(\(self.formatTime(episode.duration)))，音频流时长(\(self.formatTime(duration)))差异不大")
                                }
                            }
                        }
                    } else {
                        print("🎧 [Player] ⚠️ 音频流时长无效: \(duration)")
                    }
                }
            }
            
            // 观察加载进度
            loadedTimeRangesObserver = playerItem.observe(\.loadedTimeRanges, options: [.new]) { [weak self] item, _ in
                DispatchQueue.main.async {
                    if let timeRange = item.loadedTimeRanges.first?.timeRangeValue {
                        let loadedDuration = CMTimeGetSeconds(CMTimeAdd(timeRange.start, timeRange.duration))
                        if loadedDuration > 0 {
                            guard let self = self, let episode = self.playbackState.currentEpisode else { return }
                            
                            // 根据音频类型调整日志频率
                            if self.isYouTubeAudio(episode.audioURL) {
                                // YouTube音频：减少日志频率，只在重要节点打印
                                let previousLoaded = self.lastLoggedLoadedDuration
                                let loadedDiff = loadedDuration - previousLoaded
                                
                                if loadedDiff >= 10 || loadedDuration >= 30 && previousLoaded < 30 {
                                    print("🎧 [Player] YouTube音频已加载: \(self.formatTime(loadedDuration))")
                                    self.lastLoggedLoadedDuration = loadedDuration
                                }
                            } else {
                                // 播客音频：保持原有频率
                                print("🎧 [Player] 已加载时长: \(self.formatTime(loadedDuration))")
                            }
                        }
                    }
                }
            }
        }
        
        // 添加时间观察者
        let timeScale = CMTimeScale(NSEC_PER_SEC)
        let time = CMTime(seconds: 0.1, preferredTimescale: timeScale)
        
        timeObserver = player.addPeriodicTimeObserver(forInterval: time, queue: .main) { [weak self] time in
            self?.handleTimeUpdate(time)
        }
        
        // 监听播放完成通知
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(playerDidFinishPlaying),
            name: .AVPlayerItemDidPlayToEndTime,
            object: player.currentItem
        )
        
        print("🎧 [Player] 播放器观察者设置完成")
    }
    
    private func removePlayerObservers() {
        // 安全移除时间观察者
        if let timeObserver = timeObserver, let player = audioPlayer {
            player.removeTimeObserver(timeObserver)
            self.timeObserver = nil
        }
        
        // 移除KVO观察者
        playerStatusObserver?.invalidate()
        playerStatusObserver = nil
        
        playerItemObserver?.invalidate()
        playerItemObserver = nil
        
        // 清理新增的观察者
        durationObserver?.invalidate()
        durationObserver = nil
        
        loadedTimeRangesObserver?.invalidate()
        loadedTimeRangesObserver = nil
        
        // 移除通知观察者
        NotificationCenter.default.removeObserver(self, name: .AVPlayerItemDidPlayToEndTime, object: nil)
        
        print("🎧 [Player] 播放器观察者已清理")
    }
    
    // MARK: - AVPlayer状态处理
    private func handlePlayerStatusChange(_ status: AVPlayer.Status) {
        switch status {
        case .readyToPlay:
            print("🎧 [Player] AVPlayer准备就绪")
            audioPreparationState = .audioReady
            audioPreparationProgress = 1.0
            
            // 清除加载超时定时器
            clearLoadingTimeout()
            
            // 检查播放器状态
            if let player = audioPlayer {
                print("🎧 [Player] 播放器详细状态:")
                print("  - 播放速率: \(player.rate)")
                
                // 安全获取时长
                let duration = player.currentItem?.duration.seconds ?? 0
                print("  - 时长: \(formatTime(duration))")
                
                // 安全获取当前时间
                let currentTime = player.currentTime().seconds
                print("  - 当前时间: \(formatTime(currentTime))")
                
                print("  - 播放状态: \(playbackState.isPlaying ? "播放中" : "暂停")")
                
                // 检查音频会话
                let session = AVAudioSession.sharedInstance()
                print("  - 音频会话类别: \(session.category)")
                print("  - 音频会话模式: \(session.mode)")
                print("  - 音频会话活跃: \(session.isOtherAudioPlaying ? "其他音频播放中" : "无其他音频")")
                
                // 检查播放项状态
                if let item = player.currentItem {
                    print("  - 播放项状态: \(item.status.rawValue)")
                    print("  - 播放项错误: \(item.error?.localizedDescription ?? "无")")
                    print("  - 缓冲状态: \(item.isPlaybackBufferEmpty ? "缓冲空" : "有缓冲")")
                    print("  - 可播放: \(item.isPlaybackLikelyToKeepUp ? "可流畅播放" : "需要缓冲")")
                    
                    // 检查时长是否有效
                    let itemDuration = item.duration.seconds
                    if itemDuration.isFinite && !itemDuration.isNaN && itemDuration > 0 {
                        print("  - 播放项时长有效: \(formatTime(itemDuration))")
                    } else {
                        print("  - 播放项时长无效: \(itemDuration)")
                    }
                }
                
                // 尝试手动开始播放
                if playbackState.isPlaying && player.rate == 0 {
                    print("🎧 [Player] ⚠️ 播放状态为true但播放速率为0，尝试手动播放")
                    player.play()
                    
                    // 延迟检查播放状态
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                        if let player = self.audioPlayer {
                            let rate = player.rate
                            let status = self.playbackState.isPlaying
                            print("🎧 [Player] 1秒后播放检查: 速率=\(rate), 状态=\(status)")
                        }
                    }
                }
            }
            
            print("🎧 [Player] 播放器就绪，当前时长: \(formatTime(playbackState.duration))")
            
        case .failed:
            // 清除加载超时定时器
            clearLoadingTimeout()
            
            if let error = audioPlayer?.error {
                print("🎧 [Player] AVPlayer播放失败: \(error)")
                print("🎧 [Player] 错误详情: \(error.localizedDescription)")
                
                // 检查具体错误类型
                if let urlError = error as? URLError {
                    print("🎧 [Player] URL错误代码: \(urlError.code.rawValue)")
                    switch urlError.code {
                    case .timedOut:
                        errorMessage = "音频加载超时，请检查网络连接"
                    case .cannotConnectToHost:
                        errorMessage = "无法连接到音频服务器"
                    case .networkConnectionLost:
                        errorMessage = "网络连接中断"
                    default:
                        errorMessage = "音频播放失败: \(error.localizedDescription)"
                    }
                } else if let avError = error as? AVError {
                    print("🎧 [Player] AVError错误代码: \(avError.code.rawValue)")
                    errorMessage = "音频播放失败: \(error.localizedDescription)"
                } else {
                    errorMessage = "音频播放失败: \(error.localizedDescription)"
                }
                audioPreparationState = .failed(error)
            }
            
        case .unknown:
            print("🎧 [Player] AVPlayer状态未知")
            
        @unknown default:
            print("🎧 [Player] AVPlayer未知状态")
        }
    }
    
    private func handlePlayerItemStatusChange(_ status: AVPlayerItem.Status) {
        switch status {
        case .readyToPlay:
            print("🎧 [Player] AVPlayerItem准备就绪")
            audioPreparationProgress = 0.8
            
        case .failed:
            if let error = audioPlayer?.currentItem?.error {
                print("🎧 [Player] AVPlayerItem播放失败: \(error)")
                errorMessage = "音频播放失败: \(error.localizedDescription)"
                audioPreparationState = .failed(error)
            }
            
        case .unknown:
            print("🎧 [Player] AVPlayerItem状态未知")
            audioPreparationProgress = 0.2
            
        @unknown default:
            print("🎧 [Player] AVPlayerItem未知状态")
        }
    }
    
    private func handleTimeUpdate(_ time: CMTime) {
        let currentTime = time.seconds
        if currentTime.isFinite && !currentTime.isNaN {
            let oldTime = playbackState.currentTime
            playbackState.currentTime = currentTime
            
            // 每5秒打印一次时间更新，避免日志过多
            if Int(currentTime) % 5 == 0 && Int(oldTime) != Int(currentTime) {
                print("🎧 [Player] 时间更新: \(formatTime(currentTime)) / \(formatTime(playbackState.duration))")
                
                // 检查播放器实际状态
                if let player = audioPlayer {
                    print("🎧 [Player] 播放器状态检查: rate=\(player.rate), isPlaying=\(playbackState.isPlaying)")
                    
                    // 检查是否播放卡住了
                    if playbackState.isPlaying && player.rate == 0 {
                        print("🎧 [Player] ⚠️ 检测到播放卡住，尝试恢复播放")
                        player.play()
                    }
                }
            }
            
            // 检查播放是否真正开始（前10秒更频繁检查）
            if currentTime < 10 && Int(currentTime) != Int(oldTime) {
                print("🎧 [Player] 播放开始阶段: \(formatTime(currentTime)), rate=\(audioPlayer?.rate ?? 0)")
            }
            
            // 更新播放历史记录
            if let episode = playbackState.currentEpisode {
                updatePlaybackRecord(
                    for: episode.id,
                    currentTime: currentTime,
                    duration: playbackState.duration
                )
            }
            
            // 更新字幕索引
            updateCurrentSubtitleIndex()
        } else {
            print("🎧 [Player] ⚠️ 时间无效: \(time.seconds)")
            
            // 时间无效时检查播放器状态
            if let player = audioPlayer {
                print("🎧 [Player] 时间无效时播放器状态: rate=\(player.rate), status=\(player.status.rawValue)")
            }
        }
    }
    
    @objc private func playerDidFinishPlaying() {
        print("🎧 [Player] 音频播放完成")
        
        // 标记播放完成
        if let episode = playbackState.currentEpisode {
            updatePlaybackRecord(
                for: episode.id,
                currentTime: playbackState.duration,
                duration: playbackState.duration,
                isCompleted: true
            )
        }
        
        if playbackState.isLooping {
            // 如果是循环播放，重新开始
            seek(to: 0)
            resumePlayback()
        } else {
            // 播放完成，重置状态
            playbackState.isPlaying = false
            playbackState.currentTime = 0
            playbackState.currentSubtitleIndex = nil
            stopPlaybackTimer()
        }
    }
    
    private func startPlayback() {
        // 再次检查是否仍有当前节目
        guard playbackState.currentEpisode != nil else {
            print("🎧 [Player] 开始播放时发现没有当前节目，跳过播放")
            return
        }
        
        // 重新激活音频会话，确保独占播放
        do {
            try AVAudioSession.sharedInstance().setActive(true, options: .notifyOthersOnDeactivation)
        } catch {
            print("🎧 [Player] 音频会话激活失败: \(error)")
        }
        
        audioPlayer?.play()
        playbackState.isPlaying = true
        
        // 更新锁屏显示信息
        updateNowPlayingInfo()
        
        print("🎧 [Player] 开始播放: \(playbackState.currentEpisode?.title ?? "未知")")
        
        // 监控播放启动状态（YouTube音频使用更频繁的检查）
        if let episode = playbackState.currentEpisode, isYouTubeAudio(episode.audioURL) {
            monitorYouTubePlaybackWithNetworkDiagnosis()
        } else {
            monitorPlaybackStartup()
        }
    }
    
    func pausePlayback() {
        audioPlayer?.pause()
        playbackState.isPlaying = false
        
        // 更新锁屏显示信息
        updateNowPlayingInfo()
    }
    
    func resumePlayback() {
        // 检查音频是否准备就绪
        guard audioPreparationState == .audioReady else {
            print("🎧 [Player] 音频未准备就绪，无法恢复播放")
            return
        }
        
        audioPlayer?.play()
        playbackState.isPlaying = true
        
        // 更新锁屏显示信息
        updateNowPlayingInfo()
    }
    
    func stopPlayback() {
        // 完全停止播放，清除所有状态
        cancelSubtitleGeneration()
        
        // 清理播放器和观察者
        cleanupAudioPlayer()
        
        // 重置播放状态
        playbackState.isPlaying = false
        playbackState.currentTime = 0
        playbackState.currentSubtitleIndex = nil
        playbackState.currentEpisode = nil
        
        // 重置音频准备状态
        audioPreparationState = .idle
        audioPreparationProgress = 0.0
        
        stopPlaybackTimer()
        
        // 清除锁屏显示信息
        clearNowPlayingInfo()
        
        // 释放音频会话
        do {
            try AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        } catch {
            print("🎧 [Player] 音频会话释放失败: \(error)")
        }
        
        print("🎧 [Player] 播放已完全停止，音频会话已释放，字幕生成已取消")
    }
    
    func seek(to time: TimeInterval) {
        audioPlayer?.seek(to: CMTime(seconds: time, preferredTimescale: 1000))
        playbackState.currentTime = time
    }
    
    // MARK: - 时间跳转控制
    func seekBackward(seconds: TimeInterval = 5.0) {
        guard let audioPlayer = audioPlayer else { return }
        
        let newTime = max(0, audioPlayer.currentTime().seconds - seconds)
        audioPlayer.seek(to: CMTime(seconds: newTime, preferredTimescale: 1000))
        playbackState.currentTime = newTime
        
        print("🎧 [Player] 快退 \(seconds) 秒到: \(formatTime(newTime))")
    }
    
    func seekForward(seconds: TimeInterval = 5.0) {
        guard let audioPlayer = audioPlayer else { return }
        
        let duration = audioPlayer.currentItem?.duration.seconds ?? 0
        let newTime = min(duration, audioPlayer.currentTime().seconds + seconds)
        audioPlayer.seek(to: CMTime(seconds: newTime, preferredTimescale: 1000))
        playbackState.currentTime = newTime
        
        print("🎧 [Player] 快进 \(seconds) 秒到: \(formatTime(newTime))")
    }
    
    // MARK: - 单词跳转控制
    func seekBackwardWords(wordCount: Int = 5) {
        guard let audioPlayer = audioPlayer else { return }
        
        let currentTime = audioPlayer.currentTime().seconds
        let targetTime = findTimeForWordOffset(from: currentTime, wordOffset: -wordCount)
        
        audioPlayer.seek(to: CMTime(seconds: targetTime, preferredTimescale: 1000))
        playbackState.currentTime = targetTime
        
        print("🎧 [Player] 快退 \(wordCount) 个单词到: \(formatTime(targetTime))")
    }
    
    func seekForwardWords(wordCount: Int = 5) {
        guard let audioPlayer = audioPlayer else { return }
        
        let currentTime = audioPlayer.currentTime().seconds
        let duration = audioPlayer.currentItem?.duration.seconds ?? 0
        let targetTime = min(duration, findTimeForWordOffset(from: currentTime, wordOffset: wordCount))
        
        audioPlayer.seek(to: CMTime(seconds: targetTime, preferredTimescale: 1000))
        playbackState.currentTime = targetTime
        
        print("🎧 [Player] 快进 \(wordCount) 个单词到: \(formatTime(targetTime))")
    }
    
    // MARK: - 单词跳转辅助方法
    private func findTimeForWordOffset(from currentTime: TimeInterval, wordOffset: Int) -> TimeInterval {
        // 收集所有单词并按时间排序
        var allWords: [(word: SubtitleWord, subtitleIndex: Int)] = []
        
        for (subtitleIndex, subtitle) in currentSubtitles.enumerated() {
            for word in subtitle.words {
                allWords.append((word: word, subtitleIndex: subtitleIndex))
            }
        }
        
        // 按开始时间排序
        allWords.sort { $0.word.startTime < $1.word.startTime }
        
        // 找到当前时间对应的单词索引
        var currentWordIndex = 0
        for (index, wordData) in allWords.enumerated() {
            if currentTime >= wordData.word.startTime && currentTime <= wordData.word.endTime {
                currentWordIndex = index
                break
            } else if currentTime < wordData.word.startTime {
                // 如果当前时间在单词之前，使用这个单词
                currentWordIndex = index
                break
            } else if index == allWords.count - 1 {
                // 如果到了最后一个单词，使用最后一个
                currentWordIndex = index
            }
        }
        
        // 计算目标单词索引
        let targetWordIndex = max(0, min(allWords.count - 1, currentWordIndex + wordOffset))
        
        // 返回目标单词的开始时间
        if targetWordIndex < allWords.count {
            return allWords[targetWordIndex].word.startTime
        } else {
            return currentTime
        }
    }
    
    // MARK: - 时间格式化辅助方法
    func formatTime(_ time: TimeInterval) -> String {
        // 安全检查，防止NaN和无穷大导致崩溃
        guard time.isFinite && !time.isNaN && time >= 0 else {
            return "invalid"
        }
        
        let minutes = Int(time) / 60
        let seconds = Int(time) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
    
    func togglePlayPause() {
        // 检查音频是否准备就绪
        guard audioPreparationState == .audioReady else {
            print("🎧 [Player] 音频未准备就绪，无法播放")
            return
        }
        
        if playbackState.isPlaying {
            pausePlayback()
        } else {
            resumePlayback()
        }
    }
    
    func pause() {
        pausePlayback()
    }
    
    func setPlaybackRate(_ rate: Float) {
        guard let player = audioPlayer else {
            print("🎧 [Player] 音频播放器未初始化，无法设置播放速度")
            return
        }
        
        // 确保播放器支持速度调节
        player.rate = rate
        playbackState.playbackRate = rate
        
        // 更新锁屏显示信息
        updateNowPlayingInfo()
        
        print("🎧 [Player] 播放速度已设置为: \(rate)x")
    }
    
    func previousSubtitle() {
        guard !currentSubtitles.isEmpty else { return }
        
        // 在循环播放模式下，允许手动切换字幕
        isSubtitleLooping = false
        
        if let currentIndex = playbackState.currentSubtitleIndex, currentIndex > 0 {
            let previousSubtitle = currentSubtitles[currentIndex - 1]
            playbackState.currentSubtitleIndex = currentIndex - 1
            seek(to: previousSubtitle.startTime)
        } else if !currentSubtitles.isEmpty {
            playbackState.currentSubtitleIndex = 0
            seek(to: currentSubtitles[0].startTime)
        }
        
        // 更新锁屏显示信息
        updateNowPlayingInfo()
        
        print("🎧 [Player] 手动切换到上一条字幕")
    }
    
    func nextSubtitle() {
        guard !currentSubtitles.isEmpty else { return }
        
        // 在循环播放模式下，允许手动切换字幕
        isSubtitleLooping = false
        
        if let currentIndex = playbackState.currentSubtitleIndex, currentIndex < currentSubtitles.count - 1 {
            let nextSubtitle = currentSubtitles[currentIndex + 1]
            playbackState.currentSubtitleIndex = currentIndex + 1
            seek(to: nextSubtitle.startTime)
        }
        
        // 更新锁屏显示信息
        updateNowPlayingInfo()
        
        print("🎧 [Player] 手动切换到下一条字幕")
    }
    
    func toggleLoop() {
        playbackState.isLooping.toggle()
    }
    
    private func startPlaybackTimer() {
        // AVPlayer使用时间观察者，不需要Timer
        // 保留此方法以兼容现有代码，但不执行任何操作
    }
    
    private func stopPlaybackTimer() {
        // AVPlayer使用时间观察者，不需要Timer
        // 保留此方法以兼容现有代码，但不执行任何操作
    }
    
    private func updateCurrentSubtitleIndex() {
        let currentTime = playbackState.currentTime
        
        // 检查是否需要字幕循环播放
        if playbackState.isLooping, let currentIndex = playbackState.currentSubtitleIndex {
            let currentSubtitle = currentSubtitles[currentIndex]
            
            // 如果当前时间超过了当前字幕的结束时间，且开启了循环播放
            if currentTime > currentSubtitle.endTime {
                print("🎧 [Player] 字幕循环播放：重新播放字幕 \(currentIndex)")
                isSubtitleLooping = true
                seek(to: currentSubtitle.startTime)
                // 延迟重置标志，避免立即触发下一次检查
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                    self.isSubtitleLooping = false
                }
                return
            }
        }
        
        // 如果正在进行字幕循环播放，暂时不更新字幕索引
        if isSubtitleLooping {
            return
        }
        
        for (index, subtitle) in currentSubtitles.enumerated() {
            if currentTime >= subtitle.startTime && currentTime <= subtitle.endTime {
                if playbackState.currentSubtitleIndex != index {
                    // 如果开启了循环播放且已有当前字幕，不允许自动跳转到下一条字幕
                    if playbackState.isLooping && playbackState.currentSubtitleIndex != nil {
                        print("🎧 [Player] 循环播放模式：阻止自动跳转到下一条字幕")
                        return
                    }
                    
                    playbackState.currentSubtitleIndex = index
                    print("🎧 [Player] 字幕切换到索引: \(index)")
                    
                    // 字幕切换时更新锁屏显示信息
                    updateNowPlayingInfo()
                }
                return
            }
        }
        
        // 如果没有找到匹配的字幕，清除当前索引（但在循环播放模式下保持当前字幕）
        if playbackState.currentSubtitleIndex != nil && !playbackState.isLooping {
            playbackState.currentSubtitleIndex = nil
            print("🎧 [Player] 清除字幕索引：当前无活动字幕")
        }
    }
    
    // MARK: - 字幕生成
    
    private func startSubtitleGeneration(for episode: PodcastEpisode) {
        // 检查是否已有活动任务
        if SubtitleGenerationTaskManager.shared.hasActiveTask(for: episode.id) {
            print("🎧 [Player] 字幕生成任务已存在: \(episode.title)")
            return
        }
        
        print("🎧 [Player] 开始生成字幕: \(episode.title)")
        
        // 使用任务管理器创建任务
        let taskManager = SubtitleGenerationTaskManager.shared
        if let task = taskManager.createTask(for: episode) {
            print("🎧 [Player] 创建自动字幕生成任务: \(episode.title)")
            
            // 监听任务完成，更新当前字幕
            Task { @MainActor in
                await monitorTaskCompletion(task)
            }
        }
    }
    
    /// 监听任务完成状态
    @MainActor
    private func monitorTaskCompletion(_ task: SubtitleGenerationTask) async {
        // 监听任务状态变化
        while task.isActive && shouldContinueGeneration {
            try? await Task.sleep(nanoseconds: 500_000_000) // 500ms检查一次
            
            // 检查是否应该继续监听
            guard shouldContinueGeneration else {
                print("🎧 [Player] 停止监听任务完成状态: \(task.episodeName)")
                break
            }
            
            // 如果任务完成且是当前播放的节目，更新字幕
            if task.isCompleted,
               let currentEpisode = playbackState.currentEpisode,
               task.episodeId == currentEpisode.id {
                
                print("🎧 [Player] 任务完成，更新当前字幕: \(task.episodeName)")
                currentSubtitles = task.generatedSubtitles
                
                // 移除手动触发UI更新的调用，@Published属性会自动处理
                // 避免过度的UI刷新导致导航问题
                break
            }
            
            // 如果任务失败，设置错误信息
            if case .failed(let error) = task.status {
                errorMessage = "字幕生成失败: \(error.localizedDescription)"
                break
            }
        }
    }
    
    /// 手动生成当前节目的字幕
    func generateSubtitlesForCurrentEpisode(quality: SubtitleQuality = .medium) async {
        // 确保在主线程检查和更新状态
        let episode = await MainActor.run { () -> PodcastEpisode? in
            guard let episode = playbackState.currentEpisode else {
                errorMessage = "没有正在播放的节目"
                return nil
            }
            
            // 如果已经有字幕，询问是否重新生成
            if !episode.subtitles.isEmpty {
                print("🎧 [Player] 节目已有字幕，重新生成...")
            }
            
            return episode
        }
        
        guard let episode = episode else { return }
        
        // 使用任务管理器创建任务
        let taskManager = SubtitleGenerationTaskManager.shared
        if let task = taskManager.createTask(for: episode, quality: quality) {
            print("🎧 [Player] 创建手动字幕生成任务: \(episode.title)")
            
            // 监听任务完成
            Task { @MainActor in
                await monitorTaskCompletion(task)
            }
        }
    }
    
    /// 加载当前节目的SRT字幕
    func loadSRTSubtitlesForCurrentEpisode() async {
        await MainActor.run {
            guard let episode = playbackState.currentEpisode else {
                errorMessage = "没有正在播放的节目"
                return
            }
            
            // 如果已经有字幕，直接显示
            if !currentSubtitles.isEmpty {
                print("🎧 [Player] 当前已有字幕，无需重新加载")
                return
            }
            
            // 如果Episode对象本身包含SRT字幕，直接使用
            if !episode.subtitles.isEmpty {
                currentSubtitles = episode.subtitles
                print("🎧 [Player] ✅ 使用Episode中的SRT字幕: \(episode.subtitles.count) 条")
                return
            }
        }
        
        // 检查是否还有当前节目（在await后重新检查）
        guard let episode = await MainActor.run(body: { playbackState.currentEpisode }) else {
            await MainActor.run {
                errorMessage = "没有正在播放的节目"
            }
            return
        }
        
        // 尝试从YouTube Audio Extractor重新获取字幕
        do {
            await MainActor.run {
                isGeneratingSubtitles = true
                subtitleGenerationProgress = 0.0
            }
            
            // 从YouTube ID重新获取字幕
            if let videoId = await YouTubeAudioExtractor.shared.extractVideoId(from: episode.audioURL) {
                print("🎧 [Player] 尝试重新获取字幕，视频ID: \(videoId)")
                
                let downloadResult = try await YouTubeAudioExtractor.shared.extractAudioAndSubtitles(from: videoId)
                
                await MainActor.run {
                    currentSubtitles = downloadResult.subtitles
                    subtitleGenerationProgress = 1.0
                }
                
                print("🎧 [Player] ✅ 重新获取字幕成功: \(downloadResult.subtitles.count) 条")
                
                // 保存字幕到Episode
                await PodcastDataService.shared.updateEpisodeSubtitlesWithMetadata(
                    episode.id,
                    subtitles: downloadResult.subtitles,
                    generationDate: Date(),
                    version: "vtt_1.0"  // 更新版本标识为VTT
                )
                
            } else {
                throw YouTubeExtractionError.invalidURL
            }
            
        } catch {
            print("🎧 [Player] SRT字幕加载失败: \(error)")
            await MainActor.run {
                errorMessage = "字幕加载失败: \(error.localizedDescription)"
            }
        }
        
        await MainActor.run {
            isGeneratingSubtitles = false
        }
        
        // 延迟清除状态文本
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 2_000_000_000) // 2秒
            // 清理状态信息
        }
    }
    
    /// 取消字幕生成
    func cancelSubtitleGeneration() {
        shouldContinueGeneration = false
        
        // 取消当前节目的字幕生成任务
        if let episode = playbackState.currentEpisode {
            let taskManager = SubtitleGenerationTaskManager.shared
            if let task = taskManager.getTask(for: episode.id) {
                taskManager.cancelTask(task)
                print("🎧 [Player] 字幕生成任务已取消: \(episode.title)")
            }
        }
        
        // 取消所有活动的字幕生成任务（防止其他任务影响）
        let taskManager = SubtitleGenerationTaskManager.shared
        for task in taskManager.activeTasks {
            taskManager.cancelTask(task)
            print("🎧 [Player] 取消活动任务: \(task.episodeName)")
        }
        
        print("🎧 [Player] 所有字幕生成已取消")
    }
    
    // MARK: - 字幕保存和管理
    
    /// 保存字幕到缓存和持久存储
    private func saveSubtitlesWithMetadata(quality: SubtitleQuality) {
        guard let episode = playbackState.currentEpisode else { return }
        
        // 保存到数据服务（带元数据）
        Task {
            await PodcastDataService.shared.updateEpisodeSubtitlesWithMetadata(
                episode.id,
                subtitles: currentSubtitles,
                generationDate: Date(),
                version: "1.0"
            )
        }
        
        print("🎧 [Player] 字幕已保存，包含元数据: 质量=\(quality), 数量=\(currentSubtitles.count)")
    }
    
    /// 防抖保存字幕
    private var saveDebounceTimer: Timer?
    
    func saveSubtitlesDebounced() {
        saveDebounceTimer?.invalidate()
        saveDebounceTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: false) { [weak self] _ in
            self?.saveSubtitlesWithMetadata(quality: .medium)
        }
    }
    
    // MARK: - 字幕查找
    
    /// 获取当前时间对应的字幕
    func getCurrentSubtitle() -> Subtitle? {
        let currentTime = playbackState.currentTime
        return currentSubtitles.first { subtitle in
            currentTime >= subtitle.startTime && currentTime <= subtitle.endTime
        }
    }
    
    /// 获取指定时间范围内的字幕
    func getSubtitles(from startTime: TimeInterval, to endTime: TimeInterval) -> [Subtitle] {
        return currentSubtitles.filter { subtitle in
            subtitle.startTime < endTime && subtitle.endTime > startTime
        }
    }
    
    // MARK: - 播放历史记录
    
    private func loadPlaybackRecords() {
        if let data = UserDefaults.standard.data(forKey: playbackRecordsKey),
           let records = try? JSONDecoder().decode([String: EpisodePlaybackRecord].self, from: data) {
            playbackRecords = records
            print("🎧 [Player] 加载播放历史记录: \(records.count) 条")
        }
    }
    
    private func savePlaybackRecords() {
        if let data = try? JSONEncoder().encode(playbackRecords) {
            UserDefaults.standard.set(data, forKey: playbackRecordsKey)
        }
    }
    
    func updatePlaybackRecord(for episodeId: String, currentTime: TimeInterval, duration: TimeInterval, isCompleted: Bool = false) {
        if var record = playbackRecords[episodeId] {
            record.currentTime = currentTime
            record.duration = duration
            record.lastPlayedDate = Date()
            record.isCompleted = isCompleted
            playbackRecords[episodeId] = record
        } else {
            var newRecord = EpisodePlaybackRecord(episodeId: episodeId, currentTime: currentTime, duration: duration)
            newRecord.isCompleted = isCompleted
            playbackRecords[episodeId] = newRecord
        }
        savePlaybackRecords()
    }
    
    func getPlaybackStatus(for episodeId: String) -> EpisodePlaybackStatus {
        guard let record = playbackRecords[episodeId] else {
            return .notPlayed
        }
        return record.status
    }
    
    func getPlaybackProgress(for episodeId: String) -> Double {
        guard let record = playbackRecords[episodeId] else {
            return 0
        }
        return record.progress
    }
    
    // MARK: - 清理
    
    deinit {
        stopPlaybackTimer()
        cleanupAudioPlayer()
        cancellables.removeAll()
    }
    
    // MARK: - 锁屏显示信息更新
    private func updateNowPlayingInfo() {
        guard let episode = playbackState.currentEpisode else {
            clearNowPlayingInfo()
            return
        }
        
        var nowPlayingInfo = [String: Any]()
        
        // 标题：播客节目标题
        nowPlayingInfo[MPMediaItemPropertyTitle] = episode.title
        
        // 副标题：播客描述（可选）
        if !episode.description.isEmpty {
            nowPlayingInfo[MPMediaItemPropertyArtist] = episode.description
        } else {
            nowPlayingInfo[MPMediaItemPropertyArtist] = "播客节目"
        }
        
        // 专辑标题：当前字幕内容（如果有的话）
        if let currentIndex = playbackState.currentSubtitleIndex,
           currentIndex < currentSubtitles.count {
            let currentSubtitle = currentSubtitles[currentIndex]
            nowPlayingInfo[MPMediaItemPropertyAlbumTitle] = currentSubtitle.text
        }
        
        // 播放时间信息
        nowPlayingInfo[MPMediaItemPropertyPlaybackDuration] = playbackState.duration
        nowPlayingInfo[MPNowPlayingInfoPropertyElapsedPlaybackTime] = playbackState.currentTime
        nowPlayingInfo[MPNowPlayingInfoPropertyPlaybackRate] = playbackState.isPlaying ? NSNumber(value: playbackState.playbackRate) : NSNumber(value: 0.0)
        
        // 设置应用图标
        if let image = UIImage(named: "AppIcon") ?? UIImage(named: "AppIcon60x60") {
            nowPlayingInfo[MPMediaItemPropertyArtwork] = MPMediaItemArtwork(boundsSize: image.size) { _ in
                return image
            }
        }
        
        // 其他信息
        nowPlayingInfo[MPMediaItemPropertyMediaType] = MPMediaType.podcast.rawValue
        
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nowPlayingInfo
        
        print("🎧 [Player] 更新锁屏显示信息: \(episode.title)")
    }
    
    private func clearNowPlayingInfo() {
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
        print("🎧 [Player] 清除锁屏显示信息")
    }
    
    // MARK: - 生词解析功能
    
    /// 分析当前字幕中的生词
    func analyzeVocabulary() async {
        print("🔍 [Vocabulary] 开始生词解析")
        
        guard !currentSubtitles.isEmpty else {
            print("🔍 [Vocabulary] 失败：暂无字幕内容")
            await MainActor.run {
                vocabularyAnalysisState = .failed("暂无字幕内容可分析")
            }
            return
        }
        
        print("🔍 [Vocabulary] 字幕数量: \(currentSubtitles.count)")
        
        await MainActor.run {
            vocabularyAnalysisState = .analyzing
        }
        
        // 合并所有字幕文本
        let fullText = await MainActor.run {
            currentSubtitles.map { $0.text }.joined(separator: " ")
        }
        print("🔍 [Vocabulary] 合并文本长度: \(fullText.count) 字符")
        print("🔍 [Vocabulary] 文本预览: \(String(fullText.prefix(200)))...")
        
        // 使用通用的解析逻辑
        await performVocabularyAnalysis(with: fullText, isSelectiveMode: false)
    }
    
    /// 清理JSON响应，移除markdown格式等
    private func cleanJSONResponse(_ response: String) -> String {
        var cleaned = response.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // 移除可能的markdown代码块标记
        if cleaned.hasPrefix("```json") {
            cleaned = String(cleaned.dropFirst(7))
        }
        if cleaned.hasPrefix("```") {
            cleaned = String(cleaned.dropFirst(3))
        }
        if cleaned.hasSuffix("```") {
            cleaned = String(cleaned.dropLast(3))
        }
        
        // 移除开头和结尾的多余空白
        cleaned = cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // 确保是有效的JSON格式
        if !cleaned.hasPrefix("{") {
            if let startIndex = cleaned.firstIndex(of: "{") {
                cleaned = String(cleaned[startIndex...])
            }
        }
        
        if !cleaned.hasSuffix("}") {
            if let endIndex = cleaned.lastIndex(of: "}") {
                cleaned = String(cleaned[...endIndex])
            }
        }
        
        return cleaned
    }
    
    /// 重置生词解析状态
    func resetVocabularyAnalysis() {
        vocabularyAnalysisState = .idle
    }
    
    /// 分析用户选择的特定单词
    func analyzeSelectedWords(_ selectedWords: Set<String>) async {
        print("🔍 [Vocabulary] 开始选择解析，选中单词数量: \(selectedWords.count)")
        
        guard !selectedWords.isEmpty else {
            print("🔍 [Vocabulary] 失败：未选择任何单词")
            await MainActor.run {
                vocabularyAnalysisState = .failed("请选择要解析的单词")
            }
            return
        }
        
        print("🔍 [Vocabulary] 选中的单词: \(Array(selectedWords).joined(separator: ", "))")
        
        await MainActor.run {
            vocabularyAnalysisState = .analyzing
        }
        
        // 将选中的单词组合成分析文本
        let selectedText = Array(selectedWords).joined(separator: ",")
        print("🔍 [Vocabulary] 分析文本: \(selectedText)")
        
        // 使用相同的提示词和解析逻辑
        await performVocabularyAnalysis(with: selectedText, isSelectiveMode: true)
    }
    
    /// 通用的生词解析逻辑（供全文解析和选择解析共用）
    private func performVocabularyAnalysis(with text: String, isSelectiveMode: Bool = false) async {
        let analysisType = isSelectiveMode ? "选择解析" : "全文解析"
        print("🔍 [Vocabulary] 开始\(analysisType)，文本长度: \(text.count) 字符")
        
        // 构建提示词（与原有逻辑保持一致）
        var prompt = """
        你现在是一位专业的英语教学专家，我是一个英语四级的中国人，你现在正帮我从英语对话或文章中提炼英语中常用的Top25的难词，要求如下：
        1、您的任务是分析给定文本中的所有语言难点，这些难点可能包括对非母语学习者具有挑战性的词汇、短语、俚语、缩写、简写以及网络用语等。
        2、输出请遵循以下要求：
        - 词汇：识别出句子中所有难词，包括短语/词块、俚语、缩写，不常见且不影响理解内容的词汇不用解析。
        - 类型：包括短语/词块、俚语、缩写（Phrases, Slang, Abbreviations）
        - 词性：使用n., v., adj., adv., phrase等标准缩写
        - 音标：提供美式音标
        - 中英混合句子：使用词汇造一个句子，除了该词汇外，其他均为中文，需要保证语法正确，通过在完整中文语境中嵌入单一核心英语术语，帮助学习者直观理解专业概念的实际用法，括号里面是英文句子。
        3、输出示例如下,严格按照json格式输出，需要注意双引号问题：
        {
            "difficult_vocabulary": [
                {
                    "vocabulary": "go for it",
                    "type": "Phrases",
                    "part_of_speech": "phrase",
                    "phonetic": "/ɡoʊ fɔːr ɪt/",
                    "chinese_meaning": "努力争取；放手一搏",
                    "chinese_english_sentence": "这个机会很难得，你应该go for it。（This opportunity is rare, you should go for it.）"
                }
            ]
        }
        处理内容如下：
        \(text)
        """
        
        if(isSelectiveMode){
            prompt = """
            你现在是一位专业的英语教学专家，请帮我解析我提供的英语词汇，要求如下：
            1、请分析我给定的所有英语词汇
            2、输出请遵循以下要求：
            - 词汇：识别出句子中所有难词，包括短语/词块、俚语、缩写，不常见且不影响理解内容的词汇不用解析。
            - 类型：包括短语/词块、俚语、缩写（Phrases, Slang, Abbreviations）
            - 词性：使用n., v., adj., adv., phrase等标准缩写
            - 音标：提供美式音标
            - 中英混合句子：使用词汇造一个句子，除了该词汇外，其他均为中文，需要保证语法正确，通过在完整中文语境中嵌入单一核心英语术语，帮助学习者直观理解专业概念的实际用法，括号里面是英文句子。
            3、输出示例如下,严格按照json格式输出，需要注意双引号问题：
            {
                "difficult_vocabulary": [
                    {
                        "vocabulary": "go for it",
                        "type": "Phrases",
                        "part_of_speech": "phrase",
                        "phonetic": "/ɡoʊ fɔːr ɪt/",
                        "chinese_meaning": "努力争取；放手一搏",
                        "chinese_english_sentence": "这个机会很难得，你应该go for it。（This opportunity is rare, you should go for it.）"
                    }
                ]
            }
            处理内容如下：
            \(text)
            """
        }
        
        print("🔍 [Vocabulary] 提示词长度: \(prompt.count) 字符")
        
        do {
            print("🔍 [Vocabulary] 开始调用LLM服务...")
            let response = try await llmService.sendChatMessage(prompt: prompt)
            print("🔍 [Vocabulary] LLM响应长度: \(response.count) 字符")
            print("🔍 [Vocabulary] LLM响应内容预览: \(String(response.prefix(200)))...")
            
            // 清理响应文本，移除可能的markdown格式
            let cleanedResponse = cleanJSONResponse(response)
            print("🔍 [Vocabulary] 清理后响应: \(cleanedResponse)")
            
            // 解析JSON响应
            if let jsonData = cleanedResponse.data(using: .utf8) {
                print("🔍 [Vocabulary] 开始解析JSON...")
                
                do {
                    let analysisResponse = try JSONDecoder().decode(VocabularyAnalysisResponse.self, from: jsonData)
                    print("🔍 [Vocabulary] JSON解析成功，生词数量: \(analysisResponse.difficultVocabulary.count)")
                    
                    // 打印每个生词的详细信息
                    for (index, vocab) in analysisResponse.difficultVocabulary.enumerated() {
                        print("🔍 [Vocabulary] 生词\(index + 1): \(vocab.vocabulary) - \(vocab.chineseMeaning)")
                    }
                    
                    await MainActor.run {
                        vocabularyAnalysisState = .completed(analysisResponse.difficultVocabulary)
                    }
                } catch let decodingError {
                    print("🔍 [Vocabulary] JSON解析失败: \(decodingError)")
                    await handleJSONDecodingError(decodingError as! DecodingError)
                }
            } else {
                print("🔍 [Vocabulary] 无法将响应转换为UTF8数据")
                await MainActor.run {
                    vocabularyAnalysisState = .failed("响应格式错误：无法转换为数据")
                }
            }
        } catch {
            print("🔍 [Vocabulary] LLM调用失败: \(error)")
            print("🔍 [Vocabulary] 错误详情: \(error.localizedDescription)")
            
            await MainActor.run {
                vocabularyAnalysisState = .failed("分析失败: \(error.localizedDescription)")
            }
        }
    }
    
    /// 处理JSON解码错误的通用方法
    private func handleJSONDecodingError(_ decodingError: DecodingError) async {
        print("🔍 [Vocabulary] 解析错误详情: \(decodingError.localizedDescription)")
        
        var errorDetail = ""
        switch decodingError {
        case .keyNotFound(let key, let context):
            errorDetail = "缺少键: \(key), 上下文: \(context)"
        case .typeMismatch(let type, let context):
            errorDetail = "类型不匹配: \(type), 上下文: \(context)"
        case .valueNotFound(let type, let context):
            errorDetail = "值未找到: \(type), 上下文: \(context)"
        case .dataCorrupted(let context):
            errorDetail = "数据损坏: \(context)"
        @unknown default:
            errorDetail = "未知解析错误"
        }
        
        print("🔍 [Vocabulary] \(errorDetail)")
        
        await MainActor.run {
            vocabularyAnalysisState = .failed("JSON解析失败: \(decodingError.localizedDescription)")
        }
    }
    
    // MARK: - 音频类型判断辅助方法
    
    /// 判断是否为YouTube音频
    private func isYouTubeAudio(_ audioURL: String) -> Bool {
        return audioURL.contains("107.148.21.15:5000/files/audio")
    }
    
    /// 专门为YouTube音频监控播放启动（带网络诊断）
    private func monitorYouTubePlaybackWithNetworkDiagnosis() {
        let checkTimes: [TimeInterval] = [0.2, 0.5, 1.0, 2.0, 3.0, 5.0]  // 减少检查次数，优化时间点
        
        for (index, delay) in checkTimes.enumerated() {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                guard let player = self.audioPlayer else { return }
                
                let rate = player.rate
                let currentTime = player.currentTime().seconds
                let isPlaying = self.playbackState.isPlaying
                
                print("🎧 [Player] YouTube诊断 #\(index + 1) (\(delay)秒后): rate=\(rate), time=\(self.formatTime(currentTime)), isPlaying=\(isPlaying)")
                
                // 检查播放项状态
                if let item = player.currentItem {
                    let bufferEmpty = item.isPlaybackBufferEmpty
                    let likelyToKeepUp = item.isPlaybackLikelyToKeepUp
                    let accessLog = item.accessLog()
                    
                    // 优化用户体验：在缓冲阶段给出更友好的提示
                    if bufferEmpty && !likelyToKeepUp {
                        if index <= 1 {  // 前0.5秒内
                            print("🎧 [Player] YouTube音频正在建立连接... (\(String(format: "%.1f", delay))秒)")
                        } else if index <= 3 {  // 0.5-2秒
                            print("🎧 [Player] YouTube音频缓冲中，即将开始播放... (\(String(format: "%.1f", delay))秒)")
                        } else {  // 2秒后
                            print("🎧 [Player] YouTube音频深度缓冲中，网络可能较慢... (\(String(format: "%.1f", delay))秒)")
                        }
                    } else {
                        print("🎧 [Player] YouTube播放项状态: 缓冲空=\(bufferEmpty), 可流畅播放=\(likelyToKeepUp)")
                    }
                    
                    // 打印网络访问日志信息（简化输出）
                    if let events = accessLog?.events, !events.isEmpty, index == 2 {  // 只在1秒时打印一次
                        let latestEvent = events.last!
                        print("🌐 [Network] 传输状态: 速率=\(Int(latestEvent.observedBitrate/1000))kbps, 服务器=\(latestEvent.serverAddress ?? "YouTube代理")")
                        
                        // 检查是否有网络问题
                        if latestEvent.observedBitrate < 100000 { // 调整到100kbps阈值
                            print("🌐 [Network] ⚠️ 网络速度较慢，播放可能需要更多缓冲时间")
                        }
                    }
                    
                    // 检查加载进度
                    if let timeRange = item.loadedTimeRanges.first?.timeRangeValue {
                        let loadedDuration = CMTimeGetSeconds(CMTimeAdd(timeRange.start, timeRange.duration))
                        if index <= 1 && loadedDuration > 0 {  // 前0.5秒显示加载进度
                            print("🎧 [Player] ✅ 开始缓冲: \(self.formatTime(loadedDuration))")
                        }
                        
                        // 如果缓冲时间足够但仍然无法播放，尝试强制播放
                        if loadedDuration > 2.0 && bufferEmpty && rate == 0 {  // 增加到2秒缓冲
                            print("🎧 [Player] 🔄 缓冲充足，尝试启动播放...")
                            player.play()
                        }
                    }
                    
                    // YouTube音频特殊处理：更温和的播放尝试
                    if isPlaying && rate == 0 {
                        if bufferEmpty {
                            if index <= 2 {  // 前1秒
                                print("🎧 [Player] ⏳ YouTube音频正常缓冲启动中...")
                            } else if index >= 3 { // 2秒后
                                print("🎧 [Player] 🔄 尝试重新连接播放")
                                player.seek(to: CMTime(seconds: 0, preferredTimescale: 1000)) { finished in
                                    if finished {
                                        player.play()
                                    }
                                }
                            }
                        } else {
                            print("🎧 [Player] 🔄 检测到缓冲内容，重启播放")
                            player.play()
                            player.rate = 1.0
                        }
                    }
                    
                    // 检查播放开始情况
                    if rate > 0 && currentTime > 0 {
                        print("🎧 [Player] ✅ YouTube音频播放启动成功！当前播放时间: \(self.formatTime(currentTime))")
                        self.audioPreparationState = .audioReady
                        return
                    }
                }
                
                // 最后一次检查，如果还是没有开始播放，进行最终诊断
                if index == checkTimes.count - 1 && isPlaying && rate == 0 {
                    print("🎧 [Player] ⚠️ YouTube音频5秒后播放启动较慢，进行诊断...")
                    self.performFinalPlaybackDiagnosis()
                }
            }
        }
    }
    
    /// 最终播放诊断
    private func performFinalPlaybackDiagnosis() {
        guard let player = audioPlayer, let item = player.currentItem else {
            print("🔍 [Diagnosis] 播放器或播放项为空")
            return
        }
        
        print("🔍 [Diagnosis] === 最终播放诊断 ===")
        print("🔍 [Diagnosis] 播放器状态: \(player.status.rawValue)")
        print("🔍 [Diagnosis] 播放项状态: \(item.status.rawValue)")
        print("🔍 [Diagnosis] 播放速率: \(player.rate)")
        print("🔍 [Diagnosis] 时间: \(formatTime(player.currentTime().seconds))")
        
        if let error = item.error {
            print("🔍 [Diagnosis] 播放项错误: \(error.localizedDescription)")
        }
        
        if let errorLog = item.errorLog() {
            print("🔍 [Diagnosis] 错误日志事件数: \(errorLog.events.count)")
            for event in errorLog.events {
                print("🔍 [Diagnosis] 错误: \(event.errorComment ?? "无描述")")
            }
        }
        
        // 尝试最后的恢复策略
        print("🔍 [Diagnosis] 尝试最后的恢复策略...")
        
        // 1. 重新设置播放速率
        player.rate = 1.0
        
        // 2. 如果有缓冲内容，强制播放
        if !item.isPlaybackBufferEmpty {
            print("🔍 [Diagnosis] 发现缓冲内容，强制播放")
            player.play()
        }
        
        // 3. 设置错误信息
        if player.rate == 0 {
            errorMessage = "YouTube音频播放启动失败，可能是网络连接或服务器问题"
        }
    }
}

// MARK: - 播放状态模型已在Podcast.swift中定义 

// MARK: - 音频准备状态枚举
enum AudioPreparationState: Equatable {
    case idle           // 空闲状态
    case preparing      // 准备中
    case audioReady     // 已准备好
    case failed(Error)  // 准备失败
    
    // 实现Equatable协议
    static func == (lhs: AudioPreparationState, rhs: AudioPreparationState) -> Bool {
        switch (lhs, rhs) {
        case (.idle, .idle):
            return true
        case (.preparing, .preparing):
            return true
        case (.audioReady, .audioReady):
            return true
        case (.failed, .failed):
            return true // 对于错误状态，我们只比较类型不比较具体错误内容
        default:
            return false
        }
    }
}

