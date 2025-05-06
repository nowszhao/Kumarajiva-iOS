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
        guard let url = URL(string: urlString) else {
            throw DecodingError.dataCorruptedError(
                forKey: .audioURLString,
                in: container,
                debugDescription: "Invalid URL string"
            )
        }
        audioURL = url
        timestamp = try container.decode(Date.self, forKey: .timestamp)
        score = try container.decode(Int.self, forKey: .score)
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(word, forKey: .word)
        try container.encode(example, forKey: .example)
        try container.encode(audioURL.absoluteString, forKey: .audioURLString)
        try container.encode(timestamp, forKey: .timestamp)
        try container.encode(score, forKey: .score)
    }
} 