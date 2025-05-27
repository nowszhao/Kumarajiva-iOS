import Foundation
import Combine
import WhisperKit
import AVFoundation

// MARK: - 字幕生成任务状态
enum SubtitleGenerationTaskStatus {
    case pending        // 等待开始
    case downloading    // 下载音频
    case processing     // 处理音频格式
    case transcribing   // 语音识别
    case finalizing     // 最终处理
    case completed      // 完成
    case failed(Error)  // 失败
    case cancelled      // 已取消
}

// MARK: - 字幕生成任务
class SubtitleGenerationTask: ObservableObject, Identifiable {
    let id = UUID()
    let episodeId: String
    let episodeName: String
    let audioURL: URL
    let quality: SubtitleQuality
    let createdAt: Date
    
    @Published var status: SubtitleGenerationTaskStatus = .pending
    @Published var progress: Double = 0.0
    @Published var statusMessage: String = "等待开始..."
    @Published var generatedSubtitles: [Subtitle] = []
    @Published var errorMessage: String?
    
    private var task: Task<Void, Never>?
    private var progressTask: Task<Void, Never>?
    
    init(episodeId: String, episodeName: String, audioURL: URL, quality: SubtitleQuality = .medium) {
        self.episodeId = episodeId
        self.episodeName = episodeName
        self.audioURL = audioURL
        self.quality = quality
        self.createdAt = Date()
    }
    
    func start() {
        guard task == nil else { return }
        
        task = Task { @MainActor in
            await executeTask()
        }
    }
    
    func cancel() {
        task?.cancel()
        progressTask?.cancel()
        
        Task { @MainActor in
            self.status = .cancelled
            self.statusMessage = "任务已取消"
            print("🎯 [TaskManager] 任务已取消: \(episodeName)")
        }
    }
    
    var isActive: Bool {
        switch status {
        case .pending, .downloading, .processing, .transcribing, .finalizing:
            return true
        case .cancelled, .completed, .failed:
            return false
        }
    }
    
    var isCancelled: Bool {
        switch status {
        case .cancelled:
            return true
        default:
            return false
        }
    }
    
    var isCompleted: Bool {
        switch status {
        case .completed:
            return true
        default:
            return false
        }
    }
    
    var isFailed: Bool {
        switch status {
        case .failed:
            return true
        default:
            return false
        }
    }
    
    // MARK: - 私有方法
    
    @MainActor
    private func executeTask() async {
        do {
            print("🎯 [TaskManager] 开始执行任务: \(episodeName)")
            
            // 阶段1: 下载音频 (0% - 20%)
            await updateStatus(.downloading, progress: 0.0, message: "正在下载音频文件...")
            let tempAudioURL = try await downloadAudio()
            await updateProgress(0.2, message: "音频下载完成")
            
            // 检查取消状态
            try Task.checkCancellation()
            
            // 阶段2: 处理音频格式 (20% - 30%)
            await updateStatus(.processing, progress: 0.2, message: "正在处理音频格式...")
            let processedAudioURL = try await processAudioForWhisper(tempAudioURL)
            await updateProgress(0.3, message: "音频格式处理完成")
            
            // 检查取消状态
            try Task.checkCancellation()
            
            // 阶段3: 语音识别 (30% - 90%)
            await updateStatus(.transcribing, progress: 0.3, message: "正在进行语音识别...")
            let result = try await transcribeAudioWithProgress(processedAudioURL)
            await updateProgress(0.9, message: "语音识别完成")
            
            // 检查取消状态
            try Task.checkCancellation()
            
            // 阶段4: 最终处理 (90% - 100%)
            await updateStatus(.finalizing, progress: 0.9, message: "正在整理字幕...")
            let subtitles = await createSubtitlesFromResult(result)
            self.generatedSubtitles = subtitles
            
            // 保存字幕到数据库
            await saveSubtitlesToDatabase(subtitles)
            
            // 完成
            await updateStatus(.completed, progress: 1.0, message: "字幕生成完成！")
            
            // 清理临时文件
            try? FileManager.default.removeItem(at: tempAudioURL)
            if tempAudioURL != processedAudioURL {
                try? FileManager.default.removeItem(at: processedAudioURL)
            }
            
            print("🎯 [TaskManager] 任务完成: \(episodeName), 生成 \(subtitles.count) 条字幕")
            
        } catch is CancellationError {
            await updateStatus(.cancelled, progress: progress, message: "任务已取消")
            print("🎯 [TaskManager] 任务被取消: \(episodeName)")
        } catch {
            await updateStatus(.failed(error), progress: progress, message: "生成失败: \(error.localizedDescription)")
            self.errorMessage = error.localizedDescription
            print("🎯 [TaskManager] 任务失败: \(episodeName), 错误: \(error)")
        }
    }
    
