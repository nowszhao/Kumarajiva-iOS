import Foundation

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
} 
