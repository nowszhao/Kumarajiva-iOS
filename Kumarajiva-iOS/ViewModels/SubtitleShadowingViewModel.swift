import Foundation
import AVFoundation
import SwiftUI

/// 字幕跟读练习ViewModel
@MainActor
class SubtitleShadowingViewModel: ObservableObject {
    // MARK: - Published Properties
    @Published var currentSubtitleIndex: Int = 0
    @Published var isPlaying: Bool = false
    @Published var isRecording: Bool = false
    @Published var isProcessing: Bool = false
    @Published var currentTime: TimeInterval = 0
    @Published var practiceRecords: [SubtitlePracticeRecord] = []
    @Published var currentStats: SubtitlePracticeStats?
    @Published var errorMessage: String?
    @Published var showError: Bool = false
    @Published var lastScore: Int?
    @Published var lastRecognizedText: String?
    @Published var lastWordMatches: [SubtitleWordMatch] = []
    
    // MARK: - Private Properties
    private let video: YouTubeVideo
    let subtitles: [Subtitle]  // 需要被 View 访问，所以不能是 private
    private let audioURL: String
    private var player: AVPlayer?
    private var timeObserver: Any?
    private let whisperService = WhisperKitService.shared
    private let practiceService = SubtitlePracticeService.shared
    
    // MARK: - Computed Properties
    var currentSubtitle: Subtitle? {
        guard currentSubtitleIndex >= 0 && currentSubtitleIndex < subtitles.count else {
            return nil
        }
        return subtitles[currentSubtitleIndex]
    }
    
    var hasNext: Bool {
        return currentSubtitleIndex < subtitles.count - 1
    }
    
    var hasPrevious: Bool {
        return currentSubtitleIndex > 0
    }
    
    var totalSubtitles: Int {
        return subtitles.count
    }
    
    // MARK: - Initialization
    init(video: YouTubeVideo, subtitles: [Subtitle], audioURL: String, startIndex: Int = 0) {
        self.video = video
        self.subtitles = subtitles
        self.audioURL = audioURL
        self.currentSubtitleIndex = max(0, min(startIndex, subtitles.count - 1))
        
        setupPlayer()
        loadCurrentStats()
    }
    
    deinit {
        // 在 deinit 中直接清理，不需要 Task
        if let observer = timeObserver {
            player?.removeTimeObserver(observer)
        }
        player?.pause()
        player = nil
    }
    
