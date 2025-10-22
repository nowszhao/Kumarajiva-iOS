import Foundation

/// 字幕跟读练习记录
struct SubtitlePracticeRecord: Identifiable, Codable {
    var id = UUID()
    let videoId: String
    let subtitleId: String
    let subtitleText: String
    let audioURL: URL
    let timestamp: Date
    let score: Int
    let recognizedText: String
    let wordMatchResults: [SubtitleWordMatch]
    
    enum CodingKeys: String, CodingKey {
        case id, videoId, subtitleId, subtitleText, audioURLString, timestamp, score, recognizedText, wordMatchResults
    }
    
    init(videoId: String, subtitleId: String, subtitleText: String, audioURL: URL, timestamp: Date, score: Int, recognizedText: String, wordMatchResults: [SubtitleWordMatch]) {
        self.id = UUID()
        self.videoId = videoId
        self.subtitleId = subtitleId
        self.subtitleText = subtitleText
        self.audioURL = audioURL
        self.timestamp = timestamp
        self.score = score
        self.recognizedText = recognizedText
        self.wordMatchResults = wordMatchResults
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        videoId = try container.decode(String.self, forKey: .videoId)
        subtitleId = try container.decode(String.self, forKey: .subtitleId)
        subtitleText = try container.decode(String.self, forKey: .subtitleText)
        let urlString = try container.decode(String.self, forKey: .audioURLString)
        
        // 处理URL - 如果是绝对路径，直接使用；如果是相对路径，构建完整路径
        if urlString.hasPrefix("file://") {
            guard let url = URL(string: urlString) else {
                throw DecodingError.dataCorruptedError(
                    forKey: .audioURLString,
                    in: container,
                    debugDescription: "Invalid URL string: \(urlString)"
                )
            }
            audioURL = url
        } else {
            let containerURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            let recordingsDirectory = containerURL.appendingPathComponent("SubtitlePracticeRecordings", isDirectory: true)
            audioURL = recordingsDirectory.appendingPathComponent(urlString)
        }
        
        timestamp = try container.decode(Date.self, forKey: .timestamp)
        score = try container.decode(Int.self, forKey: .score)
        recognizedText = try container.decode(String.self, forKey: .recognizedText)
        wordMatchResults = try container.decode([SubtitleWordMatch].self, forKey: .wordMatchResults)
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(videoId, forKey: .videoId)
        try container.encode(subtitleId, forKey: .subtitleId)
        try container.encode(subtitleText, forKey: .subtitleText)
        
        // 存储相对路径而非绝对路径
        let containerURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let recordingsDirectory = containerURL.appendingPathComponent("SubtitlePracticeRecordings", isDirectory: true)
        
        if audioURL.path.hasPrefix(recordingsDirectory.path) {
            let relativePath = audioURL.lastPathComponent
            try container.encode(relativePath, forKey: .audioURLString)
        } else {
            try container.encode(audioURL.absoluteString, forKey: .audioURLString)
        }
        
        try container.encode(timestamp, forKey: .timestamp)
        try container.encode(score, forKey: .score)
        try container.encode(recognizedText, forKey: .recognizedText)
        try container.encode(wordMatchResults, forKey: .wordMatchResults)
    }
}

/// 字幕单词匹配结果
struct SubtitleWordMatch: Codable {
    let originalWord: String
    let recognizedWord: String?
    let isMatch: Bool
}

/// 字幕练习统计数据
struct SubtitlePracticeStats: Codable {
    let videoId: String
    let subtitleId: String
    var practiceCount: Int
    var highestScore: Int
    var averageScore: Double
    var records: [SubtitlePracticeRecord]
    
    init(videoId: String, subtitleId: String) {
        self.videoId = videoId
        self.subtitleId = subtitleId
        self.practiceCount = 0
        self.highestScore = 0
        self.averageScore = 0.0
        self.records = []
    }
    
    mutating func addRecord(_ record: SubtitlePracticeRecord) {
        records.append(record)
        practiceCount = records.count
        highestScore = max(highestScore, record.score)
        averageScore = Double(records.map { $0.score }.reduce(0, +)) / Double(records.count)
    }
}
