import Foundation
import Combine
import AVFoundation
import WhisperKit
import MediaPlayer

class PodcastPlayerService: NSObject, ObservableObject, AVAudioPlayerDelegate {
    static let shared = PodcastPlayerService()
    
    // MARK: - Published Properties
    @Published var playbackState = PodcastPlaybackState()
    @Published var currentSubtitles: [Subtitle] = []
    @Published var errorMessage: String?
    
    // 字幕生成状态（基于任务管理器）
    @Published var isGeneratingSubtitles: Bool = false
    @Published var subtitleGenerationProgress: Double = 0.0
    
    // 播放历史记录
    @Published var playbackRecords: [String: EpisodePlaybackRecord] = [:]
    
    // MARK: - Private Properties
    private var audioPlayer: AVAudioPlayer?
    private var playbackTimer: Timer?
    private var cancellables = Set<AnyCancellable>()
    private var shouldContinueGeneration = true
    private var whisperService: WhisperKitService!
    private var isSubtitleLooping = false // 标记是否正在进行字幕循环播放
    private let playbackRecordsKey = "podcast_playback_records"
    
    // MARK: - 生词解析相关
    @Published var vocabularyAnalysisState: VocabularyAnalysisState = .idle
    private let llmService = LLMService.shared
    
    private override init() {
        super.init()
        whisperService = WhisperKitService.shared
        setupAudioSession()
        setupRemoteCommandCenter()
        observeTaskManagerUpdates()
        loadPlaybackRecords()
    }
    
    // MARK: - 任务管理器状态监听
    private func observeTaskManagerUpdates() {
        // 监听任务管理器的状态变化
        Timer.publish(every: 0.5, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                Task { @MainActor in
                    self?.updateGenerationState()
                }
            }
            .store(in: &cancellables)
    }
    
    private func updateGenerationState() {
        guard let episode = playbackState.currentEpisode else {
            isGeneratingSubtitles = false
            subtitleGenerationProgress = 0.0
            return
        }
        
        let taskManager = SubtitleGenerationTaskManager.shared
        let hasActiveTask = taskManager.hasActiveTask(for: episode.id)
        let progress = taskManager.getTask(for: episode.id)?.progress ?? 0.0
        
        if isGeneratingSubtitles != hasActiveTask {
            isGeneratingSubtitles = hasActiveTask
        }
        
        if abs(subtitleGenerationProgress - progress) > 0.01 {
            subtitleGenerationProgress = progress
        }
        
        // 如果任务完成，更新字幕
        if let task = taskManager.getTask(for: episode.id), task.isCompleted {
            currentSubtitles = task.generatedSubtitles
        }
    }
    
    // MARK: - 字幕生成状态文本
    var subtitleGenerationStatusText: String {
        guard let episode = playbackState.currentEpisode,
              let task = SubtitleGenerationTaskManager.shared.getTask(for: episode.id) else {
            return ""
        }
        return task.statusMessage
    }
    
    // MARK: - 播放状态检查
    var isPlaying: Bool {
        let hasEpisode = playbackState.currentEpisode != nil
        let isPlayingState = playbackState.isPlaying
        let hasAudioPlayer = audioPlayer != nil
        let audioPlayerIsPlaying = audioPlayer?.isPlaying ?? false
        
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
        
        // 上一个命令（上一句字幕）
        commandCenter.previousTrackCommand.addTarget { [weak self] _ in
            self?.previousSubtitle()
            return .success
        }
        
        // 下一个命令（下一句字幕）
        commandCenter.nextTrackCommand.addTarget { [weak self] _ in
            self?.nextSubtitle()
            return .success
        }
    }
    
    // MARK: - 播放控制
    func playEpisode(_ episode: PodcastEpisode) {
        // 重置生成标志
        shouldContinueGeneration = true
        
        playbackState.currentEpisode = episode
        playbackState.isPlaying = false
        playbackState.currentTime = 0
        
        // 加载已有字幕
        loadExistingSubtitles(for: episode)
        
        // 开始播放音频
        loadAndPlayAudio(from: episode.audioURL)
        
        // 移除自动字幕生成逻辑，改为手动触发
        // 用户需要通过"重新转录字幕"按钮手动生成字幕
        
        print("🎧 [Player] 开始播放节目: \(episode.title)")
    }
    
