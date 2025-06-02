import Foundation

// MARK: - YouTuber 模型
struct YouTuber: Identifiable, Codable, Hashable {
    let id = UUID()
    let channelId: String // YouTube频道ID，如 @LexClips
    var title: String
    var description: String?
    var thumbnailURL: String?
    var subscriberCount: String?
    var videoCount: Int = 0
    var videos: [YouTubeVideo] = []
    var subscribedAt: Date = Date()
    var updatedAt: Date = Date()
    
    // 自定义编码键，排除计算属性
    enum CodingKeys: String, CodingKey {
        case channelId, title, description, thumbnailURL
        case subscriberCount, videoCount, videos
        case subscribedAt, updatedAt
    }
    
    static func == (lhs: YouTuber, rhs: YouTuber) -> Bool {
        return lhs.channelId == rhs.channelId
    }
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(channelId)
    }
}

// MARK: - YouTube 视频模型
struct YouTubeVideo: Identifiable, Codable, Hashable {
    let id = UUID()
    let videoId: String // YouTube视频ID
    var title: String
    var description: String?
    var thumbnailURL: String?
    var duration: TimeInterval = 0
    var publishDate: Date = Date()
    var viewCount: String?
    var audioURL: String? // 提取的音频URL
    var subtitles: [Subtitle] = [] // 字幕数据，复用播客的字幕模型
    var hasSubtitles: Bool { !subtitles.isEmpty }
    
    // YouTube视频的完整URL
    var youtubeURL: String {
        return "https://www.youtube.com/watch?v=\(videoId)"
    }
    
    enum CodingKeys: String, CodingKey {
        case videoId, title, description, thumbnailURL
        case duration, publishDate, viewCount, audioURL, subtitles
    }
    
    static func == (lhs: YouTubeVideo, rhs: YouTubeVideo) -> Bool {
        return lhs.videoId == rhs.videoId
    }
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(videoId)
    }
}

// MARK: - 示例数据
extension YouTuber {
    static let example = YouTuber(
        channelId: "@LexClips",
        title: "Lex Clips",
        description: "Clips from The Lex Fridman Podcast",
        thumbnailURL: "https://yt3.googleusercontent.com/example",
        subscriberCount: "1.2M",
        videoCount: 150,
        videos: [YouTubeVideo.example]
    )
}

extension YouTubeVideo {
    static let example = YouTubeVideo(
        videoId: "dQw4w9WgXcQ",
        title: "Sample Video Title",
        description: "This is a sample video description",
        thumbnailURL: "https://img.youtube.com/vi/dQw4w9WgXcQ/maxresdefault.jpg",
        duration: 180,
        publishDate: Date(),
        viewCount: "1.2M views"
    )
}

// MARK: - YouTube API 响应模型（真实API集成）

/// YouTube 频道响应
struct YouTubeChannelResponse: Codable {
    let kind: String
    let etag: String
    let pageInfo: YouTubePageInfo
    let items: [YouTubeChannelData]
}

/// YouTube 频道数据
struct YouTubeChannelData: Codable {
    let kind: String
    let etag: String
    let id: String
    let snippet: YouTubeChannelSnippet
    let statistics: YouTubeChannelStatistics
}

/// YouTube 频道片段信息
struct YouTubeChannelSnippet: Codable {
    let title: String
    let description: String
    let customUrl: String?
    let publishedAt: String
    let thumbnails: YouTubeThumbnails
    let localized: YouTubeLocalizedInfo?
    let country: String?
}

/// YouTube 频道统计信息
struct YouTubeChannelStatistics: Codable {
    let viewCount: String?
    let subscriberCount: String?
    let hiddenSubscriberCount: Bool?
    let videoCount: String?
}

/// YouTube 本地化信息
struct YouTubeLocalizedInfo: Codable {
    let title: String
    let description: String
}

/// YouTube 搜索响应
struct YouTubeSearchResponse: Codable {
    let kind: String
    let etag: String
    let nextPageToken: String?
    let regionCode: String?
    let pageInfo: YouTubePageInfo
    let items: [YouTubeSearchItem]
}

/// YouTube 搜索项目
struct YouTubeSearchItem: Codable {
    let kind: String
    let etag: String
    let id: YouTubeSearchId
    let snippet: YouTubeVideoSnippet
}

/// YouTube 搜索ID
struct YouTubeSearchId: Codable {
    let kind: String
    let videoId: String?
    let channelId: String?
    let playlistId: String?
}

/// YouTube 视频搜索响应
struct YouTubeVideoSearchResponse: Codable {
    let kind: String
    let etag: String
    let nextPageToken: String?
    let regionCode: String?
    let pageInfo: YouTubePageInfo
    let items: [YouTubeVideoSearchItem]
}

/// YouTube 视频搜索项目
struct YouTubeVideoSearchItem: Codable {
    let kind: String
    let etag: String
    let id: YouTubeSearchId
    let snippet: YouTubeVideoSnippet
}

/// YouTube 视频片段信息
struct YouTubeVideoSnippet: Codable {
    let publishedAt: String
    let channelId: String
    let title: String
    let description: String
    let thumbnails: YouTubeThumbnails
    let channelTitle: String
    let tags: [String]?
    let categoryId: String?
    let liveBroadcastContent: String?
    let localized: YouTubeLocalizedInfo?
    let defaultAudioLanguage: String?
}

/// YouTube 视频详情响应
struct YouTubeVideoDetailsResponse: Codable {
    let kind: String
    let etag: String
    let items: [YouTubeVideoDetails]
}

/// YouTube 视频详情
struct YouTubeVideoDetails: Codable {
    let kind: String
    let etag: String
    let id: String
    let snippet: YouTubeVideoSnippet
    let contentDetails: YouTubeVideoContentDetails
    let statistics: YouTubeVideoStatistics
}

/// YouTube 视频内容详情
struct YouTubeVideoContentDetails: Codable {
    let duration: String
    let dimension: String?
    let definition: String?
    let caption: String?
    let licensedContent: Bool?
    let regionRestriction: YouTubeRegionRestriction?
    let contentRating: YouTubeContentRating?
    let projection: String?
}

/// YouTube 视频统计信息
struct YouTubeVideoStatistics: Codable {
    let viewCount: String?
    let likeCount: String?
    let dislikeCount: String?
    let favoriteCount: String?
    let commentCount: String?
}

/// YouTube 地区限制
struct YouTubeRegionRestriction: Codable {
    let allowed: [String]?
    let blocked: [String]?
}

/// YouTube 内容评级
struct YouTubeContentRating: Codable {
    let ytRating: String?
}

/// YouTube 缩略图集合
struct YouTubeThumbnails: Codable {
    let `default`: YouTubeThumbnail?
    let medium: YouTubeThumbnail?
    let high: YouTubeThumbnail?
    let standard: YouTubeThumbnail?
    let maxres: YouTubeThumbnail?
}

/// YouTube 缩略图
struct YouTubeThumbnail: Codable {
    let url: String
    let width: Int?
    let height: Int?
}

/// YouTube 分页信息
struct YouTubePageInfo: Codable {
    let totalResults: Int
    let resultsPerPage: Int
} 