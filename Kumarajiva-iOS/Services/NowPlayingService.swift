import MediaPlayer
import AVFoundation

class NowPlayingService {
    static let shared = NowPlayingService()
    
    private init() {
        setupAudioSession()
        setupRemoteCommandCenter()
    }
    
    private func setupAudioSession() {
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
            try AVAudioSession.sharedInstance().setActive(true)
        } catch {
            print("Failed to set up audio session: \(error)")
        }
    }
    
    private func setupRemoteCommandCenter() {
        let commandCenter = MPRemoteCommandCenter.shared()
        
        // 播放/暂停命令
        commandCenter.playCommand.addTarget { [weak self] _ in
            AudioService.shared.resumePlayback()
            return .success
        }
        
        commandCenter.pauseCommand.addTarget { [weak self] _ in
            AudioService.shared.pausePlayback()
            return .success
        }
        
        // 下一个/上一个命令
        commandCenter.nextTrackCommand.addTarget { [weak self] _ in
            AudioService.shared.playNextWord()
            return .success
        }
        
        commandCenter.previousTrackCommand.addTarget { [weak self] _ in
            AudioService.shared.playPreviousWord()
            return .success
        }
    }
    
    func updateNowPlayingInfo(word: String, definition: String? = nil, phonetic: String? = nil, memoryMethod: String? = nil) {
        var nowPlayingInfo = [String: Any]()

        // 标题：单词
        nowPlayingInfo[MPMediaItemPropertyTitle] = word

        // 副标题：音标 + 释义（换行）
        var subtitle = ""
//        if let phonetic = phonetic {
//            subtitle += phonetic
//        }
        if let definition = definition {
            subtitle += "\(definition)"
        }
        if !subtitle.isEmpty {
            nowPlayingInfo[MPMediaItemPropertyArtist] = subtitle
        }

        // 专辑标题：记忆方法（如果存在）
        if let memoryMethod = memoryMethod, !memoryMethod.isEmpty {
            nowPlayingInfo[MPMediaItemPropertyAlbumTitle] = "记忆方法：\(memoryMethod)"
        }

        // 歌词：完整描述（需用户主动查看）
        var description = ""
        if let definition = definition {
            description += "释义：\(definition)"
        }
        if let memoryMethod = memoryMethod, !memoryMethod.isEmpty {
            description += "\n\n记忆方法：\(memoryMethod)"
        }
        if !description.isEmpty {
            nowPlayingInfo[MPMediaItemPropertyLyrics] = description
        }

        // 设置图标
        if let image = UIImage(named: "AppIcon") ?? UIImage(named: "AppIcon60x60") {
            nowPlayingInfo[MPMediaItemPropertyArtwork] = MPMediaItemArtwork(boundsSize: image.size) { _ in
                return image
            }
        }

        MPNowPlayingInfoCenter.default().nowPlayingInfo = nowPlayingInfo
    }
    
    func clearNowPlayingInfo() {
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
    }
} 
