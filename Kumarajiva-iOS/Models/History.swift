import Foundation

// Original History model for backward compatibility
struct History: Codable, Identifiable {
    var id: String { word }
    let word: String
    let definitions: [Word.Definition]
    let examples: [String]
    let lastReviewDate: Int64?
    let reviewCount: Int
    let correctCount: Int
    let pronunciation: Pronunciation?
    let memoryMethod: String?
    let mastered: Int
    let timestamp: Int64
    
    struct Pronunciation: Codable {
        let American: String
        let British: String
    }
    
    // Public memberwise initializer
    init(word: String, definitions: [Word.Definition], examples: [String], lastReviewDate: Int64?, reviewCount: Int, correctCount: Int, pronunciation: Pronunciation?, memoryMethod: String?, mastered: Int, timestamp: Int64) {
        self.word = word
        self.definitions = definitions
        self.examples = examples
        self.lastReviewDate = lastReviewDate
        self.reviewCount = reviewCount
        self.correctCount = correctCount
        self.pronunciation = pronunciation
        self.memoryMethod = memoryMethod
        self.mastered = mastered
        self.timestamp = timestamp
    }
    
    // Custom decoder to handle both string and array formats for definitions
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        
        word = try container.decode(String.self, forKey: .word)
        examples = try container.decodeIfPresent([String].self, forKey: .examples) ?? []
        lastReviewDate = try container.decodeIfPresent(Int64.self, forKey: .lastReviewDate)
        reviewCount = try container.decode(Int.self, forKey: .reviewCount)
        correctCount = try container.decode(Int.self, forKey: .correctCount)
        memoryMethod = try container.decodeIfPresent(String.self, forKey: .memoryMethod)
        mastered = try container.decode(Int.self, forKey: .mastered)
        timestamp = try container.decode(Int64.self, forKey: .timestamp)
        
        // Handle definitions field - can be either string or array
        if let definitionsArray = try? container.decode([Word.Definition].self, forKey: .definitions) {
            // If it's already an array of Definition objects, use it directly
            definitions = definitionsArray
        } else if let definitionsString = try? container.decode(String.self, forKey: .definitions) {
            // If it's a string, parse it into a single Definition
            definitions = [Word.Definition(meaning: definitionsString, pos: "")]
        } else {
            // Fallback to empty array
            definitions = []
        }
        
        // Handle pronunciation field - can be either string JSON or object
        if let pronunciationObject = try? container.decode(Pronunciation.self, forKey: .pronunciation) {
            // If it's already a Pronunciation object, use it directly
            pronunciation = pronunciationObject
        } else if let pronunciationString = try? container.decode(String.self, forKey: .pronunciation) {
            // If it's a string, try to parse it as JSON
            if let pronunciationData = pronunciationString.data(using: .utf8),
               let pronunciationObject = try? JSONDecoder().decode(Pronunciation.self, from: pronunciationData) {
                pronunciation = pronunciationObject
            } else {
                // Fallback to nil pronunciation
                pronunciation = nil
            }
        } else {
            // Fallback to nil pronunciation
            pronunciation = nil
        }
    }
    
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
}

// Response wrapper for review history API
struct ReviewHistoryResponse: Codable {
    let success: Bool
    let data: ReviewHistoryData
}

struct ReviewHistoryData: Codable {
    let total: Int
    let data: [ReviewHistoryItem]
    let limit: Int
    let offset: Int
}

// ReviewHistoryItem model that matches the actual backend response
struct ReviewHistoryItem: Codable, Identifiable {
    var id: String { word + String(timestamp) } // Create unique ID from word and timestamp
    let word: String
    let definitions: [Word.Definition]
    let memoryMethod: String?
    let pronunciation: Pronunciation?
    let mastered: Int
    let timestamp: Int64
    let userId: Int
    let lastReviewDate: Int64
    let reviewCount: Int
    let correctCount: Int
    let examples: [String]
    
    struct Pronunciation: Codable {
        let American: String
        let British: String
    }
    
    // Custom decoder to handle both string and array formats for definitions and pronunciation
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        
        word = try container.decode(String.self, forKey: .word)
        memoryMethod = try container.decodeIfPresent(String.self, forKey: .memoryMethod)
        mastered = try container.decode(Int.self, forKey: .mastered)
        timestamp = try container.decode(Int64.self, forKey: .timestamp)
        userId = try container.decode(Int.self, forKey: .userId)
        lastReviewDate = try container.decode(Int64.self, forKey: .lastReviewDate)
        reviewCount = try container.decode(Int.self, forKey: .reviewCount)
        correctCount = try container.decode(Int.self, forKey: .correctCount)
        examples = try container.decodeIfPresent([String].self, forKey: .examples) ?? []
        
        // Handle definitions field - can be either string or array
        if let definitionsArray = try? container.decode([Word.Definition].self, forKey: .definitions) {
            // If it's already an array of Definition objects, use it directly
            definitions = definitionsArray
        } else if let definitionsString = try? container.decode(String.self, forKey: .definitions) {
            // If it's a string, parse it into a single Definition
            definitions = [Word.Definition(meaning: definitionsString, pos: "")]
        } else {
            // Fallback to empty array
            definitions = []
        }
        
        // Handle pronunciation field - can be either string JSON or object
        if let pronunciationObject = try? container.decode(Pronunciation.self, forKey: .pronunciation) {
            // If it's already a Pronunciation object, use it directly
            pronunciation = pronunciationObject
        } else if let pronunciationString = try? container.decode(String.self, forKey: .pronunciation) {
            // If it's a string, try to parse it as JSON
            if let pronunciationData = pronunciationString.data(using: .utf8),
               let pronunciationObject = try? JSONDecoder().decode(Pronunciation.self, from: pronunciationData) {
                pronunciation = pronunciationObject
            } else {
                // Fallback to nil pronunciation
                pronunciation = nil
            }
        } else {
            // Fallback to nil pronunciation
            pronunciation = nil
        }
    }
    
    enum CodingKeys: String, CodingKey {
        case word
        case definitions
        case memoryMethod = "memory_method"
        case pronunciation
        case mastered
        case timestamp
        case userId = "user_id"
        case lastReviewDate = "last_review_date"
        case reviewCount = "review_count"
        case correctCount = "correct_count"
        case examples
    }
    
    // Computed properties for easier use in UI
    var isCorrect: Bool {
        return correctCount > 0
    }
    
    var parsedPronunciation: Word.Pronunciation? {
        guard let pronunciation = pronunciation else { return nil }
        return Word.Pronunciation(American: pronunciation.American, British: pronunciation.British)
    }
    
    var reviewDateFormatted: Date {
        return Date(timeIntervalSince1970: Double(lastReviewDate) / 1000.0)
    }
    
    var timestampFormatted: Date {
        return Date(timeIntervalSince1970: Double(timestamp) / 1000.0)
    }
} 
