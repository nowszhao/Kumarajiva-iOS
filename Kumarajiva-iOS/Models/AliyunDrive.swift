import Foundation

// MARK: - 阿里云盘账号模型
struct AliyunDrive: Identifiable, Codable, Hashable {
    let id = UUID()
    let driveId: String              // 云盘ID
    let userId: String               // 用户ID
    var nickname: String             // 用户昵称
    var avatar: String?              // 头像URL
    var totalSize: Int64             // 总容量
    var usedSize: Int64              // 已用容量
    var mediaFiles: [AliyunMediaFile] = []  // 媒体文件列表
    var subscribedAt: Date = Date()
    var updatedAt: Date = Date()
    
    enum CodingKeys: String, CodingKey {
        case driveId, userId, nickname, avatar
        case totalSize, usedSize, mediaFiles
        case subscribedAt, updatedAt
    }
    
    static func == (lhs: AliyunDrive, rhs: AliyunDrive) -> Bool {
        return lhs.driveId == rhs.driveId
    }
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(driveId)
    }
    
    // 格式化容量显示
    var formattedTotalSize: String {
        return ByteCountFormatter.string(fromByteCount: totalSize, countStyle: .file)
    }
    
    var formattedUsedSize: String {
        return ByteCountFormatter.string(fromByteCount: usedSize, countStyle: .file)
    }
    
    var usagePercentage: Double {
        guard totalSize > 0 else { return 0 }
        return Double(usedSize) / Double(totalSize)
    }
    
    // 统计信息
    var videoCount: Int {
        mediaFiles.filter { $0.type == .video }.count
    }
    
    var audioCount: Int {
        mediaFiles.filter { $0.type == .audio }.count
    }
}

// MARK: - 阿里云盘媒体文件模型
struct AliyunMediaFile: Identifiable, Codable, Hashable {
    let id = UUID()
    let fileId: String               // 文件ID
    let driveId: String              // 所属云盘ID
    let parentFileId: String         // 父文件夹ID
    var name: String                 // 文件名
    var type: MediaType              // 音频/视频
    var size: Int64                  // 文件大小
    var duration: TimeInterval       // 时长
    var thumbnailURL: String?        // 缩略图
    var category: String?            // 分类(video/audio)
    var createdAt: Date              // 创建时间
    var updatedAt: Date              // 更新时间
    
    // 播放相关(运行时数据,不持久化)
    var playURL: String?             // 播放URL(临时)
    var playCursor: TimeInterval?    // 播放进度
    var subtitles: [Subtitle] = []   // 字幕数据
    
    enum MediaType: String, Codable {
        case audio, video
    }
    
    enum CodingKeys: String, CodingKey {
        case fileId, driveId, parentFileId, name, type
        case size, duration, thumbnailURL, category
        case createdAt, updatedAt, playCursor
    }
    
    static func == (lhs: AliyunMediaFile, rhs: AliyunMediaFile) -> Bool {
        return lhs.fileId == rhs.fileId
    }
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(fileId)
    }
    
    // 格式化文件大小
    var formattedSize: String {
        return ByteCountFormatter.string(fromByteCount: size, countStyle: .file)
    }
    
    // 格式化时长
    var formattedDuration: String {
        let hours = Int(duration) / 3600
        let minutes = Int(duration) / 60 % 60
        let seconds = Int(duration) % 60
        
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        } else {
            return String(format: "%d:%02d", minutes, seconds)
        }
    }
}

// MARK: - 阿里云盘字幕文件模型
struct AliyunSubtitleFile: Identifiable, Codable, Hashable {
    let id = UUID()
    let fileId: String               // 字幕文件ID
    let driveId: String              // 所属云盘ID
    var name: String                 // 文件名
    var format: SubtitleFormat       // 格式
    var size: Int64                  // 文件大小
    
    enum SubtitleFormat: String, Codable, CaseIterable {
        case ass, srt, vtt, ssa
        
        var priority: Int {
            switch self {
            case .ass: return 4  // 最高优先级
            case .ssa: return 3
            case .srt: return 2
            case .vtt: return 1
            }
        }
        
        var displayName: String {
            switch self {
            case .ass: return "ASS字幕"
            case .ssa: return "SSA字幕"
            case .srt: return "SRT字幕"
            case .vtt: return "VTT字幕"
            }
        }
        
        var icon: String {
            switch self {
            case .ass, .ssa: return "star.fill"
            case .srt, .vtt: return "captions.bubble"
            }
        }
    }
    
    static func == (lhs: AliyunSubtitleFile, rhs: AliyunSubtitleFile) -> Bool {
        return lhs.fileId == rhs.fileId
    }
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(fileId)
    }
}

// MARK: - 阿里云盘 API 响应模型

/// 用户和云盘信息响应（阿里云盘 API 返回的是统一的用户信息）
struct AliyunUserInfoResponse: Codable {
    let userId: String
    let nickName: String
    let avatar: String?
    let defaultDriveId: String
    let backupDriveId: String?
    let resourceDriveId: String?
    
