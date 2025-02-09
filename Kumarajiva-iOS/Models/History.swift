import Foundation

struct History: Codable, Identifiable {
    var id: String { word }
    let word: String
    let definitions: [Word.Definition]
    let examples: [String]
    let lastReviewDate: Int64?
    let reviewCount: Int
    let correctCount: Int
    let pronunciation: String?
    let memoryMethod: String?
    let mastered: Int
    let timestamp: Int64
    
    enum CodingKeys: String, CodingKey {
        case word
        case definitions
        case examples
        case lastReviewDate = "last_review_date"
        case reviewCount = "review_count"
        case correctCount = "correct_count"
        case pronunciation
        case memoryMethod = "memory_method"
        case mastered
        case timestamp
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        word = try container.decode(String.self, forKey: .word)
        definitions = try container.decode([Word.Definition].self, forKey: .definitions)
        examples = try container.decode([String].self, forKey: .examples)
        lastReviewDate = try container.decodeIfPresent(Int64.self, forKey: .lastReviewDate)
        memoryMethod = try container.decodeIfPresent(String.self, forKey: .memoryMethod)
        mastered = try container.decode(Int.self, forKey: .mastered)
        timestamp = try container.decode(Int64.self, forKey: .timestamp)
        pronunciation = try container.decodeIfPresent(String.self, forKey: .pronunciation)
        
        // 处理可能缺失的字段
        reviewCount = (try? container.decode(Int.self, forKey: .reviewCount)) ?? 0
        correctCount = (try? container.decode(Int.self, forKey: .correctCount)) ?? 0
    }
} 