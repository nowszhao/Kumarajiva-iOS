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
    
    // MARK: - 生词标注功能
    @Published var markedWords: Set<String> = []
    @Published var currentEpisodeId: String? = nil
    
    // 设置加载超时
    private var loadingTimeoutTimer: Timer?
    
    // YouTube音频加载进度跟踪
    private var lastLoggedLoadedDuration: TimeInterval = 0
    
    // 异步加载任务跟踪
    private var currentAssetLoadingTask: DispatchWorkItem?
    
    // MARK: - 性能优化
    private var lastSubtitleUpdateTime: TimeInterval = 0
    private let subtitleUpdateInterval: TimeInterval = 0.2 // 最小更新间隔200ms
    
    // MARK: - 锁屏显示信息更新优化
    private var lastNowPlayingUpdateTime: Date = Date.distantPast
    private let nowPlayingUpdateInterval: TimeInterval = 2.0 // 最小更新间隔2秒
    
    private var lastLoggedTime: TimeInterval = 0 // 用于时间更新日志节流
    
    private override init() {
        super.init()
        Task { @MainActor in
        whisperService = WhisperKitService.shared
        }
        setupAudioSession()
        setupRemoteCommandCenter()
        observeTaskManagerUpdates()
        loadPlaybackRecords()
        setupAppLifecycleObservers()
    }
    
    // MARK: - 应用生命周期监听
    private func setupAppLifecycleObservers() {
        // 监听应用进入后台
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(appDidEnterBackground),
            name: UIApplication.didEnterBackgroundNotification,
            object: nil
        )
        
        // 监听应用即将终止
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(appWillTerminate),
            name: UIApplication.willTerminateNotification,
            object: nil
        )
    }
    
    @objc private func appDidEnterBackground() {
        // 保存当前播放位置
        if let episode = playbackState.currentEpisode {
            updatePlaybackRecord(
                for: episode.id,
                currentTime: playbackState.currentTime,
                duration: playbackState.duration
            )
            print("🎧 [Player] 应用进入后台，保存播放位置: \(formatTime(playbackState.currentTime))")
        }
    }
    
    @objc private func appWillTerminate() {
        // 应用即将终止时保存播放位置
        if let episode = playbackState.currentEpisode {
            updatePlaybackRecord(
                for: episode.id,
                currentTime: playbackState.currentTime,
                duration: playbackState.duration
            )
            print("🎧 [Player] 应用即将终止，保存播放位置: \(formatTime(playbackState.currentTime))")
        }
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
    
     
    /// 准备播放节目但不自动开始播放
    func prepareEpisode(_ episode: PodcastEpisode) {
                
        // 重置生成标志
        shouldContinueGeneration = true
        
        // 检查是否是同一个节目
        let isSameEpisode = playbackState.currentEpisode?.id == episode.id
        
        // 清除标注单词（如果切换到不同音频）
        clearMarkedWordsIfNeeded(for: episode.id)
        
        if isSameEpisode && audioPreparationState == .audioReady {
            print("🎧 [Player] 节目已准备且音频就绪: \(episode.title)")
            return
        }
        
        // 保存当前播放时间（如果是同一个节目）
        var savedCurrentTime: TimeInterval = 0
        var savedPlayingState = false
        if isSameEpisode {
            savedCurrentTime = playbackState.currentTime
            savedPlayingState = playbackState.isPlaying
            print("🎧 [Player] 保存当前播放状态: 时间=\(formatTime(savedCurrentTime)), 播放中=\(savedPlayingState)")
        }
        
        // 如果是不同的节目，先完全清空状态
        if !isSameEpisode {
            print("🎧 [Player] 切换到新节目，清空所有状态: \(episode.title)")
            
            // 停止当前播放和清理资源
            pausePlayback()
            cleanupAudioPlayer()
            
            // 重置所有状态
            currentSubtitles = []
            playbackState.currentEpisode = nil
            playbackState.isPlaying = false
            playbackState.currentTime = 0
            playbackState.duration = 0
            playbackState.currentSubtitleIndex = nil
            audioPreparationState = .idle
            audioPreparationProgress = 0.0
            isGeneratingSubtitles = false
            subtitleGenerationProgress = 0.0
            errorMessage = nil
        } else {
            // 同一个节目，只需要停止播放但保持状态
            pausePlayback()
            cleanupAudioPlayer()
            audioPreparationState = .idle
            audioPreparationProgress = 0.0
        }
        
        // 设置新节目
        playbackState.currentEpisode = episode
        
        // 加载已有字幕
        loadExistingSubtitles(for: episode)
        
        // 恢复播放时间（同一个节目）或从播放记录恢复（新节目）
        if isSameEpisode && savedCurrentTime > 0 {
            // 恢复之前的播放时间
            playbackState.currentTime = savedCurrentTime
            playbackState.isPlaying = savedPlayingState
            print("🎧 [Player] 恢复播放状态: 时间=\(formatTime(savedCurrentTime)), 播放中=\(savedPlayingState)")
        } else if !isSameEpisode {
            // 检查是否有播放记录
            if let record = playbackRecords[episode.id],
               record.currentTime > 0 && record.currentTime < record.duration {
                playbackState.currentTime = record.currentTime
                print("🎧 [Player] 从播放记录恢复位置: \(formatTime(record.currentTime))")
            }
        }
        
        // 准备音频但不播放
        prepareAudio(from: episode.audioURL)
        
        print("🎧 [Player] 准备节目（不自动播放）: \(episode.title)")
    }
    
    /// 立即清空当前播放状态，用于切换节目时避免显示旧内容
    func clearCurrentPlaybackState() {
        print("🎧 [Player] 清空当前播放状态")
        
        // 清空字幕
        currentSubtitles = []
        
        // 重置播放状态
        playbackState.currentEpisode = nil
        playbackState.isPlaying = false
        playbackState.currentTime = 0
        playbackState.duration = 0
        playbackState.currentSubtitleIndex = nil
        
        // 重置音频准备状态
        audioPreparationState = .idle
        audioPreparationProgress = 0.0
        
        // 停止字幕生成
        isGeneratingSubtitles = false
        subtitleGenerationProgress = 0.0
        
        // 清除错误信息
        errorMessage = nil
    }
    
    
    private func loadExistingSubtitles(for episode: PodcastEpisode) {
        currentSubtitles = episode.subtitles
        print("🎧 [Player] 加载已有字幕: \(episode.subtitles.count) 条")
        
        // 验证字幕数据质量
        validateSubtitleData()
    }
    
    /// 验证字幕数据质量（调试用）
    private func validateSubtitleData() {
        guard !currentSubtitles.isEmpty else {
            print("⚠️ [Player] 字幕验证：字幕列表为空")
            return
        }
        
        print("🔍 [Player] 字幕数据验证开始...")
        
        var validSubtitles = 0
        var invalidSubtitles = 0
        var totalDuration: TimeInterval = 0
        var shortSubtitles = 0 // 少于0.1秒的字幕
        var veryShortSubtitles = 0 // 少于0.01秒的字幕
        
        for (index, subtitle) in currentSubtitles.enumerated() {
            let duration = subtitle.endTime - subtitle.startTime
            totalDuration += duration
            
            // 检查时间戳有效性
            if subtitle.startTime >= 0 && subtitle.endTime > subtitle.startTime && duration > 0 {
                validSubtitles += 1
                
                if duration < 0.1 {
                    shortSubtitles += 1
                    if duration < 0.01 {
                        veryShortSubtitles += 1
                        print("⚠️ [Player] 极短字幕 [\(index)]: \(String(format: "%.4f", duration))s - '\(subtitle.text)'")
                    }
                }
            } else {
                invalidSubtitles += 1
                print("❌ [Player] 无效字幕 [\(index)]: \(subtitle.startTime) -> \(subtitle.endTime) - '\(subtitle.text)'")
            }
            
            // 详细输出前3个字幕
            if index < 3 {
                print("📝 [Player] 字幕 [\(index)]: \(formatTime(subtitle.startTime)) -> \(formatTime(subtitle.endTime)) (\(String(format: "%.3f", duration))s)")
                print("   文本: '\(subtitle.text)'")
                print("   单词数: \(subtitle.words.count)")
                if !subtitle.words.isEmpty {
                    let firstWord = subtitle.words[0]
                    let lastWord = subtitle.words[subtitle.words.count - 1]
                    print("   单词时间范围: \(formatTime(firstWord.startTime)) -> \(formatTime(lastWord.endTime))")
                }
            }
        }
        
        let averageDuration = totalDuration / Double(currentSubtitles.count)
        
        print("📊 [Player] 字幕数据统计:")
        print("   总数: \(currentSubtitles.count)")
        print("   有效: \(validSubtitles), 无效: \(invalidSubtitles)")
        print("   平均时长: \(String(format: "%.2f", averageDuration))s")
        print("   短字幕(<0.1s): \(shortSubtitles)")
        print("   极短字幕(<0.01s): \(veryShortSubtitles)")
        
        if let firstSubtitle = currentSubtitles.first, let lastSubtitle = currentSubtitles.last {
            print("   时间范围: \(formatTime(firstSubtitle.startTime)) -> \(formatTime(lastSubtitle.endTime))")
        }
        
        // 警告信息
        if veryShortSubtitles > 0 {
            print("⚠️ [Player] 发现 \(veryShortSubtitles) 个极短字幕，可能影响播放体验")
        }
        
        if invalidSubtitles > 0 {
            print("❌ [Player] 发现 \(invalidSubtitles) 个无效字幕，需要检查解析逻辑")
        }
        
        print("🔍 [Player] 字幕数据验证完成\n")
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
                        
                        // 使用音频流时长
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
        
        // 添加时间观察者 - 优化更新频率
        let timeScale = CMTimeScale(NSEC_PER_SEC)
        let time = CMTime(seconds: 0.5, preferredTimescale: timeScale) // 从0.1秒改为0.5秒
        
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
            
            // 跳转到保存的播放位置（如果有）
            if playbackState.currentTime > 0 {
                print("🎧 [Player] 恢复播放位置: \(formatTime(playbackState.currentTime))")
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
                    guard let self = self else { return }
                    self.seek(to: self.playbackState.currentTime)
                    
                    // 如果之前是播放状态，则恢复播放
                    if self.playbackState.isPlaying {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                            self.resumePlayback()
                        }
                    }
                }
            }
            
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
            
            // 节流字幕更新检查
            let now = CACurrentMediaTime()
            if now - lastSubtitleUpdateTime >= subtitleUpdateInterval {
                updateCurrentSubtitleIndex()
                lastSubtitleUpdateTime = now
            }
            
            
            // 减少日志输出频率 - 只在时间有显著变化时输出（每10秒）
            if abs(currentTime - lastLoggedTime) >= 10.0 {
                print("🎧 [Player] 时间更新: \(formatTime(currentTime)) / \(formatTime(playbackState.duration))")
                lastLoggedTime = currentTime
                
                // 在日志输出时检查播放器状态，避免过度频繁检查
                if let player = audioPlayer {
                    print("🎧 [Player] 播放器状态检查: rate=\(player.rate), isPlaying=\(playbackState.isPlaying)")
                    
                    // 检查是否播放卡住了
                    if playbackState.isPlaying && player.rate == 0 {
                        print("🎧 [Player] ⚠️ 检测到播放卡住，尝试恢复播放")
                        player.play()
                    }
                }
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
        
        monitorPlaybackStartup()
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
        
        // 节流机制：限制更新频率，减少性能开销
        let now = CACurrentMediaTime()
        if now - lastSubtitleUpdateTime < subtitleUpdateInterval {
            return
        }
        lastSubtitleUpdateTime = now
        
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
        
        // 改进的字幕匹配逻辑：增加容差和更详细的日志
        var matchedIndex: Int? = nil
        
        for (index, subtitle) in currentSubtitles.enumerated() {
            let timeTolerance: TimeInterval = 0.1 // 100ms 容差
            let isInTimeRange = currentTime >= (subtitle.startTime - timeTolerance) && 
                              currentTime <= (subtitle.endTime + timeTolerance)
            
            if isInTimeRange {
                matchedIndex = index
                
                // 只有在切换到新字幕时才打印日志
                if playbackState.currentSubtitleIndex != index {
                    
                    // 检查是否开启了循环播放且已有当前字幕，不允许自动跳转到下一条字幕
                    if playbackState.isLooping && playbackState.currentSubtitleIndex != nil {
                        print("🎧 [Player] 循环播放模式：阻止自动跳转到下一条字幕")
                        return
                    }
                    
                    playbackState.currentSubtitleIndex = index
                    print("🎧 [Player] ✅ 字幕切换到索引: \(index)")
                }
                return
            }
        }
        
        // 如果没有找到匹配的字幕，清除当前索引（但在循环播放模式下保持当前字幕）
        if playbackState.currentSubtitleIndex != nil && !playbackState.isLooping {
            let previousIndex = playbackState.currentSubtitleIndex!
            print("🎯 [Player] 没有匹配的字幕，清除索引 \(previousIndex) (时间: \(formatTime(currentTime)))")
            
            // 检查最近的字幕，看看是否刚好在间隙中
            if let nearestSubtitle = findNearestSubtitle(to: currentTime) {
                let distance = min(abs(currentTime - nearestSubtitle.subtitle.startTime), 
                                 abs(currentTime - nearestSubtitle.subtitle.endTime))
                print("🎯 [Player] 最近字幕距离: \(String(format: "%.2f", distance))s, 索引: \(nearestSubtitle.index)")
            }
            
            playbackState.currentSubtitleIndex = nil
            print("🎧 [Player] 清除字幕索引：当前无活动字幕")
        }
    }
    
    /// 查找最接近当前时间的字幕（调试用）
    private func findNearestSubtitle(to time: TimeInterval) -> (subtitle: Subtitle, index: Int)? {
        var nearestSubtitle: (subtitle: Subtitle, index: Int)?
        var minDistance = Double.infinity
        
        for (index, subtitle) in currentSubtitles.enumerated() {
            let distanceToStart = abs(time - subtitle.startTime)
            let distanceToEnd = abs(time - subtitle.endTime)
            let distance = min(distanceToStart, distanceToEnd)
            
            if distance < minDistance {
                minDistance = distance
                nearestSubtitle = (subtitle, index)
            }
        }
        
        return nearestSubtitle
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
        do {
            // 首先尝试从持久化存储加载
            if let records: [String: EpisodePlaybackRecord] = try PersistentStorageManager.shared.loadPlaybackRecords([String: EpisodePlaybackRecord].self) {
                playbackRecords = records
                print("🎧 [Player] 从持久化存储加载播放历史记录: \(records.count) 条")
                return
            }
        } catch {
            print("🎧 [Player] 从持久化存储加载失败，尝试UserDefaults迁移: \(error)")
        }
        
        // 如果持久化存储失败，尝试从UserDefaults迁移
        if let data = UserDefaults.standard.data(forKey: playbackRecordsKey),
           let records = try? JSONDecoder().decode([String: EpisodePlaybackRecord].self, from: data) {
            playbackRecords = records
            
            // 迁移到持久化存储
            do {
                try PersistentStorageManager.shared.savePlaybackRecords(records)
                print("🎧 [Player] 成功迁移播放历史记录到持久化存储: \(records.count) 条")
                // 可选择性清除UserDefaults
                // UserDefaults.standard.removeObject(forKey: playbackRecordsKey)
            } catch {
                print("🎧 [Player] 迁移播放历史记录到持久化存储失败: \(error)")
            }
            
            print("🎧 [Player] 从UserDefaults加载播放历史记录: \(records.count) 条")
        }
    }
    
    private func savePlaybackRecords() {
        do {
            try PersistentStorageManager.shared.savePlaybackRecords(playbackRecords)
        } catch {
            print("🎧 [Player] 保存播放历史记录失败: \(error)")
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
        
        // 清理NotificationCenter observers
        NotificationCenter.default.removeObserver(self)
    }
    
    // MARK: - 锁屏显示信息更新
    private func updateNowPlayingInfo() {
        if(1==1){
            return
        }
        
        // 节流机制：避免过于频繁的更新
        let now = Date()
        if now.timeIntervalSince(lastNowPlayingUpdateTime) < nowPlayingUpdateInterval {
            return
        }
        lastNowPlayingUpdateTime = now
        
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
    
    /// 分析已标注的单词（新增方法）
    func analyzeMarkedWords() async {
        print("🔍 [Vocabulary] 开始解析已标注单词，数量: \(markedWords.count)")
        
        guard !markedWords.isEmpty else {
            print("🔍 [Vocabulary] 失败：未标注任何单词")
            await MainActor.run {
                vocabularyAnalysisState = .failed("请先在听力模式中标注单词")
            }
            return
        }
        
        print("🔍 [Vocabulary] 标注的单词: \(Array(markedWords).joined(separator: ", "))")
        
        await MainActor.run {
            vocabularyAnalysisState = .analyzing
        }
        
        // 使用标注的单词进行分析
        let markedText = Array(markedWords).joined(separator: ",")
        print("🔍 [Vocabulary] 分析文本: \(markedText)")
        
        // 使用选择解析模式
        await performVocabularyAnalysis(with: markedText, isSelectiveMode: true)
    }
    
    /// 通用的生词解析逻辑（供全文解析和选择解析共用）
    private func performVocabularyAnalysis(with text: String, isSelectiveMode: Bool = false) async {
        let analysisType = isSelectiveMode ? "选择解析" : "全文解析"
        print("🔍 [Vocabulary] 开始\(analysisType)，文本长度: \(text.count) 字符")
        
        // 构建提示词（与原有逻辑保持一致）
        var prompt = """
            英语教学专家指令：文本词汇难点分析与Top25提炼（针对英语四级学习者）
            - 我是谁： 你是一位专业的英语教学专家。
            - 你在做什么： 你正在帮助一位英语四级水平的中国学习者分析一段具体的英语对话或文章，从中提炼出对该学习者而言最具挑战性的词汇和语言点（Top25）。
            - 你将获得什么输入： 用户会提供一段英文文本（对话、文章片段等）。
            - 你的核心任务： 分析提供的文本，识别其中的语言难点，包括：
            1.  对四级水平学习者可能构成挑战的词汇、短语/词块、俚语、缩写、网络用语等。
            2.  注意：不常见且不影响理解内容核心思想的词汇可以忽略。
            - 输出要求（严格JSON格式）：
            {
                "difficult_vocabulary": [
                    {
                        "vocabulary": "目标词汇/短语",       // 如 "go for it", "ASAP", "lit"
                        "type": "Phrases/Slang/Abbreviations", // 选择最恰当的类型
                        "part_of_speech": "n./v./adj./adv./phrase/etc.", // 使用标准缩写
                        "phonetic": "/美式音标/",             // 如 "/ɡoʊ fɔːr ɪt/"
                        "chinese_meaning": "准确的中文释义",     // 如 "努力争取；放手一搏"
                        "chinese_english_sentence": "在这个完整的中文句子中自然地嵌入'目标词汇'"
                        // 示例： "这个机会很难得，你应该go for it。（This opportunity is rare, you should go for it.）"
                    },
                    // ... 最多提炼25个项目
                ]
            }

            - 处理流程：
            1.  等待用户提供具体的英文文本内容（放在下方）。
            2.  分析该文本。
            3.  识别出符合要求的难点词汇（最多Top25，按挑战性或必要性排序）。
            4.  严格按以上JSON格式输出结果。

            文本输入区：
            ###
            \(text)
            ###
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
    
    // MARK: - 播放列表管理
    
    /// 删除指定节目的播放记录
    func removePlaybackRecord(episodeId: String) {
        playbackRecords.removeValue(forKey: episodeId)
        savePlaybackRecords()
        print("🎧 [Player] 删除播放记录: \(episodeId)")
    }
    
    /// 清空所有播放记录
    func clearAllPlaybackRecords() {
        playbackRecords.removeAll()
        savePlaybackRecords()
        print("🎧 [Player] 清空所有播放记录")
    }
    
    /// 获取播放列表中的节目信息（增强版，支持YouTube视频）
    func getEpisodeFromRecord(_ record: EpisodePlaybackRecord) -> PodcastEpisode? {
        // 检查当前播放的节目是否匹配
        if let currentEpisode = playbackState.currentEpisode,
           currentEpisode.id == record.episodeId {
            return currentEpisode
        }
        
        // 首先从数据服务中获取episode信息（RSS播客）
        if let episode = PodcastDataService.shared.getEpisode(by: record.episodeId) {
            return episode
        }
        
        // 对于YouTube视频，我们需要返回一个占位Episode，让UI能正常显示
        // 真正的播放会在playEpisodeFromRecord中异步处理
        if record.episodeId.count == 11 && record.episodeId.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "_" || $0 == "-" }) {
//            print("🎧 [Player] 检测到YouTube视频ID，创建占位Episode: \(record.episodeId)")
            
            // 创建一个占位Episode用于显示
            return PodcastEpisode(
                id: record.episodeId,
                title: "正在加载视频信息...",
                description: "YouTube视频",
                audioURL: "", // 空的，需要重新提取
                duration: record.duration,
                publishDate: record.lastPlayedDate
            )
        }
        
        return nil
    }
    
    /// 从YouTube数据服务获取视频信息（异步版本）
    @MainActor
    private func getYouTubeVideoById(_ videoId: String) async -> YouTubeVideo? {
        let youtubeService = YouTubeDataService.shared
        
        // 遍历所有订阅的YouTuber查找视频
        for youtuber in youtubeService.youtubers {
            if let video = youtuber.videos.first(where: { $0.videoId == videoId }) {
                return video
            }
        }
        
        print("🎧 [Player] YouTube视频未在订阅列表中找到: \(videoId)")
        return nil
    }
    
    /// 从播放记录恢复播放episode（增强版，支持YouTube视频）
    func playEpisodeFromRecord(_ record: EpisodePlaybackRecord) {
        print("🎧 [Player] 从播放记录恢复播放: \(record.episodeId)")
        
        // 如果是当前播放的节目，只需要切换播放状态
        if let currentEpisode = playbackState.currentEpisode,
           currentEpisode.id == record.episodeId {
            print("🎧 [Player] 切换当前播放节目的播放状态")
            togglePlayPause()
            return
        }
        
        // 获取完整的episode信息
        guard let episode = getEpisodeFromRecord(record) else {
            print("🎧 [Player] ❌ 无法找到对应的episode: \(record.episodeId)")
            errorMessage = "无法找到该播客节目，可能已被删除"
            return
        }
        
        print("🎧 [Player] ✅ 找到episode: \(episode.title)")
        
        // 检查是否为YouTube视频且缺少音频URL
        if episode.audioURL.isEmpty && isYouTubeVideoId(record.episodeId) {
            print("🎧 [Player] 检测到YouTube视频缺少音频URL，开始重新提取...")
            
            // 异步重新提取YouTube音频URL
            Task {
                await reextractYouTubeAudio(for: episode, record: record)
            }
            return
        }
        
        // 准备播放新的episode
        prepareEpisode(episode)
        
        // 跳转到上次播放的位置
        if record.currentTime > 0 && record.currentTime < record.duration {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                self?.seek(to: record.currentTime)
                print("🎧 [Player] 跳转到上次播放位置: \(self?.formatTime(record.currentTime) ?? "0:00")")
            }
        }
        
        // 开始播放
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
            self?.resumePlayback()
            print("🎧 [Player] 开始播放恢复的episode")
        }
    }
    
    /// 重新提取YouTube音频URL并开始播放
    private func reextractYouTubeAudio(for episode: PodcastEpisode, record: EpisodePlaybackRecord) async {
        do {
            print("🎧 [Player] 开始处理YouTube视频: \(episode.id)")
            
            // 首先尝试从YouTube数据服务获取视频信息
            if let youtubeVideo = await getYouTubeVideoById(episode.id) {
                print("🎧 [Player] ✅ 从YouTube数据服务找到视频信息: \(youtubeVideo.title)")
                
                // 检查是否有有效的音频URL
                if let audioURL = youtubeVideo.audioURL, !audioURL.isEmpty {
                    await MainActor.run {
                        // 使用现有的音频URL
                        let updatedEpisode = PodcastEpisode(
                            id: youtubeVideo.videoId,
                            title: youtubeVideo.title,
                            description: youtubeVideo.description ?? "",
                            audioURL: audioURL,
                            duration: youtubeVideo.duration,
                            publishDate: youtubeVideo.publishDate,
                            subtitles: youtubeVideo.subtitles
                        )
                        
                        self.startPlaybackWithRecord(updatedEpisode, record: record)
                    }
                    return
                }
            }
            
            print("🎧 [Player] 需要重新提取YouTube音频: \(episode.id)")
            
            // 使用YouTubeAudioExtractor重新提取音频
            let downloadResult = try await YouTubeAudioExtractor.shared.extractAudioAndSubtitles(from: episode.id)
            
            await MainActor.run {
                print("🎧 [Player] ✅ YouTube音频重新提取成功")
                
                // 创建更新的episode
                let updatedEpisode = PodcastEpisode(
                    id: episode.id,
                    title: downloadResult.videoInfo?.title ?? episode.title,
                    description: downloadResult.videoInfo?.description ?? episode.description,
                    audioURL: downloadResult.audioURL,
                    duration: downloadResult.videoInfo?.duration ?? episode.duration,
                    publishDate: episode.publishDate,
                    subtitles: downloadResult.subtitles.isEmpty ? episode.subtitles : downloadResult.subtitles
                )
                
                self.startPlaybackWithRecord(updatedEpisode, record: record)
            }
            
        } catch {
            await MainActor.run {
                print("🎧 [Player] ❌ YouTube音频处理失败: \(error)")
                self.errorMessage = "无法加载该YouTube视频的音频，请稍后重试"
            }
        }
    }
    
    /// 启动播放并跳转到记录位置的通用方法
    private func startPlaybackWithRecord(_ episode: PodcastEpisode, record: EpisodePlaybackRecord) {
        // 准备播放
        self.prepareEpisode(episode)
        
        // 跳转到上次播放的位置
        if record.currentTime > 0 && record.currentTime < record.duration {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                self?.seek(to: record.currentTime)
                print("🎧 [Player] 跳转到上次播放位置: \(self?.formatTime(record.currentTime) ?? "0:00")")
            }
        }
        
        // 开始播放
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
            self?.resumePlayback()
            print("🎧 [Player] 开始播放YouTube音频")
        }
    }
    
    /// 检查是否为YouTube视频ID格式
    private func isYouTubeVideoId(_ id: String) -> Bool {
        return id.count == 11 && id.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "_" || $0 == "-" })
    }
    
    // MARK: - 生词标注功能
    
    /// 切换音频时清除标注单词
    func clearMarkedWordsIfNeeded(for episodeId: String) {
        if currentEpisodeId != episodeId {
            print("🎧 [Player] 切换音频，清除标注单词: \(markedWords.count) 个")
            markedWords.removeAll()
            currentEpisodeId = episodeId
        } else if currentEpisodeId == nil {
            currentEpisodeId = episodeId
        }
    }
    
    /// 添加或移除标注单词
    func toggleMarkedWord(_ word: String) {
        let cleanWord = cleanWordForMarking(word)
        
        if markedWords.contains(cleanWord) {
            markedWords.remove(cleanWord)
            print("🔖 [Player] 移除标注单词: \(cleanWord)")
        } else {
            markedWords.insert(cleanWord)
            print("🔖 [Player] 添加标注单词: \(cleanWord)")
        }
        
        // 限制标注单词数量，避免性能问题
        if markedWords.count > 100 {
            print("🔖 [Player] ⚠️ 标注单词过多，自动清理最旧的标注")
            let wordsArray = Array(markedWords)
            markedWords = Set(wordsArray.suffix(80)) // 保留最新的80个
        }
    }
    
    /// 检查单词是否已标注
    func isWordMarked(_ word: String) -> Bool {
        let cleanWord = cleanWordForMarking(word)
        return markedWords.contains(cleanWord)
    }
    
    /// 清理单词以用于标注（移除标点符号，转换为小写）
    private func cleanWordForMarking(_ word: String) -> String {
        return word.lowercased()
            .trimmingCharacters(in: .punctuationCharacters)
            .trimmingCharacters(in: .whitespaces)
    }
    
    /// 获取所有标注的单词
    func getMarkedWords() -> [String] {
        return Array(markedWords).sorted()
    }
    
    /// 清除所有标注单词
    func clearAllMarkedWords() {
        let count = markedWords.count
        markedWords.removeAll()
        print("🔖 [Player] 清除所有标注单词: \(count) 个")
    }
    
    /// 获取标注单词数量
    var markedWordCount: Int {
        return markedWords.count
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

