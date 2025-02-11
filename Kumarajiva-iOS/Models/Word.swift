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
} 