    // MARK: - Player Setup
    private func setupPlayer() {
        guard let url = URL(string: audioURL) else {
            showErrorMessage("无效的音频URL")
            return
        }
        
        player = AVPlayer(url: url)
        
        // 添加时间观察器
        let interval = CMTime(seconds: 0.1, preferredTimescale: CMTimeScale(NSEC_PER_SEC))
        timeObserver = player?.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
            Task { @MainActor in
                self?.currentTime = time.seconds
            }
        }
    }
    
    // MARK: - Playback Control
    func playCurrentSubtitle() {
        guard let subtitle = currentSubtitle else { return }
        
        stopRecording()
        
        let startTime = CMTime(seconds: subtitle.startTime, preferredTimescale: CMTimeScale(NSEC_PER_SEC))
        let duration = subtitle.endTime - subtitle.startTime
        
        player?.seek(to: startTime) { [weak self] _ in
            Task { @MainActor in
                guard let self = self else { return }
                self.player?.play()
                self.isPlaying = true
                
                // 在字幕结束时自动停止
                DispatchQueue.main.asyncAfter(deadline: .now() + duration) {
                    Task { @MainActor in
                        if self.isPlaying {
                            self.stopPlayback()
                        }
                    }
                }
            }
        }
    }
    
    func stopPlayback() {
        player?.pause()
        isPlaying = false
    }
    
    func togglePlayback() {
        if isPlaying {
            stopPlayback()
        } else {
            playCurrentSubtitle()
        }
    }
    
    // MARK: - Recording Control
    func startRecording() async {
        guard currentSubtitle != nil else { return }
        
        stopPlayback()
        
        isRecording = true
        errorMessage = nil
        
        do {
            try await whisperService.startRecording()
        } catch {
            showErrorMessage("录音失败: \(error.localizedDescription)")
            isRecording = false
        }
    }
    
    func stopRecording() {
        guard isRecording else { return }
        
        Task {
            isRecording = false
            isProcessing = true
            
            if let audioURL = try? await whisperService.stopRecording() {
                await processRecording(audioURL: audioURL)
            } else {
                showErrorMessage("停止录音失败")
                isProcessing = false
            }
        }
    }
    
    private func processRecording(audioURL: URL) async {
        guard let subtitle = currentSubtitle else {
            isProcessing = false
            return
        }
        
        do {
            // 使用WhisperKit识别
            let results = try await whisperService.transcribeAudioFile(at: audioURL)
            let recognizedText = results.first?.text ?? ""
            
            // 评分和匹配
            let (score, wordMatches) = evaluateRecording(
                original: subtitle.text,
                recognized: recognizedText
            )
            
            // 保存录音文件到专用目录
            let savedURL = try saveRecording(from: audioURL)
            
            // 创建练习记录
            let record = SubtitlePracticeRecord(
                videoId: video.id.uuidString,
                subtitleId: subtitle.id,
                subtitleText: subtitle.text,
                audioURL: savedURL,
                timestamp: Date(),
                score: score,
                recognizedText: recognizedText,
                wordMatchResults: wordMatches
            )
            
            // 保存记录
            practiceService.addRecord(record)
            
            // 更新UI
            lastScore = score
            lastRecognizedText = recognizedText
            lastWordMatches = wordMatches
            loadCurrentStats()
            
        } catch {
            showErrorMessage("识别失败: \(error.localizedDescription)")
        }
        
        isProcessing = false
    }
    
    // MARK: - Navigation
    func goToNext() {
        guard hasNext else { return }
        
        stopPlayback()
        stopRecording()
        
        currentSubtitleIndex += 1
        loadCurrentStats()
        clearLastResult()
    }
    
    func goToPrevious() {
        guard hasPrevious else { return }
        
        stopPlayback()
        stopRecording()
        
        currentSubtitleIndex -= 1
        loadCurrentStats()
        clearLastResult()
    }
    
    func goToSubtitle(at index: Int) {
        guard index >= 0 && index < subtitles.count else { return }
        
        stopPlayback()
        stopRecording()
        
        currentSubtitleIndex = index
        loadCurrentStats()
        clearLastResult()
    }
    
    // MARK: - Data Management
    private func loadCurrentStats() {
        guard let subtitle = currentSubtitle else { return }
        currentStats = practiceService.getStats(videoId: video.id.uuidString, subtitleId: subtitle.id)
        practiceRecords = practiceService.getRecords(videoId: video.id.uuidString, subtitleId: subtitle.id)
    }
    
    func deleteRecord(id: UUID) {
        practiceService.deleteRecord(id: id)
        loadCurrentStats()
    }
    
    func clearAllRecords() {
        guard let subtitle = currentSubtitle else { return }
        
        // 删除当前字幕的所有记录
        for record in practiceRecords {
            practiceService.deleteRecord(id: record.id)
        }
        
        loadCurrentStats()
        clearLastResult()
    }
    
    // MARK: - Evaluation
    private func evaluateRecording(original: String, recognized: String) -> (score: Int, matches: [SubtitleWordMatch]) {
        // 清理和标准化文本
        let originalWords = cleanText(original).components(separatedBy: .whitespaces).filter { !$0.isEmpty }
        let recognizedWords = cleanText(recognized).components(separatedBy: .whitespaces).filter { !$0.isEmpty }
        
        var matches: [SubtitleWordMatch] = []
        var correctCount = 0
        
        // 逐词匹配
        for (index, originalWord) in originalWords.enumerated() {
            let recognizedWord = index < recognizedWords.count ? recognizedWords[index] : nil
            let isMatch = recognizedWord?.lowercased() == originalWord.lowercased()
            
            if isMatch {
                correctCount += 1
            }
            
            matches.append(SubtitleWordMatch(
                originalWord: originalWord,
                recognizedWord: recognizedWord,
                isMatch: isMatch
            ))
        }
        
        // 计算分数 (0-100)
        let score = originalWords.isEmpty ? 0 : Int((Double(correctCount) / Double(originalWords.count)) * 100)
        
        return (score, matches)
    }
    
    private func cleanText(_ text: String) -> String {
        // 移除标点符号，保留字母和数字
        let allowed = CharacterSet.alphanumerics.union(.whitespaces)
        return text.components(separatedBy: allowed.inverted).joined()
    }
    
    // MARK: - File Management
    private func saveRecording(from sourceURL: URL) throws -> URL {
        let fileManager = FileManager.default
        let documentsURL = fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let recordingsDir = documentsURL.appendingPathComponent("SubtitlePracticeRecordings", isDirectory: true)
        
        // 创建目录
        if !fileManager.fileExists(atPath: recordingsDir.path) {
            try fileManager.createDirectory(at: recordingsDir, withIntermediateDirectories: true)
        }
        
        // 生成唯一文件名
        let subtitleId = currentSubtitle?.id ?? UUID().uuidString
        let fileName = "\(video.id)_\(subtitleId)_\(Date().timeIntervalSince1970).m4a"
        let destinationURL = recordingsDir.appendingPathComponent(fileName)
        
        // 复制文件
        if fileManager.fileExists(atPath: destinationURL.path) {
            try fileManager.removeItem(at: destinationURL)
        }
        try fileManager.copyItem(at: sourceURL, to: destinationURL)
        
        return destinationURL
    }
    
    // MARK: - Helper Methods
    private func showErrorMessage(_ message: String) {
        errorMessage = message
        showError = true
    }
    
    private func clearLastResult() {
        lastScore = nil
        lastRecognizedText = nil
        lastWordMatches = []
    }
    
    func cleanup() {
        if let observer = timeObserver {
            player?.removeTimeObserver(observer)
            timeObserver = nil
        }
        player?.pause()
        player = nil
    }
}
