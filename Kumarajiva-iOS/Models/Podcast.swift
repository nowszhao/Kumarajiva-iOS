import Foundation

// MARK: - 播客节目模型
struct Podcast: Identifiable, Codable {
    let id: String
    let title: String
    let description: String
    let rssURL: String
    let imageURL: String?
    let author: String?
    let language: String?
    var episodes: [PodcastEpisode]
    let createdAt: Date
    let updatedAt: Date
    
    init(id: String = UUID().uuidString,
         title: String,
         description: String,
         rssURL: String,
         imageURL: String? = nil,
         author: String? = nil,
         language: String? = nil,
         episodes: [PodcastEpisode] = [],
         createdAt: Date = Date(),
         updatedAt: Date = Date()) {
        self.id = id
        self.title = title
        self.description = description
        self.rssURL = rssURL
        self.imageURL = imageURL
        self.author = author
        self.language = language
        self.episodes = episodes
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

// MARK: - 播客单集模型
struct PodcastEpisode: Identifiable, Codable {
    let id: String
    let title: String
    let description: String
    let audioURL: String
    let duration: TimeInterval
    let publishDate: Date
    let fileSize: Int64?
    let episodeType: String? // full, trailer, bonus
    var subtitles: [Subtitle]
    var subtitleGenerationDate: Date? // 字幕生成时间
    var subtitleVersion: String? // 字幕版本，用于管理更新
    
    init(id: String = UUID().uuidString,
         title: String,
         description: String,
         audioURL: String,
         duration: TimeInterval,
         publishDate: Date,
         fileSize: Int64? = nil,
         episodeType: String? = nil,
         subtitles: [Subtitle] = [],
         subtitleGenerationDate: Date? = nil,
         subtitleVersion: String? = nil) {
        self.id = id
        self.title = title
        self.description = description
        self.audioURL = audioURL
        self.duration = duration
        self.publishDate = publishDate
        self.fileSize = fileSize
        self.episodeType = episodeType
        self.subtitles = subtitles
        self.subtitleGenerationDate = subtitleGenerationDate
        self.subtitleVersion = subtitleVersion
    }
    
    // 检查是否有字幕
    var hasSubtitles: Bool {
        return !subtitles.isEmpty
    }
    
    // 获取字幕生成状态描述
    var subtitleStatusDescription: String {
        if hasSubtitles {
            if let date = subtitleGenerationDate {
                let formatter = DateFormatter()
                formatter.dateStyle = .short
                formatter.timeStyle = .short
                return "已生成 (\(formatter.string(from: date)))"
            } else {
                return "已生成"
            }
        } else {
            return "未生成"
        }
    }
}

// MARK: - 增强字幕模型
struct Subtitle: Identifiable, Codable {
    let id: String
    let startTime: TimeInterval
    let endTime: TimeInterval
    let text: String
    let confidence: Float? // Whisper识别置信度
    let words: [SubtitleWord] // 单词级别的时间戳
    let language: String? // 语言标识
    
    init(id: String = UUID().uuidString,
         startTime: TimeInterval,
         endTime: TimeInterval,
         text: String,
         confidence: Float? = nil,
         words: [SubtitleWord] = [],
         language: String? = nil) {
        self.id = id
        self.startTime = startTime
        self.endTime = endTime
        self.text = text
        self.confidence = confidence
        self.words = words.isEmpty ? Self.generateWordsFromText(text, startTime: startTime, endTime: endTime) : words
        self.language = language
    }
    
    // 从文本自动生成单词时间戳（当WhisperKit没有提供单词级别数据时）
    private static func generateWordsFromText(_ text: String, startTime: TimeInterval, endTime: TimeInterval) -> [SubtitleWord] {
        let words = text.components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .map { $0.trimmingCharacters(in: .punctuationCharacters) }
            .filter { !$0.isEmpty }
        
        guard !words.isEmpty else { return [] }
        
        let duration = endTime - startTime
        let timePerWord = duration / Double(words.count)
        
        return words.enumerated().map { index, word in
            let wordStartTime = startTime + Double(index) * timePerWord
            let wordEndTime = min(wordStartTime + timePerWord, endTime)
            
            return SubtitleWord(
                word: word,
                startTime: wordStartTime,
                endTime: wordEndTime,
                confidence: nil
            )
        }
    }
    
    // 获取指定时间的当前单词索引
    func getCurrentWordIndex(at time: TimeInterval) -> Int? {
        for (index, word) in words.enumerated() {
            if time >= word.startTime && time <= word.endTime {
                return index
            }
        }
        return nil
    }
    
    // 获取指定时间之前的所有单词（用于高亮显示）
    func getWordsBeforeTime(_ time: TimeInterval) -> [Int] {
        return words.enumerated().compactMap { index, word in
            time >= word.endTime ? index : nil
        }
    }
    
    // 获取当前正在播放的单词（用于高亮显示）
    func getCurrentPlayingWordIndex(at time: TimeInterval) -> Int? {
        for (index, word) in words.enumerated() {
            if time >= word.startTime && time < word.endTime {
                return index
            }
        }
        return nil
    }
}

// MARK: - 单词级别字幕模型
struct SubtitleWord: Identifiable, Codable {
    let id: String
    let word: String
    let startTime: TimeInterval
    let endTime: TimeInterval
    let confidence: Float? // 单词识别置信度
    
    init(id: String = UUID().uuidString,
         word: String,
         startTime: TimeInterval,
         endTime: TimeInterval,
         confidence: Float? = nil) {
        self.id = id
        self.word = word
        self.startTime = startTime
        self.endTime = endTime
        self.confidence = confidence
    }
    
    // 单词持续时间
    var duration: TimeInterval {
        return endTime - startTime
    }
    
    // 是否为标点符号
    var isPunctuation: Bool {
        return word.rangeOfCharacter(from: .letters) == nil
    }
}

// MARK: - 播放状态模型
struct PodcastPlaybackState {
    var isPlaying: Bool = false
    var currentTime: TimeInterval = 0
    var duration: TimeInterval = 0
    var playbackRate: Float = 1.0
    var currentSubtitleIndex: Int? = nil
    var currentWordIndex: Int? = nil // 当前播放的单词索引
    var isLooping: Bool = false
    var currentEpisode: PodcastEpisode?
    
    var progress: Double {
        guard duration > 0 else { return 0 }
        return currentTime / duration
    }
    
    // 获取当前字幕
    func getCurrentSubtitle(from subtitles: [Subtitle]) -> Subtitle? {
        guard let index = currentSubtitleIndex,
              index >= 0 && index < subtitles.count else { return nil }
        return subtitles[index]
    }
    
    // 获取当前单词
    func getCurrentWord(from subtitles: [Subtitle]) -> SubtitleWord? {
        guard let subtitle = getCurrentSubtitle(from: subtitles),
              let wordIndex = currentWordIndex,
              wordIndex >= 0 && wordIndex < subtitle.words.count else { return nil }
        return subtitle.words[wordIndex]
    }
}

// MARK: - RSS解析结果
struct RSSParseResult {
    let podcast: Podcast
    let episodes: [PodcastEpisode]
    let error: Error?
}

// MARK: - 字幕管理相关枚举
enum SubtitleQuality: String, CaseIterable, Codable {
    case low = "low"
    case medium = "medium"
    case high = "high"
    
    var description: String {
        switch self {
        case .low: return "低质量"
        case .medium: return "中等质量"
        case .high: return "高质量"
        }
    }
    
    var whisperModel: String {
        switch self {
        case .low: return "tiny"
        case .medium: return "base"
        case .high: return "small"
        }
    }
}

enum SubtitleError: Error, LocalizedError {
    case generationFailed(String)
    case noAudioData
    case invalidFormat
    case saveFailed
    case deleteFailed
    
    var errorDescription: String? {
        switch self {
        case .generationFailed(let message):
            return "字幕生成失败: \(message)"
        case .noAudioData:
            return "没有音频数据"
        case .invalidFormat:
            return "无效的字幕格式"
        case .saveFailed:
            return "字幕保存失败"
        case .deleteFailed:
            return "字幕删除失败"
        }
    }
} 

// MARK: - 生词解析模型
struct DifficultVocabulary: Codable, Identifiable, Equatable {
    let id = UUID()
    let vocabulary: String
    let type: String
    let partOfSpeech: String
    let phonetic: String
    let chineseMeaning: String
    let chineseEnglishSentence: String
    
    enum CodingKeys: String, CodingKey {
        case vocabulary
        case type
        case partOfSpeech = "part_of_speech"
        case phonetic
        case chineseMeaning = "chinese_meaning"
        case chineseEnglishSentence = "chinese_english_sentence"
    }
    
    // Equatable conformance - compare by vocabulary content, not UUID
    static func == (lhs: DifficultVocabulary, rhs: DifficultVocabulary) -> Bool {
        return lhs.vocabulary == rhs.vocabulary &&
               lhs.type == rhs.type &&
               lhs.partOfSpeech == rhs.partOfSpeech &&
               lhs.phonetic == rhs.phonetic &&
               lhs.chineseMeaning == rhs.chineseMeaning &&
               lhs.chineseEnglishSentence == rhs.chineseEnglishSentence
    }
}

struct VocabularyAnalysisResponse: Codable {
    let difficultVocabulary: [DifficultVocabulary]
    
    enum CodingKeys: String, CodingKey {
        case difficultVocabulary = "difficult_vocabulary"
    }
}

// MARK: - 生词解析状态
enum VocabularyAnalysisState: Equatable {
    case idle
    case analyzing
    case completed([DifficultVocabulary])
    case failed(String)
    
    static func == (lhs: VocabularyAnalysisState, rhs: VocabularyAnalysisState) -> Bool {
        switch (lhs, rhs) {
        case (.idle, .idle), (.analyzing, .analyzing):
            return true
        case (.completed(let lhsVocab), .completed(let rhsVocab)):
            return lhsVocab == rhsVocab
        case (.failed(let lhsError), .failed(let rhsError)):
            return lhsError == rhsError
        default:
            return false
        }
    }
}

// MARK: - 播放状态枚举
enum EpisodePlaybackStatus: String, CaseIterable, Codable {
    case notPlayed = "not_played"      // 未播放
    case playing = "playing"           // 播放中
    case completed = "completed"       // 播放完成
    
    var displayName: String {
        switch self {
        case .notPlayed: return "未播放"
        case .playing: return "播放中"
        case .completed: return "播放完成"
        }
    }
    
    var icon: String {
        switch self {
        case .notPlayed: return "circle"
        case .playing: return "play.circle.fill"
        case .completed: return "checkmark.circle.fill"
        }
    }
}

// MARK: - 播放历史记录
struct EpisodePlaybackRecord: Codable, Identifiable {
    let id: String
    let episodeId: String
    var currentTime: TimeInterval
    var duration: TimeInterval
    var lastPlayedDate: Date
    var isCompleted: Bool
    
    init(episodeId: String, currentTime: TimeInterval = 0, duration: TimeInterval = 0) {
        self.id = UUID().uuidString
        self.episodeId = episodeId
        self.currentTime = currentTime
        self.duration = duration
        self.lastPlayedDate = Date()
        self.isCompleted = false
    }
    
    // 计算播放进度
    var progress: Double {
        guard duration > 0 else { return 0 }
        return min(currentTime / duration, 1.0)
    }
    
    // 获取播放状态
    var status: EpisodePlaybackStatus {
        if isCompleted {
            return .completed
        } else if currentTime > 0 {
            return .playing
        } else {
            return .notPlayed
        }
    }
} 