    @MainActor
    private func updateStatus(_ newStatus: SubtitleGenerationTaskStatus, progress: Double, message: String) {
        self.status = newStatus
        self.progress = progress
        self.statusMessage = message
    }
    
    @MainActor
    private func updateProgress(_ newProgress: Double, message: String) {
        self.progress = newProgress
        self.statusMessage = message
    }
    
    private func downloadAudio() async throws -> URL {
        let (tempURL, response) = try await URLSession.shared.download(from: audioURL)
        
        // 检查下载的文件大小
        let fileSize = try FileManager.default.attributesOfItem(atPath: tempURL.path)[.size] as? Int64 ?? 0
        guard fileSize > 1024 else { // 至少1KB
            throw NSError(domain: "SubtitleGenerationTask", code: 1007, userInfo: [NSLocalizedDescriptionKey: "下载的音频文件太小或为空"])
        }
        
        // 根据Content-Type和URL推断文件扩展名
        var inferredExtension = "mp3" // 默认扩展名
        
        if let httpResponse = response as? HTTPURLResponse,
           let contentType = httpResponse.value(forHTTPHeaderField: "Content-Type") {
            switch contentType.lowercased() {
            case let ct where ct.contains("audio/mpeg"):
                inferredExtension = "mp3"
            case let ct where ct.contains("audio/mp4"), let ct where ct.contains("audio/m4a"):
                inferredExtension = "m4a"
            case let ct where ct.contains("audio/wav"):
                inferredExtension = "wav"
            case let ct where ct.contains("audio/aac"):
                inferredExtension = "aac"
            default:
                // 回退到URL扩展名
                let urlExtension = audioURL.pathExtension.lowercased()
                if !urlExtension.isEmpty && ["mp3", "m4a", "wav", "aac"].contains(urlExtension) {
                    inferredExtension = urlExtension
                }
            }
        } else {
            // 没有Content-Type，使用URL扩展名
            let urlExtension = audioURL.pathExtension.lowercased()
            if !urlExtension.isEmpty && ["mp3", "m4a", "wav", "aac"].contains(urlExtension) {
                inferredExtension = urlExtension
            }
        }
        
        // 创建带正确扩展名的临时文件
        let tempDirectory = FileManager.default.temporaryDirectory
        let correctExtensionURL = tempDirectory.appendingPathComponent("task_\(id.uuidString).\(inferredExtension)")
        
        try FileManager.default.moveItem(at: tempURL, to: correctExtensionURL)
        
        print("🎯 [TaskManager] 音频下载完成: \(correctExtensionURL.lastPathComponent), 大小: \(fileSize) bytes, 类型: \(inferredExtension)")
        
        return correctExtensionURL
    }
    
    private func processAudioForWhisper(_ inputURL: URL) async throws -> URL {
        // 首先验证文件是否可以被AVAudioFile读取
        do {
            let audioFile = try AVAudioFile(forReading: inputURL)
            let duration = Double(audioFile.length) / audioFile.fileFormat.sampleRate
            
            print("🎯 [TaskManager] 音频文件验证成功: 时长 \(duration) 秒, 格式: \(audioFile.fileFormat)")
            
            // 如果文件可以直接读取，检查格式是否被WhisperKit支持
            let pathExtension = inputURL.pathExtension.lowercased()
            let supportedFormats = ["mp3", "m4a", "wav", "aac"]
            
            if supportedFormats.contains(pathExtension) {
                return inputURL
            }
        } catch {
            print("🎯 [TaskManager] 音频文件验证失败: \(error), 尝试转换格式")
        }
        
        // 如果直接读取失败或格式不支持，尝试转换
        let tempDirectory = FileManager.default.temporaryDirectory
        let outputURL = tempDirectory.appendingPathComponent("processed_\(id.uuidString).m4a")
        
        let asset = AVURLAsset(url: inputURL)
        
        do {
            let isPlayable = try await asset.load(.isPlayable)
            guard isPlayable else {
                throw NSError(domain: "SubtitleGenerationTask", code: 1001, userInfo: [NSLocalizedDescriptionKey: "音频文件无法播放，可能文件损坏或格式不支持"])
            }
            
            let duration = try await asset.load(.duration)
            guard duration.seconds > 0 else {
                throw NSError(domain: "SubtitleGenerationTask", code: 1008, userInfo: [NSLocalizedDescriptionKey: "音频文件时长为0"])
            }
            
            print("🎯 [TaskManager] 开始转换音频格式，原始时长: \(duration.seconds) 秒")
            
        } catch {
            throw NSError(domain: "SubtitleGenerationTask", code: 1009, userInfo: [NSLocalizedDescriptionKey: "音频文件分析失败: \(error.localizedDescription)"])
        }
        
        guard let exportSession = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetAppleM4A) else {
            throw NSError(domain: "SubtitleGenerationTask", code: 1002, userInfo: [NSLocalizedDescriptionKey: "无法创建音频导出会话"])
        }
        
