import Foundation

struct Word: Codable, Identifiable {
    var id: String { word }
    let word: String
    let definitions: [Definition]
    let memoryMethod: String?
    let pronunciation: Pronunciation
    let mastered: Int
    let timestamp: Int64
    let isNew: Bool
    
    struct Definition: Codable {
        let meaning: String
        let pos: String
    }
    
    struct Pronunciation: Codable {
        let American: String?
        let British: String?
    }
    
    enum CodingKeys: String, CodingKey {
        case word
        case definitions
        case memoryMethod = "memory_method"
        case pronunciation
        case mastered
        case timestamp
        case isNew
    }
    
    // Custom decoder to handle both string and array formats for definitions
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        
        word = try container.decode(String.self, forKey: .word)
        memoryMethod = try container.decodeIfPresent(String.self, forKey: .memoryMethod)
        mastered = try container.decode(Int.self, forKey: .mastered)
        timestamp = try container.decode(Int64.self, forKey: .timestamp)
        isNew = try container.decodeIfPresent(Bool.self, forKey: .isNew) ?? false
        
        // Handle definitions field - can be either string or array
        if let definitionsArray = try? container.decode([Definition].self, forKey: .definitions) {
            // If it's already an array of Definition objects, use it directly
            definitions = definitionsArray
        } else if let definitionsString = try? container.decode(String.self, forKey: .definitions) {
            // If it's a string, parse it into a single Definition
            // For now, we'll treat the entire string as the meaning with unknown pos
            definitions = [Definition(meaning: definitionsString, pos: "")]
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
                // Fallback to empty pronunciation
                pronunciation = Pronunciation(American: nil, British: nil)
            }
        } else {
            // Fallback to empty pronunciation
            pronunciation = Pronunciation(American: nil, British: nil)
        }
    }
    
    // Custom encoder to maintain compatibility
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        
        try container.encode(word, forKey: .word)
        try container.encode(definitions, forKey: .definitions)
        try container.encodeIfPresent(memoryMethod, forKey: .memoryMethod)
        try container.encode(pronunciation, forKey: .pronunciation)
        try container.encode(mastered, forKey: .mastered)
        try container.encode(timestamp, forKey: .timestamp)
        try container.encode(isNew, forKey: .isNew)
    }
} 