    enum CodingKeys: String, CodingKey {
        case userId = "user_id"
        case nickName = "nick_name"
        case avatar
        case defaultDriveId = "default_drive_id"
        case backupDriveId = "backup_drive_id"
        case resourceDriveId = "resource_drive_id"
    }
}

/// 云盘容量信息响应
struct AliyunDriveSpaceInfoResponse: Codable {
    let personalSpaceInfo: PersonalSpaceInfo
    
    enum CodingKeys: String, CodingKey {
        case personalSpaceInfo = "personal_space_info"
    }
    
    struct PersonalSpaceInfo: Codable {
        let totalSize: Int64
        let usedSize: Int64
        
        enum CodingKeys: String, CodingKey {
            case totalSize = "total_size"
            case usedSize = "used_size"
        }
    }
}

/// 文件列表响应
struct AliyunFileListResponse: Codable {
    let items: [AliyunFileItem]
    let nextMarker: String?
    
    enum CodingKeys: String, CodingKey {
        case items
        case nextMarker = "next_marker"
    }
}

/// 文件项
struct AliyunFileItem: Codable {
    let fileId: String
    let name: String
    let type: String  // "file" or "folder"
    let category: String?  // "video", "audio", etc.
    let size: Int64?  // 文件夹的 size 为 null
    let createdAt: String
    let updatedAt: String
    let thumbnail: String?
    let videoMediaMetadata: VideoMetadata?
    
    enum CodingKeys: String, CodingKey {
        case fileId = "file_id"
        case name
        case type
        case category
        case size
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case thumbnail
        case videoMediaMetadata = "video_media_metadata"
    }
    
    struct VideoMetadata: Codable {
        let duration: String?
        let width: Int?
        let height: Int?
    }
}

/// 视频播放信息响应
struct AliyunVideoPlayInfoResponse: Codable {
    let videoPreviewPlayInfo: VideoPreviewPlayInfo
    
    enum CodingKeys: String, CodingKey {
        case videoPreviewPlayInfo = "video_preview_play_info"
    }
    
    struct VideoPreviewPlayInfo: Codable {
        let liveTranscodingTaskList: [TranscodingTask]
        
        enum CodingKeys: String, CodingKey {
            case liveTranscodingTaskList = "live_transcoding_task_list"
        }
    }
    
    struct TranscodingTask: Codable {
        let templateId: String
        let status: String
        let url: String?
        
        enum CodingKeys: String, CodingKey {
            case templateId = "template_id"
            case status
            case url
        }
    }
}

/// 下载URL响应
struct AliyunDownloadURLResponse: Codable {
    let url: String
    let expiration: String?
    
    enum CodingKeys: String, CodingKey {
        case url
        case expiration
    }
}

/// OAuth 二维码响应
struct AliyunQRCodeResponse: Codable {
    let sid: String
    let qrCodeUrl: String
    
    enum CodingKeys: String, CodingKey {
        case sid
        case qrCodeUrl = "qrCodeUrl"
    }
}

/// 二维码状态响应
struct AliyunQRCodeStatusResponse: Codable {
    let status: String  // "WaitLogin", "ScanSuccess", "LoginSuccess", "QRCodeExpired"
    let authCode: String?
    
    enum CodingKeys: String, CodingKey {
        case status
        case authCode = "authCode"
    }
}

/// Token 响应
struct AliyunTokenResponse: Codable {
    let accessToken: String
    let refreshToken: String
    let expiresIn: Int
    
    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case refreshToken = "refresh_token"
        case expiresIn = "expires_in"
    }
}

// MARK: - 示例数据
extension AliyunDrive {
    static let example = AliyunDrive(
        driveId: "123456",
        userId: "user123",
        nickname: "我的云盘",
        avatar: nil,
        totalSize: 1099511627776, // 1TB
        usedSize: 107374182400,   // 100GB
        mediaFiles: [AliyunMediaFile.example]
    )
}

extension AliyunMediaFile {
    static let example = AliyunMediaFile(
        fileId: "file123",
        driveId: "123456",
        parentFileId: "root",
        name: "示例视频.mp4",
        type: .video,
        size: 1073741824, // 1GB
        duration: 3600,
        thumbnailURL: nil,
        category: "video",
        createdAt: Date(),
        updatedAt: Date()
    )
}

// MARK: - AliyunMediaFile 遵循 PlayableContent 协议
extension AliyunMediaFile: PlayableContent {
    var title: String {
        return name
    }
    
    var contentDescription: String {
        return "\(formattedSize) • \(formattedDuration)"
    }
    
    var publishDate: Date {
        return createdAt
    }
    
    var playableAudioURL: String? {
        return playURL
    }
    
    var hasSubtitles: Bool {
        return !subtitles.isEmpty
    }
}