        exportSession.outputURL = outputURL
        exportSession.outputFileType = .m4a
        
        await exportSession.export()
        
        switch exportSession.status {
        case .completed:
            // 验证转换后的文件
            do {
                let convertedFile = try AVAudioFile(forReading: outputURL)
                let convertedDuration = Double(convertedFile.length) / convertedFile.fileFormat.sampleRate
                print("🎯 [TaskManager] 音频转换成功: 时长 \(convertedDuration) 秒")
                return outputURL
            } catch {
                throw NSError(domain: "SubtitleGenerationTask", code: 1010, userInfo: [NSLocalizedDescriptionKey: "转换后的音频文件验证失败: \(error.localizedDescription)"])
            }
        case .failed:
            let errorMessage = exportSession.error?.localizedDescription ?? "未知错误"
            throw NSError(domain: "SubtitleGenerationTask", code: 1003, userInfo: [NSLocalizedDescriptionKey: "音频格式转换失败: \(errorMessage)"])
        case .cancelled:
            throw CancellationError()
        default:
            throw NSError(domain: "SubtitleGenerationTask", code: 1004, userInfo: [NSLocalizedDescriptionKey: "音频格式转换状态异常: \(exportSession.status.rawValue)"])
        }
    }
    
    private func transcribeAudioWithProgress(_ audioURL: URL) async throws -> TranscriptionResult {
        let whisperService = WhisperKitService.shared
        
        guard await whisperService.modelDownloadState == .ready else {
            throw NSError(domain: "SubtitleGenerationTask", code: 1005, userInfo: [NSLocalizedDescriptionKey: "WhisperKit模型未准备就绪"])
        }
        
        // 启动进度模拟任务 (30% - 90%)
        progressTask = Task { @MainActor in
            var currentProgress = 0.3
            let targetProgress = 0.85
            let stepSize = 0.005 // 每次增加0.5%
            let stepInterval: UInt64 = 300_000_000 // 300ms
            
            while currentProgress < targetProgress && !Task.isCancelled {
                try? await Task.sleep(nanoseconds: stepInterval)
                currentProgress += stepSize
                await self.updateProgress(min(currentProgress, targetProgress), message: "正在识别语音内容... \(Int(currentProgress * 100))%")
            }
        }
        
        // 执行实际的转录
        let results = try await whisperService.transcribeAudioFile(at: audioURL)
        
        // 停止进度模拟
        progressTask?.cancel()
        
        guard let firstResult = results.first else {
            throw NSError(domain: "SubtitleGenerationTask", code: 1006, userInfo: [NSLocalizedDescriptionKey: "音频转录结果为空"])
        }
        
        return firstResult
    }
    
    @MainActor
    private func createSubtitlesFromResult(_ result: TranscriptionResult) async -> [Subtitle] {
        // 使用WhisperKit的真实单词时间戳创建字幕段落
        if !result.allWords.isEmpty {
            let segments = createSubtitleSegmentsFromWhisperResult(result)
            return segments.map { segment in
                Subtitle(
                    startTime: segment.start,
                    endTime: segment.end,
                    text: segment.text,
                    confidence: segment.avgLogprob != nil ? Float(exp(segment.avgLogprob!)) : nil,
                    words: segment.words,
                    language: "en"
                )
            }
        } else {
            // 回退到文本分割方法
            let duration = TimeInterval(result.segments.last?.end ?? 0)
            let segments = createSubtitleSegments(from: result.text, audioDuration: duration)
            return segments.map { segment in
                Subtitle(
                    startTime: segment.start,
                    endTime: segment.end,
                    text: segment.text,
                    confidence: segment.avgLogprob != nil ? Float(exp(segment.avgLogprob!)) : nil,
                    words: segment.words,
                    language: "en"
                )
            }
        }
    }
    
    private func saveSubtitlesToDatabase(_ subtitles: [Subtitle]) async {
        await PodcastDataService.shared.updateEpisodeSubtitlesWithMetadata(
            episodeId,
            subtitles: subtitles,
            generationDate: Date(),
            version: generateSubtitleVersion()
        )
    }
    
    private func generateSubtitleVersion() -> String {
        let timestamp = Int(Date().timeIntervalSince1970)
        return "\(quality.rawValue)_\(timestamp)"
    }
    
    // MARK: - 字幕创建辅助方法 (从PodcastPlayerService复制)
    
    private struct LocalTranscriptionSegment {
        let start: TimeInterval
        let end: TimeInterval
        let text: String
        let avgLogprob: Double?
        let words: [SubtitleWord]
    }
    
    private func createSubtitleSegmentsFromWhisperResult(_ result: TranscriptionResult) -> [LocalTranscriptionSegment] {
        guard !result.allWords.isEmpty else {
            return createSubtitleSegments(from: result.text, audioDuration: TimeInterval(result.segments.last?.end ?? 0))
        }
        
        let targetDuration: TimeInterval = 5.0
        let maxDuration: TimeInterval = 8.0
        let minDuration: TimeInterval = 2.0
        let maxWordsPerSubtitle = 15
        
        var segments: [LocalTranscriptionSegment] = []
        var currentWords: [WordTiming] = []
        var segmentStartTime: TimeInterval = 0
        
        for (index, word) in result.allWords.enumerated() {
            if currentWords.isEmpty {
                segmentStartTime = TimeInterval(word.start)
            }
            
            currentWords.append(word)
            
            let currentDuration = TimeInterval(word.end) - segmentStartTime
            
            let shouldEndSegment = (
                currentWords.count >= maxWordsPerSubtitle ||
                currentDuration >= maxDuration ||
                (currentDuration >= targetDuration && isGoodBreakPoint(word)) ||
                index == result.allWords.count - 1
            )
            
            if shouldEndSegment {
                let segmentText = currentWords.map { $0.word }.joined(separator: " ")
                let segmentEndTime = TimeInterval(word.end)
                let finalEndTime = max(segmentEndTime, segmentStartTime + minDuration)
                
                let segment = LocalTranscriptionSegment(
                    start: segmentStartTime,
                    end: finalEndTime,
                    text: segmentText,
                    avgLogprob: nil,
                    words: currentWords.map { whisperWordToSubtitleWord($0) }
                )
                
                segments.append(segment)
                currentWords = []
            }
        }
        
        return segments
    }
    
    private func createSubtitleSegments(from text: String, audioDuration: TimeInterval) -> [LocalTranscriptionSegment] {
        let cleanText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanText.isEmpty else { return [] }
        
        let targetDuration: TimeInterval = 5.0
        let maxCharacters = 80
        
        let sentences = cleanText.components(separatedBy: CharacterSet(charactersIn: ".!?"))
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        
        var segments: [LocalTranscriptionSegment] = []
        var currentTime: TimeInterval = 0
        
        for sentence in sentences {
            let estimatedDuration = max(2.0, min(8.0, TimeInterval(sentence.count) * 0.06))
            let actualDuration = min(estimatedDuration, audioDuration - currentTime)
            
            segments.append(LocalTranscriptionSegment(
                start: currentTime,
                end: currentTime + actualDuration,
                text: sentence,
                avgLogprob: nil,
                words: []
            ))
            
            currentTime += actualDuration
            
            if currentTime >= audioDuration {
                break
            }
        }
        
        return segments
    }
    
    private func isGoodBreakPoint(_ word: WordTiming) -> Bool {
        let punctuation = CharacterSet(charactersIn: ".!?;,:")
        return word.word.rangeOfCharacter(from: punctuation) != nil
    }
    
    private func whisperWordToSubtitleWord(_ wordTiming: WordTiming) -> SubtitleWord {
        return SubtitleWord(
            word: wordTiming.word,
            startTime: TimeInterval(wordTiming.start),
            endTime: TimeInterval(wordTiming.end),
            confidence: wordTiming.probability
        )
    }
}

