import Foundation

enum WordTypeFilter: String, CaseIterable, Identifiable {
    case all
    case new
    case mastered
    case reviewing
    case incorrect
    
    var id: String { rawValue }
    
    var title: String {
        switch self {
        case .all: return "全部"
        case .new: return "新词"
        case .mastered: return "已掌握"
        case .reviewing: return "复习中"
        case .incorrect: return "错词"
        }
    }
    
    var apiValue: String {
        switch self {
        case .all: return "all"
        case .new: return "new"
        case .mastered: return "mastered"
        case .reviewing: return "reviewing"
        case .incorrect: return "wrong"
        }
    }
    
    func matches(_ history: History) -> Bool {
        switch self {
        case .all:
            return true
        case .new:
            return history.reviewCount == 1
        case .mastered:
            return history.mastered == 1
        case .reviewing:
            return history.reviewCount > 1
        case .incorrect:
            return history.correctCount < history.reviewCount
        }
    }
} 
