import Foundation
import Speech
import AVFoundation

struct WordMatchResult: Identifiable {
    enum MatchType {
        case matched    // 匹配的词 (绿色)
        case missing    // 缺失的词 (红色)
        case extra      // 多余的词 (灰色)
    }
    
    let id = UUID() // 添加id属性以符合Identifiable协议
    let word: String
    let type: MatchType
    let originalIndex: Int  // 记录单词在原句中的位置，用于排序
}

@MainActor
class SpeechRecognitionService: NSObject, ObservableObject {
    static let shared = SpeechRecognitionService()
    
    // Speech recognition properties
    private let speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    
    // Audio recording properties
    private var audioEngine = AVAudioEngine()
    private var audioRecorder: AVAudioRecorder?
    private var recordingURL: URL?
    
    @Published var isRecording = false
    @Published var recognizedText = ""
    @Published var recordingTime: TimeInterval = 0
    @Published var wordResults: [WordMatchResult] = []
    
    // 添加实时识别相关属性
    @Published var isTranscribing = false
    @Published var interimResult = ""
    @Published var transcriptionProgress: Float = 0.0
    
    private var recordingTimer: Timer?
    
    override private init() {
        super.init()
        requestPermissions()
    }
    
    // Request necessary permissions
    private func requestPermissions() {
        SFSpeechRecognizer.requestAuthorization { [weak self] status in
            DispatchQueue.main.async {
                switch status {
                case .authorized:
                    print("Speech recognition authorized")
                default:
                    print("Speech recognition authorization denied")
                }
            }
        }
        
        AVAudioSession.sharedInstance().requestRecordPermission { granted in
            print("Recording permission granted: \(granted)")
        }
    }
    
    // Start recording and speech recognition
    func startRecording() {
        // Check which service to use
        let recognitionService = UserSettings.shared.speechRecognitionServiceType
        
        switch recognitionService {
        case .nativeSpeech:
            startNativeRecording()
        case .whisperKit:
            Task {
                await startWhisperKitRecording()
            }
        }
    }
    
    // Start recording with the native iOS Speech Recognition framework
    private func startNativeRecording() {
        // Set up audio session for recording
        let audioSession = AVAudioSession.sharedInstance()
        try? audioSession.setCategory(.record, mode: .default)
        try? audioSession.setActive(true, options: .notifyOthersOnDeactivation)
        
        // Get persistent storage directory for recordings
        let containerURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let recordingsDirectory = containerURL.appendingPathComponent("KumarajivaSpeechRecordings", isDirectory: true)
        
        // Create recordings directory if it doesn't exist
        if !FileManager.default.fileExists(atPath: recordingsDirectory.path) {
            do {
                try FileManager.default.createDirectory(at: recordingsDirectory, 
                                                      withIntermediateDirectories: true,
                                                      attributes: nil)
                
                // Make directory visible in Files app
                var resourceValues = URLResourceValues()
                resourceValues.isExcludedFromBackup = false
                var mutableURL = recordingsDirectory as URL
                try mutableURL.setResourceValues(resourceValues)
            } catch {
                print("Failed to create recordings directory: \(error)")
            }
        }
        
        // Create recording file with readable name and timestamp
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyyMMdd_HHmmss"
        let timestamp = dateFormatter.string(from: Date())
        let fileName = "speech_recording_\(timestamp).m4a"
        recordingURL = recordingsDirectory.appendingPathComponent(fileName)
        
        // Configure audio recorder
        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: 44100.0,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
        ]
        
        // Start audio recorder
        do {
            if let url = recordingURL {
                audioRecorder = try AVAudioRecorder(url: url, settings: settings)
                audioRecorder?.record()
            }
        } catch {
            print("Could not start recording: \(error)")
            return
        }
        
        // Reset recognition state
        recognizedText = ""
        wordResults = []
        
        // Set up audio engine and recognition request
        recognitionRequest = SFSpeechAudioBufferRecognitionRequest()
        
        let inputNode = audioEngine.inputNode
        guard let recognitionRequest = recognitionRequest else {
            print("Unable to create recognition request")
            return
        }
        
        recognitionRequest.shouldReportPartialResults = true
        
