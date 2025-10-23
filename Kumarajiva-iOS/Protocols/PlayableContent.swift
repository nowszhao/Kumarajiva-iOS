import Foundation

// MARK: - 可播放内容协议
/// 定义播客和YouTube视频的共同接口
protocol PlayableContent {
    var title: String { get }
    var contentDescription: String { get }
    var duration: TimeInterval { get }
    var publishDate: Date { get }
    var playableAudioURL: String? { get }
    var subtitles: [Subtitle] { get }
    var hasSubtitles: Bool { get }
}

// MARK: - PodcastEpisode 遵循协议
extension PodcastEpisode: PlayableContent {
    var contentDescription: String {
        return self.description
    }
    
    var playableAudioURL: String? {
        return self.audioURL
    }
}

// MARK: - YouTubeVideo 遵循协议
extension YouTubeVideo: PlayableContent {
    var contentDescription: String {
        return self.description ?? ""
    }
    
    var playableAudioURL: String? {
        return self.audioURL
    }
}
