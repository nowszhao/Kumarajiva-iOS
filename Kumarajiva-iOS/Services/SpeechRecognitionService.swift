import Foundation
import Speech
import AVFoundation

struct WordMatchResult: Identifiable {
    enum MatchType {
        case matched    // 匹配的词 (绿色)
        case missing    // 缺失的词 (黑色)
        case incorrect  // 错误的词 (红色)
        case extra      // 多余的词 (灰色)
    }
    
    let id = UUID() // 添加id属性以符合Identifiable协议
    let word: String
    let type: MatchType
}

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
        // Set up audio session for recording
        let audioSession = AVAudioSession.sharedInstance()
        try? audioSession.setCategory(.record, mode: .default)
        try? audioSession.setActive(true, options: .notifyOthersOnDeactivation)
        
        // Create recording URL in documents directory
        let documentsDirectory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let fileName = "speech_practice_\(Date().timeIntervalSince1970).m4a"
        recordingURL = documentsDirectory.appendingPathComponent(fileName)
        
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
    
    // Stop recording and speech recognition
    func stopRecording() -> URL? {
        audioEngine.stop()
        recognitionRequest?.endAudio()
        audioEngine.inputNode.removeTap(onBus: 0)
        
        audioRecorder?.stop()
        isRecording = false
        
        // Stop and invalidate timer
        recordingTimer?.invalidate()
        recordingTimer = nil
        
        return recordingURL
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
        // Extract English text if needed and normalize
        let englishExpectedText = extractEnglishText(expectedText)
        let finalExpectedText = englishExpectedText.isEmpty ? expectedText : englishExpectedText
        
        let normalizedExpected = normalizeText(finalExpectedText)
        let normalizedRecognized = normalizeText(recognizedText)
        
        let expectedWords = normalizedExpected.components(separatedBy: .whitespaces).filter { !$0.isEmpty }
        let recognizedWords = normalizedRecognized.components(separatedBy: .whitespaces).filter { !$0.isEmpty }
        
        var results: [WordMatchResult] = []
        var matchedIndices = Set<Int>()
        
        // First, find all matched words
        for (index, recognizedWord) in recognizedWords.enumerated() {
            if expectedWords.contains(recognizedWord) && recognizedWord.count > 1 {
                results.append(WordMatchResult(word: recognizedWord, type: .matched))
                matchedIndices.insert(index)
            }
        }
        
        // Then, identify extra words
        for (index, recognizedWord) in recognizedWords.enumerated() {
            if !matchedIndices.contains(index) {
                results.append(WordMatchResult(word: recognizedWord, type: .extra))
            }
        }
        
        // Finally, identify missing words
        for expectedWord in expectedWords {
            if !recognizedWords.contains(expectedWord) && expectedWord.count > 1 {
                results.append(WordMatchResult(word: expectedWord, type: .missing))
            }
        }
        
        return results
    }
    
    // Calculate speech recognition score by comparing recognized text with the expected text
    func calculateScore(expectedText: String) -> Int {
        guard !recognizedText.isEmpty else { return 0 }
        
        // Extract English text if needed and normalize
        let englishExpectedText = extractEnglishText(expectedText)
        let normalizedExpected = normalizeText(englishExpectedText.isEmpty ? expectedText : englishExpectedText)
        let normalizedRecognized = normalizeText(recognizedText)
        
        print("Expected: \(normalizedExpected)")
        print("Recognized: \(normalizedRecognized)")
        
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
        
        // Calculate percentage score
        let scorePercentage = (Double(matchedWords) / Double(max(1, totalWords))) * 100
        
        // Analyze word matching for highlighting
        wordResults = analyzeWordMatching(expectedText: expectedText)
        
        return Int(scorePercentage)
    }
} 