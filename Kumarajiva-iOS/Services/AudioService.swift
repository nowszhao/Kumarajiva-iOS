import Foundation
import AVFoundation

class AudioService: NSObject, AVPlayerItemMetadataOutputPushDelegate {
    static let shared = AudioService()
    private var player: AVPlayer?
    private var isLooping = false
    private var currentWords: [History]?
    private var currentIndex = 0
    private var shouldPlayMemory = false
    
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
    
    func playPronunciation(word: String) {
        let url = PronounceURLGenerator.generatePronounceUrl(word: word, type: "2")
        guard let audioUrl = URL(string: url) else { return }
        
        let playerItem = AVPlayerItem(url: audioUrl)
        
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
    
    func startBatchPlayback(words: [History]) {
        stopPlayback()
        currentWords = words
        currentIndex = 0
        isLooping = true
        shouldPlayMemory = false
        playNextContent()
    }
    
    func stopPlayback() {
        isLooping = false
        currentWords = nil
        currentIndex = 0
        shouldPlayMemory = false
        player?.pause()
        player?.seek(to: .zero)
        NotificationCenter.default.removeObserver(self, name: .AVPlayerItemDidPlayToEndTime, object: nil)
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
        
        switch playbackMode {
        case .wordOnly:
            playPronunciation(word: history.word)
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
        guard isLooping else { return }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
            guard let self = self else { return }
            self.playNextContent()
        }
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
    }
} 