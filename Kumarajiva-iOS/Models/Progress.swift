import Foundation

struct Progress: Codable {
    let id: Int
    let date: String
    let currentWordIndex: Int
    let totalWords: Int
    let completed: Int
    let correct: Int
} 