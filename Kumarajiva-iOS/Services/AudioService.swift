import Foundation
import AVFoundation

class AudioService: NSObject, AVPlayerItemMetadataOutputPushDelegate {
    static let shared = AudioService()
    private var player: AVPlayer?
    private var isLooping = false
    private var currentWords: [History]?
    private var currentIndex = 0
    private var shouldPlayMemory = false
    private var onWordChangeWithIndex: ((String, Int) -> Void)?
    private var completionHandler: (() -> Void)?
    
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
    
    func playPronunciation(word: String, le: String = "zh", onCompletion: (() -> Void)? = nil) {
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
        
        player?.seek(to: .zero)
        player?.play()
    }
    
    func startBatchPlayback(
        words: [History],
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
        
        let history = words[currentIndex]
        let playbackMode = UserSettings.shared.playbackMode
        
        // 通知当前播放的单词和索引变化
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.onWordChangeWithIndex?(history.word, self.currentIndex)
        }
        
        // 更新锁屏显示
        updateNowPlayingInfo(for: history)
        
        switch playbackMode {
        case .wordOnly:
            playPronunciation(word: history.word, le: "en")
            currentIndex += 1
            
        case .memoryOnly:
            if let method = history.memoryMethod {
                playPronunciation(word: method)
                currentIndex += 1
            } else {
                currentIndex += 1
                playNextContent()
            }
            
        case .wordAndMemory:
            if !shouldPlayMemory {
                playPronunciation(word: history.word)
                shouldPlayMemory = true
            } else {
                if let method = history.memoryMethod {
                    playPronunciation(word: method)
                }
                currentIndex += 1
                shouldPlayMemory = false
            }
        }
    }
    
    @objc private func playerDidFinishPlaying(_ notification: Notification) {
        // 如果有单独的完成回调，则执行
        if let completion = completionHandler, !isLooping {
            DispatchQueue.main.async {
                completion()
                self.completionHandler = nil
            }
            return
        }
        
        // 如果是循环播放，则继续下一条
        guard isLooping else { return }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
            guard let self = self else { return }
            self.playNextContent()
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
    }
    
    func resumePlayback() {
        player?.play()
    }
    
    private func updateNowPlayingInfo(for history: History) {
        print("Debug - History object: \(history)")
        
        // 获取所有释义并组合
        let definition = history.definitions
            .map { "\($0.pos) \($0.meaning)" }
            .joined(separator: "\n")
        
        print("Debug - Combined definition: \(definition)")
        
        let phonetic = history.pronunciation?.American
        print("Debug - Phonetic: \(String(describing: phonetic))")
        print("Debug - Memory method: \(String(describing: history.memoryMethod))")
        
        NowPlayingService.shared.updateNowPlayingInfo(
            word: history.word,
            definition: definition,
            phonetic: phonetic,
            memoryMethod: history.memoryMethod
        )
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
    }
} 