// MARK: - 字幕生成任务管理器
class SubtitleGenerationTaskManager: ObservableObject {
    static let shared = SubtitleGenerationTaskManager()
    
    @Published var tasks: [SubtitleGenerationTask] = []
    @Published var activeTasks: [SubtitleGenerationTask] = []
    @Published var completedTasks: [SubtitleGenerationTask] = []
    @Published var failedTasks: [SubtitleGenerationTask] = []
    
    private let maxConcurrentTasks = 2 // 最多同时执行2个任务
    private var cancellables = Set<AnyCancellable>()
    
    private init() {
        // 监听任务状态变化
        $tasks
            .map { tasks in tasks.filter { $0.isActive } }
            .assign(to: \.activeTasks, on: self)
            .store(in: &cancellables)
        
        $tasks
            .map { tasks in tasks.filter { $0.isCompleted } }
            .assign(to: \.completedTasks, on: self)
            .store(in: &cancellables)
        
        $tasks
            .map { tasks in tasks.filter { $0.isFailed } }
            .assign(to: \.failedTasks, on: self)
            .store(in: &cancellables)
        
        // 定时检查任务状态变化
        Timer.publish(every: 1.0, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                self?.updateTaskCategories()
            }
            .store(in: &cancellables)
    }
    
    // MARK: - 公共方法
    
