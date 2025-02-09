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
    
    struct Option: Codable {
        let definition: String
        let pos: String
        
        var toDefinition: Word.Definition {
            Word.Definition(meaning: definition, pos: pos)
        }
    }

} 
