import Foundation

struct Quiz: Codable {
    let word: String
    let phonetic: String?
    let audio: String?
    let definitions: [Word.Definition]
    let examples: [String]
    let memoryMethod: String?
    let correctAnswer: String?
    let options: [Option]
    let isNew: Bool?
    
    struct Option: Codable {
        let definition: String
        let pos: String
        
        var toDefinition: Word.Definition {
            // Try to parse definition as JSON first
            if let definitionData = definition.data(using: .utf8) {
                let decoder = JSONDecoder()
                decoder.keyDecodingStrategy = .convertFromSnakeCase
                if let definitionsArray = try? decoder.decode([Word.Definition].self, from: definitionData),
                   let firstDefinition = definitionsArray.first {
                    return firstDefinition
                }
                // If JSON parsing fails, use the string as meaning
                return Word.Definition(meaning: definition, pos: pos)
            } else {
                return Word.Definition(meaning: definition, pos: pos)
            }
        }
    }
    
    // Custom decoder to handle string format for definitions
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        
        word = try container.decode(String.self, forKey: .word)
        phonetic = try container.decodeIfPresent(String.self, forKey: .phonetic)
        audio = try container.decodeIfPresent(String.self, forKey: .audio)
        examples = try container.decodeIfPresent([String].self, forKey: .examples) ?? []
        memoryMethod = try container.decodeIfPresent(String.self, forKey: .memoryMethod)
        correctAnswer = try container.decodeIfPresent(String.self, forKey: .correctAnswer)
        options = try container.decodeIfPresent([Option].self, forKey: .options) ?? []
        isNew = try container.decodeIfPresent(Bool.self, forKey: .isNew)
        
        // Handle definitions field - can be either string or array
        if let definitionsArray = try? container.decode([Word.Definition].self, forKey: .definitions) {
            // If it's already an array of Definition objects, use it directly
            definitions = definitionsArray
        } else if let definitionsString = try? container.decode(String.self, forKey: .definitions) {
            // If it's a string, try to parse it as JSON first
            if let definitionsData = definitionsString.data(using: .utf8) {
                let decoder = JSONDecoder()
                decoder.keyDecodingStrategy = .convertFromSnakeCase
                if let definitionsArray = try? decoder.decode([Word.Definition].self, from: definitionsData) {
                    definitions = definitionsArray
                } else {
                    // If JSON parsing fails, treat as a single definition
                    definitions = [Word.Definition(meaning: definitionsString, pos: "")]
                }
            } else {
                definitions = [Word.Definition(meaning: definitionsString, pos: "")]
            }
        } else {
            // Fallback to empty array
            definitions = []
        }
    }
    
    enum CodingKeys: String, CodingKey {
        case word
        case phonetic
        case audio
        case definitions
        case examples
        case memoryMethod = "memory_method"
        case correctAnswer = "correct_answer"
        case options
        case isNew
    }
} 