    /// 准备播放节目但不自动开始播放
    func prepareEpisode(_ episode: PodcastEpisode) {
        // 如果是同一个节目，不需要重新准备
        if playbackState.currentEpisode?.id == episode.id {
            print("🎧 [Player] 节目已准备: \(episode.title)")
            return
        }
        
        // 重置生成标志
        shouldContinueGeneration = true
        
        playbackState.currentEpisode = episode
        // 不自动设置为播放状态
        playbackState.currentTime = 0
        
        // 加载已有字幕
        loadExistingSubtitles(for: episode)
        
        // 准备音频但不播放
        prepareAudio(from: episode.audioURL)
        
        // 移除自动字幕生成逻辑，改为手动触发
        // 用户需要通过"重新转录字幕"按钮手动生成字幕
        
        print("🎧 [Player] 准备节目（不自动播放）: \(episode.title)")
    }
    
    private func loadExistingSubtitles(for episode: PodcastEpisode) {
        currentSubtitles = episode.subtitles
        print("🎧 [Player] 加载已有字幕: \(episode.subtitles.count) 条")
    }
    
    private func loadAndPlayAudio(from urlString: String) {
        guard let url = URL(string: urlString) else {
            errorMessage = "无效的音频URL"
            return
        }
        
        Task {
            do {
                let (data, _) = try await URLSession.shared.data(from: url)
                
                await MainActor.run {
                    // 检查是否仍有当前节目（防止在加载过程中被停止）
                    guard self.playbackState.currentEpisode != nil else {
                        print("🎧 [Player] 音频加载完成但播放已停止，跳过播放")
            return
        }
        
                    do {
                        self.audioPlayer = try AVAudioPlayer(data: data)
                        self.audioPlayer?.prepareToPlay()
                        
                        // 启用速度控制和设置代理
                        self.audioPlayer?.enableRate = true
                        self.audioPlayer?.rate = self.playbackState.playbackRate
                        self.audioPlayer?.delegate = self
                        
                        self.playbackState.duration = self.audioPlayer?.duration ?? 0
                        self.startPlayback()
                    } catch {
                        self.errorMessage = "音频播放失败: \(error.localizedDescription)"
                    }
                }
            } catch {
                await MainActor.run {
                    self.errorMessage = "音频加载失败: \(error.localizedDescription)"
                }
            }
        }
    }
    