        // Start recognition task
        recognitionTask = speechRecognizer?.recognitionTask(with: recognitionRequest) { [weak self] result, error in
            guard let self = self else { return }
            
            if let result = result {
                self.recognizedText = result.bestTranscription.formattedString
            }
            
            if error != nil || (result?.isFinal ?? false) {
                self.audioEngine.stop()
                inputNode.removeTap(onBus: 0)
                self.recognitionRequest = nil
                self.recognitionTask = nil
            }
        }
        
        // Configure audio engine
        let recordingFormat = inputNode.outputFormat(forBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { buffer, _ in
            self.recognitionRequest?.append(buffer)
        }
        
        try? audioEngine.start()
        isRecording = true
        
        // Start timer to track recording duration
        recordingTime = 0
        recordingTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            self.recordingTime += 0.1
        }
    }
    
    // Start recording with WhisperKit
    private func startWhisperKitRecording() async {
        // Delegate to WhisperKit service
        await WhisperKitService.shared.startRecording()
        
        // Observe WhisperKit service properties
        observeWhisperKitProperties()
    }
    
    // Set up property observations for WhisperKit service
    private func observeWhisperKitProperties() {
        // We need to manually update our properties when WhisperKit's properties change
        // since we can't use property wrappers across actors
        Task { @MainActor in
            self.isRecording = WhisperKitService.shared.isRecording
            self.recognizedText = WhisperKitService.shared.recognizedText
            self.recordingTime = WhisperKitService.shared.recordingTime
            self.wordResults = WhisperKitService.shared.wordResults
            
            // 添加新属性的观察
            self.isTranscribing = WhisperKitService.shared.isTranscribing
            self.interimResult = WhisperKitService.shared.interimResult
            self.transcriptionProgress = WhisperKitService.shared.transcriptionProgress
            
            // Set up a timer to observe changes
            Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] timer in
                guard let self = self else {
                    timer.invalidate()
                    return
                }
                
                // Only continue observing while recording or transcribing
                if !WhisperKitService.shared.isRecording && !WhisperKitService.shared.isTranscribing {
                    timer.invalidate()
                    return
                }
                
                // Update properties
                self.isRecording = WhisperKitService.shared.isRecording
                self.recognizedText = WhisperKitService.shared.recognizedText
                self.recordingTime = WhisperKitService.shared.recordingTime
                self.wordResults = WhisperKitService.shared.wordResults
                
                // 更新新属性
                self.isTranscribing = WhisperKitService.shared.isTranscribing
                self.interimResult = WhisperKitService.shared.interimResult
                self.transcriptionProgress = WhisperKitService.shared.transcriptionProgress
            }
        }
    }
    
    // Stop recording and speech recognition
    func stopRecording() -> URL? {
        // Check which service to use
        let recognitionService = UserSettings.shared.speechRecognitionServiceType
        
        switch recognitionService {
        case .nativeSpeech:
            return stopNativeRecording()
        case .whisperKit:
            // Create a semaphore to wait for the async operation
            let semaphore = DispatchSemaphore(value: 0)
            var resultURL: URL? = nil
            
            Task { @MainActor in
                resultURL = await stopWhisperKitRecording()
                semaphore.signal()
            }
            
            // Wait for the async operation to complete (with timeout)
            _ = semaphore.wait(timeout: .now() + 2.0)
            return resultURL
        }
    }
    
    // Stop native recording
    private func stopNativeRecording() -> URL? {
        audioEngine.stop()
        recognitionRequest?.endAudio()
        audioEngine.inputNode.removeTap(onBus: 0)
        
        audioRecorder?.stop()
        isRecording = false
        
        // Stop and invalidate timer
        recordingTimer?.invalidate()
        recordingTimer = nil
        
        // Reset audio session back to playback mode
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
            try AVAudioSession.sharedInstance().setActive(true, options: .notifyOthersOnDeactivation)
        } catch {
            print("Failed to reset audio session: \(error)")
        }
        
        return recordingURL
    }
    
    // Stop WhisperKit recording
    private func stopWhisperKitRecording() async -> URL? {
        return await WhisperKitService.shared.stopRecording()
    }
    
    // Normalize text for comparison by removing punctuation, extra spaces, and lowercasing
    private func normalizeText(_ text: String) -> String {
        let lowercasedText = text.lowercased()
        
        // Remove punctuation
        let punctuationCharacterSet = CharacterSet.punctuationCharacters
        let textWithoutPunctuation = lowercasedText
            .components(separatedBy: punctuationCharacterSet)
            .joined(separator: " ")
        
        // Normalize whitespace
        let whitespaceCharacterSet = CharacterSet.whitespacesAndNewlines
        let components = textWithoutPunctuation
            .components(separatedBy: whitespaceCharacterSet)
            .filter { !$0.isEmpty }
        
        return components.joined(separator: " ")
    }
    
    // Extract English text from memory method
    private func extractEnglishText(_ text: String) -> String {
        // First, try to extract text in parentheses (both English and Chinese)
        let parenthesesRegex = try? NSRegularExpression(pattern: "\\([^\\)]+\\)|（[^）]+）", options: [])
        if let matches = parenthesesRegex?.matches(in: text, options: [], range: NSRange(text.startIndex..., in: text)),
           !matches.isEmpty {
            var extractedText = ""
            
            // Extract the text inside parentheses
            for match in matches {
                if let range = Range(match.range, in: text) {
                    var content = String(text[range])
                    // Remove the parentheses
                    content = content.trimmingCharacters(in: CharacterSet(charactersIn: "()（）"))
                    extractedText += " " + content
                }
            }
            
            if !extractedText.isEmpty {
                return extractedText.trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }
        
        // Fallback to original method if no parentheses found
        var englishWords: [String] = []
        let words = text.components(separatedBy: .whitespacesAndNewlines)
        
        for word in words {
            // Check if word contains mainly English characters
            let englishCharacterSet = CharacterSet.letters.subtracting(
                CharacterSet(charactersIn: "àáâäæãåāèéêëēėęîïíīįìôöòóœøōõûüùúū")
            )
            let nonEnglishCharacterSet = CharacterSet.letters.subtracting(englishCharacterSet)
            
            // Consider a word English if it contains mainly English characters
            let englishChars = word.unicodeScalars.filter { englishCharacterSet.contains($0) }.count
            let nonEnglishChars = word.unicodeScalars.filter { nonEnglishCharacterSet.contains($0) }.count
            
            if englishChars > nonEnglishChars && word.count > 1 {
                englishWords.append(word)
            }
        }
        
        return englishWords.joined(separator: " ")
    }
    
    // Analyze word matching for highlighting
    func analyzeWordMatching(expectedText: String) -> [WordMatchResult] {
        // Check which service to use
        if UserSettings.shared.speechRecognitionServiceType == .whisperKit {
            // If WhisperKit is being used, get from the latest wordResults
            return wordResults
        }
        
        // Extract English text if needed and normalize
        let englishExpectedText = extractEnglishText(expectedText)
        let finalExpectedText = englishExpectedText.isEmpty ? expectedText : englishExpectedText
        
        let normalizedExpected = normalizeText(finalExpectedText)
        let normalizedRecognized = normalizeText(recognizedText)
        
        let expectedWords = normalizedExpected.components(separatedBy: .whitespaces).filter { !$0.isEmpty }
        let recognizedWords = normalizedRecognized.components(separatedBy: .whitespaces).filter { !$0.isEmpty }
        
        // 创建一个临时数组，用于构建最终的结果
        var temporaryResults: [WordMatchResult?] = Array(repeating: nil, count: max(expectedWords.count, recognizedWords.count) * 2)
        
        // 两个索引
        var currentRecognizedIndex = 0
        var expectedWordMatched = Array(repeating: false, count: expectedWords.count)
        var currentTempIndex = 0
        
        // 第一步：处理已识别的单词
        for (recIndex, recognizedWord) in recognizedWords.enumerated() {
            if let expIndex = expectedWords.firstIndex(of: recognizedWord), !expectedWordMatched[expIndex] {
                // 如果是匹配的词
                expectedWordMatched[expIndex] = true
                
                // 检查是否有缺失的词需要先插入
                for i in 0..<expIndex {
                    if !expectedWordMatched[i] {
                        temporaryResults[currentTempIndex] = WordMatchResult(
                            word: expectedWords[i],
                            type: .missing,
                            originalIndex: currentTempIndex
                        )
                        expectedWordMatched[i] = true
                        currentTempIndex += 1
                    }
                }
                
                // 添加匹配的词
                temporaryResults[currentTempIndex] = WordMatchResult(
                    word: recognizedWord,
                    type: .matched,
                    originalIndex: currentTempIndex
                )
                currentTempIndex += 1
            } else {
                // 如果是额外的词
                temporaryResults[currentTempIndex] = WordMatchResult(
                    word: recognizedWord,
                    type: .extra,
                    originalIndex: currentTempIndex
                )
                currentTempIndex += 1
            }
        }
        
        // 第二步：添加所有剩余缺失的词
        for (expIndex, expectedWord) in expectedWords.enumerated() {
            if !expectedWordMatched[expIndex] {
                temporaryResults[currentTempIndex] = WordMatchResult(
                    word: expectedWord,
                    type: .missing,
                    originalIndex: currentTempIndex
                )
                currentTempIndex += 1
            }
        }
        
        // 过滤掉空值并返回结果
        let results = temporaryResults.compactMap { $0 }
        return results
    }
    
    // Calculate speech recognition score by comparing recognized text with the expected text
    func calculateScore(expectedText: String) -> Int {
        print("SpeechRecognitionService: 开始计算得分，预期文本: \(expectedText)")
        
        // Check which service to use
        if UserSettings.shared.speechRecognitionServiceType == .whisperKit {
            print("SpeechRecognitionService: 使用WhisperKit计算得分")
            
            // Use a semaphore to make the async call behave synchronously
            let semaphore = DispatchSemaphore(value: 0)
            var whisperScore = 0
            
            Task { @MainActor in
                print("SpeechRecognitionService: 调用WhisperKit.calculateScore")
                whisperScore = await WhisperKitService.shared.calculateScore(expectedText: expectedText)
                self.wordResults = WhisperKitService.shared.wordResults
                self.recognizedText = WhisperKitService.shared.recognizedText
                print("SpeechRecognitionService: WhisperKit得分: \(whisperScore)")
                print("SpeechRecognitionService: WhisperKit识别文本: \(self.recognizedText)")
                semaphore.signal()
            }
            
            // Wait with timeout
            print("SpeechRecognitionService: 等待WhisperKit计算结果")
            _ = semaphore.wait(timeout: .now() + 3.0) // 增加超时时间到3秒
            print("SpeechRecognitionService: WhisperKit计算完成，得分: \(whisperScore)")
            return whisperScore
        }
        
        guard !recognizedText.isEmpty else { 
            print("SpeechRecognitionService: 识别文本为空，返回0分")
            return 0 
        }
        
        // Update word results
        wordResults = analyzeWordMatching(expectedText: expectedText)
        
        // Extract English text if needed and normalize
        let englishExpectedText = extractEnglishText(expectedText)
        let normalizedExpected = normalizeText(englishExpectedText.isEmpty ? expectedText : englishExpectedText)
        let normalizedRecognized = normalizeText(recognizedText)
        
        print("SpeechRecognitionService: 预期文本(标准化): \(normalizedExpected)")
        print("SpeechRecognitionService: 识别文本(标准化): \(normalizedRecognized)")
        
        // Simple word matching algorithm
        let expectedWords = normalizedExpected.components(separatedBy: .whitespaces).filter { !$0.isEmpty }
        let recognizedWords = normalizedRecognized.components(separatedBy: .whitespaces).filter { !$0.isEmpty }
        
        var matchedWords = 0
        var totalWords = expectedWords.count
        
        // In case there are no English words extracted, use a more lenient approach
        if totalWords == 0 {
            totalWords = max(1, recognizedWords.count)
            let expectedText = normalizeText(expectedText)
            
            // Try to match any recognized word with the expected text
            for word in recognizedWords {
                if expectedText.contains(word) && word.count > 1 {
                    matchedWords += 1
                }
            }
        } else {
            // Standard word matching for English text
            for word in recognizedWords {
                if expectedWords.contains(word) && word.count > 1 {
                    matchedWords += 1
                }
            }
        }
        
        // Calculate score as a percentage from 0-100
        let score = Int((Double(matchedWords) / Double(totalWords)) * 100)
        
        // Ensure the score is within 0-100 range
        let finalScore = min(100, max(0, score))
        print("SpeechRecognitionService: 最终得分: \(finalScore)")
        return finalScore
    }
} 