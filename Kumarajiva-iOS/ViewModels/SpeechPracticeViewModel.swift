import Foundation
import SwiftUI
import AVFoundation

@MainActor
class SpeechPracticeViewModel: NSObject, ObservableObject {
    @Published var records: [SpeechPracticeRecord] = []
    @Published var currentScore: Int = 0
    @Published var isRecording = false
    @Published var recordingTime: TimeInterval = 0
    @Published var recognizedText = ""
    @Published var wordResults: [WordMatchResult] = []
    
    // 添加实时识别相关属性
    @Published var isTranscribing = false
    @Published var interimResult = ""
    @Published var transcriptionProgress: Float = 0.0
    
    // 添加学习记录相关属性
    @Published var studyRecords: [StudyRecord] = []
    @Published var isLoadingStudyRecords = false
    @Published var studyRecordsError: String?
    
    // 添加智能解析相关属性
    @Published var analysisState: AnalysisState = .notAnalyzed
    @Published var isAnalyzing = false
    
    private let speechService = SpeechRecognitionService.shared
    private var audioPlayer: AVAudioPlayer?
    private var playbackCompletionHandler: (() -> Void)?
    
    override init() {
        super.init()
        // 从服务获取记录
        records = SpeechPracticeRecordService.shared.records
        
        // Bind to speech service properties
        speechService.$isRecording.assign(to: &$isRecording)
        speechService.$recordingTime.assign(to: &$recordingTime)
        speechService.$recognizedText.assign(to: &$recognizedText)
        speechService.$wordResults.assign(to: &$wordResults)
        
        // 绑定新的实时识别属性
        if let whisperService = speechService as? WhisperKitService {
            whisperService.$isTranscribing.assign(to: &$isTranscribing)
            whisperService.$interimResult.assign(to: &$interimResult)
            whisperService.$transcriptionProgress.assign(to: &$transcriptionProgress)
        } else {
            // WhisperKitService.shared is not optional, so we don't need if let
            let whisperService = WhisperKitService.shared
            whisperService.$isTranscribing.assign(to: &$isTranscribing)
            whisperService.$interimResult.assign(to: &$interimResult)
            whisperService.$transcriptionProgress.assign(to: &$transcriptionProgress)
        }
    }
    