    private func prepareAudio(from urlString: String) {
        guard let url = URL(string: urlString) else {
            errorMessage = "无效的音频URL"
            return
        }
        
        Task {
            do {
                let (data, _) = try await URLSession.shared.data(from: url)
            
            await MainActor.run {
                    // 检查是否仍有当前节目（防止在加载过程中被停止）
                    guard self.playbackState.currentEpisode != nil else {
                        print("🎧 [Player] 音频加载完成但播放已停止，跳过准备")
                        return
                    }
                    
                    do {
                        self.audioPlayer = try AVAudioPlayer(data: data)
                        self.audioPlayer?.prepareToPlay()
                        
                        // 启用速度控制和设置代理
                        self.audioPlayer?.enableRate = true
                        self.audioPlayer?.rate = self.playbackState.playbackRate
                        self.audioPlayer?.delegate = self
                        
                        self.playbackState.duration = self.audioPlayer?.duration ?? 0
                        // 不自动开始播放，只准备音频
                        print("🎧 [Player] 音频准备完成，等待用户操作")
                    } catch {
                        self.errorMessage = "音频准备失败: \(error.localizedDescription)"
                    }
                }
        } catch {
            await MainActor.run {
                    self.errorMessage = "音频加载失败: \(error.localizedDescription)"
                }
            }
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
        startPlaybackTimer()
        
        // 更新锁屏显示信息
        updateNowPlayingInfo()
        
        print("🎧 [Player] 开始播放: \(playbackState.currentEpisode?.title ?? "未知")")
    }
    
    func pausePlayback() {
        audioPlayer?.pause()
        playbackState.isPlaying = false
        stopPlaybackTimer()
        
        // 更新锁屏显示信息
        updateNowPlayingInfo()
    }
    
    func resumePlayback() {
        audioPlayer?.play()
        playbackState.isPlaying = true
        startPlaybackTimer()
        
        // 更新锁屏显示信息
        updateNowPlayingInfo()
    }
    
    func stopPlayback() {
        // 完全停止播放，清除所有状态
        cancelSubtitleGeneration()
        
        audioPlayer?.stop()
        audioPlayer = nil
        playbackState.isPlaying = false
        playbackState.currentTime = 0
        playbackState.currentSubtitleIndex = nil
        playbackState.currentEpisode = nil
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
        audioPlayer?.currentTime = time
        playbackState.currentTime = time
    }
    
    func togglePlayPause() {
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
        player.enableRate = true
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
    
    var hasPreviousSubtitle: Bool {
        guard let currentIndex = playbackState.currentSubtitleIndex else { return false }
        return currentIndex > 0
    }
    
    var hasNextSubtitle: Bool {
        guard let currentIndex = playbackState.currentSubtitleIndex else { return false }
        return currentIndex < currentSubtitles.count - 1
    }
    
    func formatTime(_ time: TimeInterval) -> String {
        let minutes = Int(time) / 60
        let seconds = Int(time) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
    
    private func startPlaybackTimer() {
        playbackTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            guard let self = self, let player = self.audioPlayer else { return }
            
            DispatchQueue.main.async {
                self.updatePlaybackTime()
            }
        }
    }
    
    private func updatePlaybackTime() {
        guard let player = audioPlayer else { return }
        
        self.playbackState.currentTime = player.currentTime
        
        // 检查播放器状态，如果停止了但我们的状态还是播放中，则更新状态
        if !player.isPlaying && self.playbackState.isPlaying {
            self.playbackState.isPlaying = false
        }
        
        // 更新播放历史记录
        if let episode = playbackState.currentEpisode {
            updatePlaybackRecord(
                for: episode.id,
                currentTime: player.currentTime,
                duration: playbackState.duration
            )
        }
        
        // 更新字幕索引
        updateCurrentSubtitleIndex()
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
    
    private func stopPlaybackTimer() {
        playbackTimer?.invalidate()
        playbackTimer = nil
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
        guard let episode = playbackState.currentEpisode else {
            errorMessage = "没有正在播放的节目"
            return
        }
        
        // 如果已经有字幕，询问是否重新生成
        if !episode.subtitles.isEmpty {
            print("🎧 [Player] 节目已有字幕，重新生成...")
        }
        
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
        let fullText = currentSubtitles.map { $0.text }.joined(separator: " ")
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
        audioPlayer?.stop()
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
}

// MARK: - AVAudioPlayerDelegate
extension PodcastPlayerService {
    
    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        print("🎧 [Player] 音频播放完成，成功: \(flag)")
        
        // 标记播放完成
        if let episode = playbackState.currentEpisode {
            updatePlaybackRecord(
                for: episode.id,
                currentTime: playbackState.duration,
                duration: playbackState.duration,
                isCompleted: true
            )
        }
        
        if flag && playbackState.isLooping {
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
    
    func audioPlayerDecodeErrorDidOccur(_ player: AVAudioPlayer, error: Error?) {
        print("🎧 [Player] 音频解码错误: \(error?.localizedDescription ?? "未知错误")")
        errorMessage = "音频播放错误: \(error?.localizedDescription ?? "未知错误")"
        playbackState.isPlaying = false
        stopPlaybackTimer()
    }
    
    func audioPlayerBeginInterruption(_ player: AVAudioPlayer) {
        print("🎧 [Player] 音频播放被中断")
        pausePlayback()
    }
    
    func audioPlayerEndInterruption(_ player: AVAudioPlayer, withOptions flags: Int) {
        print("🎧 [Player] 音频播放中断结束")
        // 可以选择自动恢复播放或让用户手动恢复
        // resumePlayback()
    }
}

// MARK: - 播放状态模型已在Podcast.swift中定义 
