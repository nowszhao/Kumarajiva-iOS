import Foundation
import AVFoundation
import MediaPlayer

class AudioService: NSObject, AVPlayerItemMetadataOutputPushDelegate, ObservableObject {
    static let shared = AudioService()
    private var player: AVPlayer?
    private var audioPlayer: AVAudioPlayer?
    private var isLooping = false
    private var currentWords: [Any]? // Use Any to store either History or ReviewHistoryItem
    private var currentIndex = 0
    private var shouldPlayMemory = false
    private var onWordChangeWithIndex: ((String, Int) -> Void)?
    private var completionHandler: (() -> Void)?
    private var currentPlaybackRate: Float = 1.0
    
    // 提取英文句子的方法
    private func extractEnglishSentence(from input: String) -> String? {
        // 定义兼容中英文括号的正则表达式模式
        let pattern = #"[(（]([A-Za-z ,.'-]+.*?)[)）]"#
        
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return nil
        }
        
        // 在输入字符串中查找所有匹配项
        let matches = regex.matches(in: input, range: NSRange(input.startIndex..., in: input))
        
        // 取最后一个匹配项（通常英文句子在末尾括号）
        guard let lastMatch = matches.last else { return nil }
        
        // 提取捕获组内容并去除前后空格
        let range = lastMatch.range(at: 1)
        guard let swiftRange = Range(range, in: input) else { return nil }
        return String(input[swiftRange]).trimmingCharacters(in: .whitespaces)
    }
    
    private override init() {
        super.init()
        setupAudioSession()
    }
    
    private func setupAudioSession() {
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
            try AVAudioSession.sharedInstance().setActive(true)
        } catch {
            print("Failed to set audio session category: \(error)")
        }
    }
    
    func playPronunciation(word: String, le: String = "zh", rate: Float? = nil, onCompletion: (() -> Void)? = nil) {
        // 使用传入的速率或默认使用用户设置的速率
        let actualRate = rate ?? UserSettings.shared.playbackSpeed
        // Save the current playback rate
        currentPlaybackRate = actualRate
        
        // Determine which TTS service to use
        let ttsService = UserSettings.shared.ttsServiceType
        let playbackMode = UserSettings.shared.playbackMode
        
        // If playback mode is highestScoreSpeech, always use Youdao TTS
        if playbackMode == .highestScoreSpeech || ttsService == .youdaoTTS {
            playYoudaoPronunciation(word: word, le: le, rate: actualRate, onCompletion: onCompletion)
        } else {
            // Use Edge TTS for other modes if selected
            playEdgePronunciation(word: word, rate: actualRate, onCompletion: onCompletion)
        }
    }
    
    private func playYoudaoPronunciation(word: String, le: String = "zh", rate: Float = 1.0, onCompletion: (() -> Void)? = nil) {
        let url = PronounceURLGenerator.generatePronounceUrl(word: word, le: le)
        guard let audioUrl = URL(string: url) else { return }
        
        let playerItem = AVPlayerItem(url: audioUrl)
        
        // 保存完成回调
        self.completionHandler = onCompletion
        
        // 添加播放完成通知
        NotificationCenter.default.removeObserver(self, name: .AVPlayerItemDidPlayToEndTime, object: nil)
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(playerDidFinishPlaying(_:)),
            name: .AVPlayerItemDidPlayToEndTime,
            object: playerItem
        )
        
        if player == nil {
            player = AVPlayer(playerItem: playerItem)
        } else {
            player?.replaceCurrentItem(with: playerItem)
        }
        
        // Apply playback rate
        player?.rate = rate
        
        player?.seek(to: .zero)
        player?.play()
    }
    
    private func playEdgePronunciation(word: String, rate: Float = 1.0, onCompletion: (() -> Void)? = nil) {
        // Determine voice based on the content
        // Check if the text contains Chinese characters
        let isChineseText = word.contains { char in
            let scalars = char.unicodeScalars
            return scalars.contains { scalar in
                // Chinese character ranges
                (scalar.value >= 0x4E00 && scalar.value <= 0x9FFF) ||
                (scalar.value >= 0x3400 && scalar.value <= 0x4DBF) ||
                (scalar.value >= 0x20000 && scalar.value <= 0x2A6DF) ||
                (scalar.value >= 0x2A700 && scalar.value <= 0x2B73F) ||
                (scalar.value >= 0x2B740 && scalar.value <= 0x2B81F) ||
                (scalar.value >= 0x2B820 && scalar.value <= 0x2CEAF)
            }
        }
        
        var voice = isChineseText ? "zh-CN-XiaoxiaoNeural" : "en-US-AvaMultilingualNeural"
        voice = "en-US-AndrewMultilingualNeural"
        
        // Call Edge TTS Service
        EdgeTTSService.shared.synthesize(text: word, voice: voice) { [weak self] fileURL in
            guard let self = self, let url = fileURL else {
                DispatchQueue.main.async {
                    print("Failed to get Edge TTS audio, falling back to Youdao TTS")
                    self?.playYoudaoPronunciation(word: word, rate: rate, onCompletion: onCompletion)
                }
                return
            }
            
            DispatchQueue.main.async {
                self.playLocalAudio(url: url, rate: rate, onCompletion: onCompletion)
            }
        }
    }
    
    // 播放本地音频文件
    func playLocalAudio(url: URL, rate: Float? = nil, onCompletion: (() -> Void)? = nil) {
        // 使用传入的速率或默认使用用户设置的速率
        let actualRate = rate ?? UserSettings.shared.playbackSpeed
        do {
            // 停止当前播放
            player?.pause()
            audioPlayer?.stop()
            
            // 保存完成回调
            self.completionHandler = onCompletion
            
            // 设置音频会话
            try AVAudioSession.sharedInstance().setCategory(.playback)
            try AVAudioSession.sharedInstance().setActive(true)
            
            // 创建并播放
            audioPlayer = try AVAudioPlayer(contentsOf: url)
            audioPlayer?.delegate = self
            
            // Apply playback rate
            audioPlayer?.enableRate = true
            audioPlayer?.rate = actualRate
            
            audioPlayer?.prepareToPlay()
            audioPlayer?.play()
        } catch {
            print("Failed to play local audio: \(error)")
            onCompletion?()
        }
    }
    
    // Get current playback rate
    func getCurrentPlaybackRate() -> Float {
        return currentPlaybackRate
    }
    
    // Set playback rate for current player
    func setPlaybackRate(_ rate: Float) {
        currentPlaybackRate = rate
        
        // Apply to current player if any
        player?.rate = rate
        
        if let audioPlayer = audioPlayer {
            audioPlayer.enableRate = true
            audioPlayer.rate = rate
        }
    }
    
    func startBatchPlayback(
        words: [Any],
        startIndex: Int = 0,
        onWordChange: ((String, Int) -> Void)? = nil
    ) {
        stopPlayback()
        currentWords = words
        currentIndex = startIndex
        isLooping = true
        shouldPlayMemory = false
        self.onWordChangeWithIndex = onWordChange
        playNextContent()
    }
    
    func stopPlayback() {
        isLooping = false
        currentWords = nil
        currentIndex = 0
        shouldPlayMemory = false
        completionHandler = nil
        player?.pause()
        player?.seek(to: .zero)
        audioPlayer?.stop()
        NotificationCenter.default.removeObserver(self, name: .AVPlayerItemDidPlayToEndTime, object: nil)
        NowPlayingService.shared.clearNowPlayingInfo()
    }
    
    private func playNextContent() {
        guard let words = currentWords,
              isLooping,
              currentIndex < words.count else {
            if isLooping {
                currentIndex = 0
                shouldPlayMemory = false
                playNextContent()
            }
            return
        }
        
        let item = words[currentIndex]
        let playbackMode = UserSettings.shared.playbackMode
        let playbackSpeed = UserSettings.shared.playbackSpeed
        
        // Extract word and other properties based on type
        let word: String
        let memoryMethod: String?
        
        if let history = item as? History {
            word = history.word
            memoryMethod = history.memoryMethod
        } else if let reviewHistory = item as? ReviewHistoryItem {
            word = reviewHistory.word
            memoryMethod = reviewHistory.memoryMethod
        } else {
            // Skip unknown types
            currentIndex += 1
            playNextContent()
            return
        }
        
        // 通知当前播放的单词和索引变化
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.onWordChangeWithIndex?(word, self.currentIndex)
        }
        
        // 更新锁屏显示
        updateNowPlayingInfo(for: item)
        
        switch playbackMode {
        case .wordOnly:
            playPronunciation(word: word, le: "en", rate: playbackSpeed) { [weak self] in
                DispatchQueue.main.async {
                    guard let self = self else { return }
                    self.currentIndex += 1
                    self.playNextContent()
                }
            }
            
        case .memoryOnly:
            if let method = memoryMethod {
                playPronunciation(word: method, rate: playbackSpeed) { [weak self] in
                    DispatchQueue.main.async {
                        guard let self = self else { return }
                        self.currentIndex += 1
                        self.playNextContent()
                    }
                }
            } else {
                currentIndex += 1
                playNextContent()
            }
            
        case .englishMemoryOnly:
            if let method = memoryMethod, let englishSentence = extractEnglishSentence(from: method) {
                playPronunciation(word: englishSentence, le: "en", rate: playbackSpeed) { [weak self] in
                    DispatchQueue.main.async {
                        guard let self = self else { return }
                        self.currentIndex += 1
                        self.playNextContent()
                    }
                }
            } else {
                currentIndex += 1
                playNextContent()
            }
            
        case .wordAndMemory:
            if !shouldPlayMemory {
                playPronunciation(word: word, rate: playbackSpeed) { [weak self] in
                    DispatchQueue.main.async {
                        guard let self = self else { return }
                        self.shouldPlayMemory = true
                        self.playNextContent()
                    }
                }
            } else {
                if let method = memoryMethod {
                    playPronunciation(word: method, rate: playbackSpeed) { [weak self] in
                        DispatchQueue.main.async {
                            guard let self = self else { return }
                            self.currentIndex += 1
                            self.shouldPlayMemory = false
                            self.playNextContent()
                        }
                    }
                } else {
                    currentIndex += 1
                    shouldPlayMemory = false
                    playNextContent()
                }
            }
            
        case .highestScoreSpeech:
            // 查找该单词的最高分录音
            if let highestScoreRecording = SpeechRecordService.shared.findHighestScoreRecording(for: word) {
                // 如果找到最高分录音，播放录音
                playLocalAudio(url: highestScoreRecording.audioURL, rate: playbackSpeed) {
                    DispatchQueue.main.async {
                        self.currentIndex += 1
                        self.playNextContent()
                    }
                }
            } else {
                // 如果没有录音，播放单词发音
                playPronunciation(word: word, le: "en", rate: playbackSpeed) {
                    DispatchQueue.main.async {
                        self.currentIndex += 1
                        self.playNextContent()
                    }
                }
            }
        }
    }
    
    @objc private func playerDidFinishPlaying(_ notification: Notification) {
        // 只处理有道TTS的回调（AVPlayer通知）
        // Edge TTS通过audioPlayerDidFinishPlaying处理
        
        // 如果有单独的完成回调，则执行
        if let completion = completionHandler {
            DispatchQueue.main.async {
                completion()
                self.completionHandler = nil
            }
            return
        }
        
        // 当前处理循环模式下的Youdao TTS
        // Edge TTS已在各自的方法中处理，这里不需要重复处理
        if UserSettings.shared.ttsServiceType == .youdaoTTS {
            guard isLooping else { return }
            
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
                guard let self = self else { return }
                self.playNextContent()
            }
        }
    }
    
    func playNextWord() {
        guard isLooping else { return }
        currentIndex += 1
        playNextContent()
    }
    
    func playPreviousWord() {
        guard isLooping else { return }
        currentIndex = max(0, currentIndex - 1)
        playNextContent()
    }
    
    func pausePlayback() {
        player?.pause()
        audioPlayer?.pause()
    }
    
    func resumePlayback() {
        player?.play()
        audioPlayer?.play()
    }
    
    private func updateNowPlayingInfo(for item: Any) {
        print("Debug - Item object: \(item)")
        
        // Extract properties based on type
        let word: String
        let definitions: [Word.Definition]
        let pronunciation: History.Pronunciation?
        let memoryMethod: String?
        
        if let history = item as? History {
            word = history.word
            definitions = history.definitions
            pronunciation = history.pronunciation
            memoryMethod = history.memoryMethod
        } else if let reviewHistory = item as? ReviewHistoryItem {
            word = reviewHistory.word
            definitions = reviewHistory.definitions
            pronunciation = reviewHistory.pronunciation.map { parsed in
                History.Pronunciation(
                    American: parsed.American,
                    British: parsed.British
                )
            }
            memoryMethod = reviewHistory.memoryMethod
        } else {
            // Unknown type, skip
            return
        }
        
        // 获取所有释义并组合
        let definition = definitions
            .map { "\($0.pos) \($0.meaning)" }
            .joined(separator: "\n")
        
        print("Debug - Combined definition: \(definition)")
        
        let phonetic = pronunciation?.American
        print("Debug - Phonetic: \(String(describing: phonetic))")
        print("Debug - Memory method: \(String(describing: memoryMethod))")
        
        NowPlayingService.shared.updateNowPlayingInfo(
            word: word,
            definition: definition,
            phonetic: phonetic,
            memoryMethod: memoryMethod
        )
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
    }
}

// MARK: - AVAudioPlayerDelegate
extension AudioService: AVAudioPlayerDelegate {
    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            
            // 处理完成回调
            if let completion = self.completionHandler {
                completion()
                self.completionHandler = nil
            }
            
            // 清理
            self.audioPlayer = nil
        }
    }
}