    // Start recording
    func startRecording() {
        // Stop any audio playback first
        AudioService.shared.stopPlayback()
        
        if audioPlayer != nil {
            audioPlayer?.stop()
            audioPlayer = nil
        }
        
        // Reset state for new recording
        recognizedText = ""
        wordResults = []
        
        // Ensure audio session is properly reset before starting new recording
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
            self?.speechService.startRecording()
        }
    }
    
    // Stop recording and save the record
    func stopRecording(word: String, example: String, shouldSave: Bool = true) {
        print("SpeechPracticeViewModel: 停止录音, 单词: \(word), 保存: \(shouldSave)")
        
        // Use a background queue for the blocking semaphore calls
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            
            print("SpeechPracticeViewModel: 开始停止录音处理")
            guard let audioURL = self.speechService.stopRecording() else { 
                print("SpeechPracticeViewModel: 停止录音失败，未获取到音频URL")
                DispatchQueue.main.async {
                    self.recognizedText = ""
                    self.wordResults = []
                    self.currentScore = 0
                }
                return 
            }
            
            print("SpeechPracticeViewModel: 录音已停止，音频URL: \(audioURL)")
            
            // 如果选择放弃，则不保存记录
            if !shouldSave {
                print("SpeechPracticeViewModel: 用户选择不保存录音")
                // 删除临时录音文件
                do {
                    try FileManager.default.removeItem(at: audioURL)
                    print("SpeechPracticeViewModel: 临时录音文件已删除")
                } catch {
                    print("Failed to delete canceled recording file: \(error)")
                }
                
                // 重置状态
                DispatchQueue.main.async {
                    self.recognizedText = ""
                    self.wordResults = []
                    self.currentScore = 0
                }
                return
            }
            
            // 等待一段时间，确保WhisperKit有足够时间处理录音
            if UserSettings.shared.speechRecognitionServiceType == .whisperKit {
                print("SpeechPracticeViewModel: 使用WhisperKit，等待处理完成")
                Thread.sleep(forTimeInterval: 1.0) // 等待1秒，确保处理完成
            }
            
            // 正常保存记录的逻辑
            // Calculate score based on the example text
            print("SpeechPracticeViewModel: 计算得分，例句: \(example)")
            let score = self.speechService.calculateScore(expectedText: example)
            print("SpeechPracticeViewModel: 得分计算结果: \(score)")
            
            // 如果使用WhisperKit，确保我们有识别结果
            if UserSettings.shared.speechRecognitionServiceType == .whisperKit {
                print("SpeechPracticeViewModel: WhisperKit识别结果: \(WhisperKitService.shared.recognizedText)")
                // 手动同步识别结果
                DispatchQueue.main.async {
                    self.recognizedText = WhisperKitService.shared.recognizedText
                    self.wordResults = WhisperKitService.shared.wordResults
                }
            }
            
            // Update UI on main thread
            DispatchQueue.main.async {
                self.currentScore = score
                
                print("SpeechPracticeViewModel: 创建录音记录，得分: \(score)")
                // Create and save the record
                let record = SpeechPracticeRecord(
                    word: word,
                    example: example,
                    audioURL: audioURL,
                    timestamp: Date(),
                    score: score
                )
                
                // 使用服务添加记录
                SpeechPracticeRecordService.shared.addRecord(record)
                // 更新本地记录数组
                self.records = SpeechPracticeRecordService.shared.records
                print("SpeechPracticeViewModel: 录音记录已保存")
            }
        }
    }
    
    // 取消录音并清除状态
    func cancelRecording() {
        // Use a background queue for the blocking call
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            
            _ = self.speechService.stopRecording()
            
            // 重置状态 - on main thread
            DispatchQueue.main.async {
                self.recognizedText = ""
                self.wordResults = []
                self.currentScore = 0
            }
        }
    }
    
    // Play a recording
    func playRecording(at url: URL, completion: (() -> Void)? = nil) {
        do {
            // Stop any other audio playing
            audioPlayer?.stop()
            AudioService.shared.stopPlayback()
            
            // Save completion handler
            playbackCompletionHandler = completion
            
            // Configure audio session for playback
            try AVAudioSession.sharedInstance().setCategory(.playback)
            try AVAudioSession.sharedInstance().setActive(true)
            
            // Create and play the audio player
            audioPlayer = try AVAudioPlayer(contentsOf: url)
            audioPlayer?.delegate = self
            audioPlayer?.prepareToPlay()
            audioPlayer?.play()
        } catch {
            print("Failed to play recording: \(error)")
            completion?()
        }
    }
    
    // Stop playback
    func stopPlayback() {
        audioPlayer?.stop()
        audioPlayer = nil
        playbackCompletionHandler = nil
    }
    
    // Delete a recording
    func deleteRecord(id: UUID) {
        // Stop if currently playing this recording
        if audioPlayer != nil {
            audioPlayer?.stop()
            audioPlayer = nil
            playbackCompletionHandler = nil
        }
        
        // 使用服务删除记录
        SpeechPracticeRecordService.shared.deleteRecord(id: id)
        // 更新本地记录数组
        records = SpeechPracticeRecordService.shared.records
    }
    
    // Delete all recordings for a specific word
    func deleteAllRecordsForWord(_ word: String) {
        // Stop any playback
        if audioPlayer != nil {
            audioPlayer?.stop()
            audioPlayer = nil
            playbackCompletionHandler = nil
        }
        
        // 使用服务删除记录
        SpeechPracticeRecordService.shared.deleteAllRecordsForWord(word)
        // 更新本地记录数组
        records = SpeechPracticeRecordService.shared.records
        print("已删除关于 '\(word)' 的练习记录")
    }
    
    // 这些方法已由 SpeechPracticeRecordService 处理
    // 保留此注释以表明这些功能已移至服务中
    
    // Format recording time as MM:SS
    func formatRecordingTime(_ time: TimeInterval) -> String {
        let minutes = Int(time) / 60
        let seconds = Int(time) % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }
    
    // Get color for word match type
    func colorForMatchType(_ type: WordMatchResult.MatchType) -> Color {
        switch type {
        case .matched:
            return .green      // 匹配的词 - 绿色
        case .missing:
            return .red        // 缺失的词 - 红色
        case .extra:
            return .gray       // 多余的词 - 灰色
        }
    }
    
    // Format recognized text with highlights
    func formattedRecognizedText() -> [WordMatchResult] {
        // No highlighting if no words
        if wordResults.isEmpty {
            if recognizedText.isEmpty {
                return []
            } else {
                // Return existing text without highlighting
                return recognizedText.components(separatedBy: .whitespaces)
                    .filter { !$0.isEmpty }
                    .enumerated()
                    .map { index, word in 
                        WordMatchResult(word: word, type: .extra, originalIndex: index) 
                    }
            }
        }
        
        return wordResults
    }
    
    // MARK: - Study Records Methods
    
    // 获取单词学习记录
    func fetchStudyRecords(for word: String) {
        isLoadingStudyRecords = true
        studyRecordsError = nil
        
        Task {
            do {
                let records = try await APIService.shared.getWordStudyHistory(word: word)
                DispatchQueue.main.async {
                    self.studyRecords = records
                    self.isLoadingStudyRecords = false
                }
            } catch {
                DispatchQueue.main.async {
                    self.studyRecordsError = error.localizedDescription
                    self.isLoadingStudyRecords = false
                    self.studyRecords = []
                }
                print("获取学习记录失败: \(error)")
            }
        }
    }
    
    // 清除学习记录
    func clearStudyRecords() {
        studyRecords = []
        studyRecordsError = nil
    }
    
    // MARK: - Word Analysis Methods
    
    /// 获取单词智能解析
    func fetchWordAnalysis(for word: String, forceRefresh: Bool = false) {
        // 检查是否有缓存且不强制刷新
        if !forceRefresh, let cachedAnalysis = WordAnalysisService.shared.getAnalysis(for: word) {
            analysisState = .analyzed(cachedAnalysis)
            return
        }
        
        analysisState = .analyzing
        isAnalyzing = true
        
        Task {
            do {
                let prompt = generateAnalysisPrompt(for: word)
                let response = try await LLMService.shared.sendChatMessage(prompt: prompt)
                
                // 解析LLM响应
                if let analysis = parseAnalysisResponse(response, word: word) {
                    // 保存到缓存
                    WordAnalysisService.shared.saveAnalysis(analysis)
                    
                    DispatchQueue.main.async {
                        self.analysisState = .analyzed(analysis)
                        self.isAnalyzing = false
                    }
                } else {
                    DispatchQueue.main.async {
                        self.analysisState = .failed("解析结果格式错误")
                        self.isAnalyzing = false
                    }
                }
            } catch {
                DispatchQueue.main.async {
                    self.analysisState = .failed(error.localizedDescription)
                    self.isAnalyzing = false
                }
                print("🧠 [Analysis] 智能解析失败: \(error)")
            }
        }
    }
    
    /// 生成分析提示词
    private func generateAnalysisPrompt(for word: String) -> String {
        return """
        根据人类记忆原理和人性，我立马记住这个单词且终身难忘。
        1、举例：ubiquitous
        2、按照 Json 格式输出：
        {
            "word": "ubiquitous",
            "basic_info": {
                "phonetic_notation": {
                    "British": "/juːˈbɪkwɪtəs/",
                    "American": "/juːˈbɪkwɪtəs/"
                },
                "annotation": "adj. 普遍存在的；无处不在的"
            },
            "split_association_method": "把"ubiquitous"拆分成"u（看作'you'，你） + bi（谐音'必'） + quit（离开） + ous（形容词后缀）" 。联想成"你必离开"一个地方，但无论你走到哪儿，都能发现某个事物，这就说明这个事物是"普遍存在的；无处不在的" 。",
            "scene_memory": [{
                    "scene": "如今，智能手机几乎是"ubiquitous"的。在公交上、餐厅里、校园中，随处都能看到人们拿着智能手机，它已经成为人们生活中不可或缺的一部分，无处不在。"
                },
                {
                    "scene": "在现代城市中，WiFi信号几乎是ubiquitous的，无论走到哪里都能连接网络。"
                }
            ],
            "synonym_precise_guidance": [{
                    "synonym": "Universal",
                    "explanation": "强调在所有地方或所有人中都存在，更具普遍性，常涉及概念、真理、现象等，如universal truth（普遍真理）。"
                },
                {
                    "synonym": "Widespread",
                    "explanation": "强调分布广泛，但不一定在每个地方都存在，如widespread support（广泛支持）。"
                }
            ]
        }

        新单词：\(word)
        """
    }
    
    /// 解析LLM响应为WordAnalysis对象
    private func parseAnalysisResponse(_ response: String, word: String) -> WordAnalysis? {
        // 提取JSON部分
        guard let jsonData = extractJSONFromResponse(response) else {
            print("🧠 [Analysis] 无法从响应中提取JSON")
            return nil
        }
        
        do {
            let llmResponse = try JSONDecoder().decode(LLMAnalysisResponse.self, from: jsonData)
            
            // 转换为WordAnalysis对象
            let analysis = WordAnalysis(
                word: word,
                basicInfo: llmResponse.basicInfo,
                splitAssociationMethod: llmResponse.splitAssociationMethod,
                sceneMemory: llmResponse.sceneMemory,
                synonymPreciseGuidance: llmResponse.synonymPreciseGuidance,
                createdAt: Date(),
                updatedAt: Date()
            )
            
            return analysis
        } catch {
            print("🧠 [Analysis] JSON解析失败: \(error)")
            return nil
        }
    }
    
    /// 从LLM响应中提取JSON部分
    private func extractJSONFromResponse(_ response: String) -> Data? {
        // 查找第一个 { 和最后一个 }
        guard let firstBrace = response.firstIndex(of: "{"),
              let lastBrace = response.lastIndex(of: "}") else {
            return nil
        }
        
        let jsonString = String(response[firstBrace...lastBrace])
        return jsonString.data(using: .utf8)
    }
    
    /// 清空分析状态
    func clearAnalysisState() {
        analysisState = .notAnalyzed
        isAnalyzing = false
    }
}

// MARK: - AVAudioPlayerDelegate
extension SpeechPracticeViewModel: @preconcurrency AVAudioPlayerDelegate {
    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            
            // Call completion handler and clean up
            self.playbackCompletionHandler?()
            self.playbackCompletionHandler = nil
            self.audioPlayer = nil
        }
    }
}