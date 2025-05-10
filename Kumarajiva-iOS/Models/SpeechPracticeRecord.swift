import Foundation

struct SpeechPracticeRecord: Identifiable, Codable {
    var id = UUID()
    let word: String
    let example: String
    let audioURL: URL
    let timestamp: Date
    let score: Int
    
    enum CodingKeys: String, CodingKey {
        case id, word, example, audioURLString, timestamp, score
    }
    
    init(word: String, example: String, audioURL: URL, timestamp: Date, score: Int) {
        self.id = UUID()
        self.word = word
        self.example = example
        self.audioURL = audioURL
        self.timestamp = timestamp
        self.score = score
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        word = try container.decode(String.self, forKey: .word)
        example = try container.decode(String.self, forKey: .example)
        let urlString = try container.decode(String.self, forKey: .audioURLString)
        
        // 处理URL - 如果是绝对路径，直接使用；如果是相对路径，构建完整路径
        if urlString.hasPrefix("file://") {
            // 绝对路径
            guard let url = URL(string: urlString) else {
                throw DecodingError.dataCorruptedError(
                    forKey: .audioURLString,
                    in: container,
                    debugDescription: "Invalid URL string: \(urlString)"
                )
            }
            audioURL = url
        } else {
            // 相对路径 - 构建完整路径
            let containerURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            let recordingsDirectory = containerURL.appendingPathComponent("KumarajivaWhisperRecordings", isDirectory: true)
            audioURL = recordingsDirectory.appendingPathComponent(urlString)
        }
        
        timestamp = try container.decode(Date.self, forKey: .timestamp)
        score = try container.decode(Int.self, forKey: .score)
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(word, forKey: .word)
        try container.encode(example, forKey: .example)
        
        // 存储相对路径而非绝对路径
        let containerURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let recordingsDirectory = containerURL.appendingPathComponent("KumarajivaWhisperRecordings", isDirectory: true)
        
        if audioURL.path.hasPrefix(recordingsDirectory.path) {
            // 如果是在录音目录下的文件，只存储相对路径
            let relativePath = audioURL.lastPathComponent
            try container.encode(relativePath, forKey: .audioURLString)
        } else {
            // 否则存储完整路径
            try container.encode(audioURL.absoluteString, forKey: .audioURLString)
        }
        
        try container.encode(timestamp, forKey: .timestamp)
        try container.encode(score, forKey: .score)
    }
}