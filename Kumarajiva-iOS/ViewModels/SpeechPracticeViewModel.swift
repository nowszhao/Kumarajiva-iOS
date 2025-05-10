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
    
    private let speechService = SpeechRecognitionService.shared
    private var audioPlayer: AVAudioPlayer?
    private var playbackCompletionHandler: (() -> Void)?
    
    override init() {
        super.init()
        loadRecordsFromDisk()
        
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
                
                self.records.insert(record, at: 0)
                self.saveRecordsToDisk()
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
        if let index = records.firstIndex(where: { $0.id == id }) {
            let record = records[index]
            
            // Stop if currently playing this recording
            if audioPlayer != nil {
                audioPlayer?.stop()
                audioPlayer = nil
                playbackCompletionHandler = nil
            }
            
            // Delete file from disk
            do {
                try FileManager.default.removeItem(at: record.audioURL)
            } catch {
                print("Failed to delete recording file: \(error)")
            }
            
            // Remove from records array
            records.remove(at: index)
            saveRecordsToDisk()
        }
    }
    
    // Load records from disk
    private func loadRecordsFromDisk() {
        let userDefaults = UserDefaults.standard
        if let data = userDefaults.data(forKey: "speechPracticeRecords") {
            do {
                let decoder = JSONDecoder()
                let savedRecords = try decoder.decode([SpeechPracticeRecord].self, from: data)
                
                // Filter out records with invalid URLs
                records = savedRecords.filter { record in
                    // Verify if the file exists
                    return FileManager.default.fileExists(atPath: record.audioURL.path)
                }
                
                // If we filtered some records, update the saved records
                if records.count != savedRecords.count {
                    print("Removed \(savedRecords.count - records.count) records with missing audio files")
                    saveRecordsToDisk()
                }
            } catch {
                print("Failed to load speech practice records: \(error)")
            }
        }
    }
    
    // Save records to disk
    private func saveRecordsToDisk() {
        do {
            let encoder = JSONEncoder()
            let data = try encoder.encode(records)
            UserDefaults.standard.set(data, forKey: "speechPracticeRecords")
        } catch {
            print("Failed to save speech practice records: \(error)")
        }
    }
    
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
}

// MARK: - AVAudioPlayerDelegate
extension SpeechPracticeViewModel: AVAudioPlayerDelegate {
    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            
            // Call completion handler and clean up
            self.playbackCompletionHandler?()
            self.playbackCompletionHandler = nil
            self.audioPlayer = nil
        }
    }
} 