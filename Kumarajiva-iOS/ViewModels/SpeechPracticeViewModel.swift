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
    }
    
    // Start recording
    func startRecording() {
        // Stop any audio playback first
        AudioService.shared.stopPlayback()
        audioPlayer?.stop()
        
        speechService.startRecording()
    }
    
    // Stop recording and save the record
    func stopRecording(word: String, example: String) {
        guard let audioURL = speechService.stopRecording() else { return }
        
        // Calculate score based on the example text
        let score = speechService.calculateScore(expectedText: example)
        currentScore = score
        
        // Create and save the record
        let record = SpeechPracticeRecord(
            word: word,
            example: example,
            audioURL: audioURL,
            timestamp: Date(),
            score: score
        )
        
        records.insert(record, at: 0)
        saveRecordsToDisk()
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
                records = try decoder.decode([SpeechPracticeRecord].self, from: data)
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
            return .black      // 缺失的词 - 黑色
        case .incorrect:
            return .red        // 错误的词 - 红色
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
                    .map { WordMatchResult(word: $0, type: .extra) }
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