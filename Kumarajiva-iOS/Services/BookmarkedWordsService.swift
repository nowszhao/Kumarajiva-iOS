import Foundation
import SwiftUI

class BookmarkedWordsService: ObservableObject {
    static let shared = BookmarkedWordsService()
    
    @AppStorage("bookmarkedWords") private var bookmarkedWordsData: Data = Data()
    @Published var bookmarkedWords: Set<String> = []
    
    private init() {
        loadBookmarkedWords()
    }
    
    private func loadBookmarkedWords() {
        if let decoded = try? JSONDecoder().decode(Set<String>.self, from: bookmarkedWordsData) {
            bookmarkedWords = decoded
        }
    }
    
    private func saveBookmarkedWords() {
        if let encoded = try? JSONEncoder().encode(bookmarkedWords) {
            bookmarkedWordsData = encoded
        }
    }
    
    /// 切换单词的标注状态
    func toggleBookmark(for word: String) {
        if bookmarkedWords.contains(word) {
            bookmarkedWords.remove(word)
        } else {
            bookmarkedWords.insert(word)
        }
        saveBookmarkedWords()
    }
    
    /// 检查单词是否已标注
    func isBookmarked(_ word: String) -> Bool {
        return bookmarkedWords.contains(word)
    }
    
    /// 添加标注
    func addBookmark(for word: String) {
        bookmarkedWords.insert(word)
        saveBookmarkedWords()
    }
    
    /// 移除标注
    func removeBookmark(for word: String) {
        bookmarkedWords.remove(word)
        saveBookmarkedWords()
    }
    
    /// 获取所有标注的单词
    func getAllBookmarkedWords() -> Set<String> {
        return bookmarkedWords
    }
    
    /// 清除所有标注
    func clearAllBookmarks() {
        bookmarkedWords.removeAll()
        saveBookmarkedWords()
    }
    
    /// 获取标注单词数量
    var bookmarkedCount: Int {
        return bookmarkedWords.count
    }
} 