    func createTask(for episode: PodcastEpisode, quality: SubtitleQuality = .medium) -> SubtitleGenerationTask? {
        guard let audioURL = URL(string: episode.audioURL) else {
            print("🎯 [TaskManager] 无效的音频URL: \(episode.audioURL)")
            return nil
        }
        
        // 检查是否已有相同的任务
        if let existingTask = tasks.first(where: { $0.episodeId == episode.id && $0.isActive }) {
            print("🎯 [TaskManager] 任务已存在: \(episode.title)")
            return existingTask
        }
        
        let task = SubtitleGenerationTask(
            episodeId: episode.id,
            episodeName: episode.title,
            audioURL: audioURL,
            quality: quality
        )
        
        // 监听任务状态变化
        task.$status
            .sink { [weak self] status in
                DispatchQueue.main.async {
                    self?.objectWillChange.send()
                    // 立即更新任务分类
                    self?.updateTaskCategories()
                    print("🎯 [TaskManager] 任务状态变化: \(task.episodeName) -> \(status)")
                }
            }
            .store(in: &cancellables)
        
        // 监听任务进度变化
        task.$progress
            .sink { [weak self] progress in
                DispatchQueue.main.async {
                    self?.objectWillChange.send()
                }
            }
            .store(in: &cancellables)
        
        tasks.append(task)
        
        // 如果当前活动任务数量未达到上限，立即开始
        if activeTasks.count < maxConcurrentTasks {
            task.start()
        }
        
        print("🎯 [TaskManager] 创建新任务: \(episode.title)")
        return task
    }
    
    func cancelTask(_ task: SubtitleGenerationTask) {
        task.cancel()
        
        // 立即从任务列表中移除取消的任务
        tasks.removeAll { $0.id == task.id }
        
        print("🎯 [TaskManager] 取消并移除任务: \(task.episodeName)")
        
        // 检查是否有等待的任务可以开始
        startNextPendingTask()
    }
    
    func deleteTask(_ task: SubtitleGenerationTask) {
        task.cancel()
        tasks.removeAll { $0.id == task.id }
        print("🎯 [TaskManager] 删除任务: \(task.episodeName)")
        
        // 检查是否有等待的任务可以开始
        startNextPendingTask()
    }
    
    func clearCompletedTasks() {
        tasks.removeAll { $0.isCompleted }
        print("🎯 [TaskManager] 清除已完成任务")
    }
    
    func clearFailedTasks() {
        tasks.removeAll { $0.isFailed }
        print("🎯 [TaskManager] 清除失败任务")
    }
    
    func getTask(for episodeId: String) -> SubtitleGenerationTask? {
        return tasks.first { $0.episodeId == episodeId }
    }
    
    func hasActiveTask(for episodeId: String) -> Bool {
        return tasks.contains { $0.episodeId == episodeId && $0.isActive }
    }
    
    // MARK: - 私有方法
    
    private func updateTaskCategories() {
        let newActiveTasks = tasks.filter { $0.isActive }
        let newCompletedTasks = tasks.filter { $0.isCompleted }
        let newFailedTasks = tasks.filter { $0.isFailed }
        
        // 只有当分类真正发生变化时才更新
        if activeTasks.count != newActiveTasks.count ||
           completedTasks.count != newCompletedTasks.count ||
           failedTasks.count != newFailedTasks.count {
            
            activeTasks = newActiveTasks
            completedTasks = newCompletedTasks
            failedTasks = newFailedTasks
            
            print("🎯 [TaskManager] 任务状态更新 - 活动中: \(activeTasks.count), 已完成: \(completedTasks.count), 失败: \(failedTasks.count)")
            
            // 检查是否有等待的任务可以开始
            startNextPendingTask()
        }
    }
    
    private func startNextPendingTask() {
        guard activeTasks.count < maxConcurrentTasks else { return }
        
        if let pendingTask = tasks.first(where: { task in
            switch task.status {
            case .pending:
                return true
            default:
                return false
            }
        }) {
            pendingTask.start()
            print("🎯 [TaskManager] 开始等待中的任务: \(pendingTask.episodeName)")
        }
    }
} 