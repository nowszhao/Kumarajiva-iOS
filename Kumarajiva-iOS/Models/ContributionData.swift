import Foundation

// 学习贡献图数据模型
struct ContributionData: Codable, Identifiable {
    var id: String { date }
    let date: String
    let totalWords: Int
    let completed: Int
    let correct: Int
    
    // 便利初始化器
    init(date: String, totalWords: Int, completed: Int, correct: Int) {
        self.date = date
        self.totalWords = totalWords
        self.completed = completed
        self.correct = correct
    }
    
    // 正确率计算
    var accuracy: Double {
        guard completed > 0 else { return 0 }
        return Double(correct) / Double(completed)
    }
    
    // 贡献强度等级 (0-4)
    var contributionLevel: Int {
        // 如果没有学习计划或者没有完成任何学习，返回0
        if totalWords == 0 && completed == 0 { return 0 }
        
        // 如果有学习计划但没有完成，显示很低的活动等级
        if completed == 0 && totalWords > 0 { return 1 }
        
        // 如果有完成学习，根据完成情况和正确率计算
        if completed > 0 {
            let accuracy = self.accuracy
            let completionRate = totalWords > 0 ? Double(completed) / Double(totalWords) : 1.0
            
            // 综合考虑完成率和正确率
            let score = accuracy * 0.6 + completionRate * 0.4
            
            if score >= 0.99 { return 4 }      // 深绿色
            else if score >= 0.95 { return 3 } // 中绿色
            else if score >= 0.9 { return 2 } // 浅绿色
            else { return 1 }                 // 很浅绿色
        }
        
        return 0  // 默认返回0
    }
    
    // 格式化的日期
    var formattedDate: String {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        
        if let date = dateFormatter.date(from: date) {
            let displayFormatter = DateFormatter()
            displayFormatter.dateFormat = "MM月dd日"
            return displayFormatter.string(from: date)
        }
        return date
    }
    
    // 获取 Date 对象
    var dateObject: Date? {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        return dateFormatter.date(from: date)
    }
    
    enum CodingKeys: String, CodingKey {
        case date
        case totalWords
        case completed
        case correct
    }
}

// API 响应模型
struct ContributionResponse: Codable {
    let success: Bool
    let data: [ContributionData]
}

// 贡献图配置
struct ContributionConfig {
    static let daysToShow = 182  // 显示 182 天 (26 周 * 7 天)
    static let weeksToShow = 26
    static let daysInWeek = 7
    
    // 贡献等级对应的颜色
    static func color(for level: Int) -> String {
        switch level {
        case 0: return "contribution-level-0"  // 灰色
        case 1: return "contribution-level-1"  // 很浅绿
        case 2: return "contribution-level-2"  // 浅绿
        case 3: return "contribution-level-3"  // 中绿
        case 4: return "contribution-level-4"  // 深绿
        default: return "contribution-level-0"
        }
    }
} 
