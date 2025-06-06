import Foundation

// 学习记录模型
struct StudyRecord: Codable, Identifiable {
    var id: String { "\(reviewDate)_\(reviewResult)" }
    let reviewDate: String
    let reviewResult: Int // 1 表示正确，0 表示错误
    
    // 转换为友好的日期格式
    var formattedDate: String {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        
        if let date = dateFormatter.date(from: reviewDate) {
            let displayFormatter = DateFormatter()
            displayFormatter.dateFormat = "yyyy-MM-dd"
            return displayFormatter.string(from: date)
        }
        return reviewDate
    }
    
    // 是否正确
    var isCorrect: Bool {
        return reviewResult == 1
    }
    
    // 获取 Date 对象用于间隔计算
    var date: Date? {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return dateFormatter.date(from: reviewDate)
    }
    
    // 计算与上一次学习的间隔时间
    func intervalSince(_ previousRecord: StudyRecord?) -> String? {
        guard let previousRecord = previousRecord,
              let currentDate = self.date,
              let previousDate = previousRecord.date else {
            return nil
        }
        
        let interval = currentDate.timeIntervalSince(previousDate)
        return formatTimeInterval(interval)
    }
    
    // 格式化时间间隔
    private func formatTimeInterval(_ interval: TimeInterval) -> String {
        let totalMinutes = Int(interval / 60)
        let totalHours = totalMinutes / 60
        let totalDays = totalHours / 24
        
        if totalDays > 0 {
            let remainingHours = totalHours % 24
            if remainingHours > 0 {
                return "\(totalDays)天\(remainingHours)小时"
            } else {
                return "\(totalDays)天"
            }
        } else if totalHours > 0 {
            let remainingMinutes = totalMinutes % 60
            if remainingMinutes > 0 {
                return "\(totalHours)小时\(remainingMinutes)分钟"
            } else {
                return "\(totalHours)小时"
            }
        } else if totalMinutes > 0 {
            return "\(totalMinutes)分钟"
        } else {
            return "刚刚"
        }
    }
    
    // enum CodingKeys: String, CodingKey {
    //     case reviewDate = "review_date"
    //     case reviewResult = "review_result"
    // }
}

// API 响应模型
struct StudyRecordResponse: Codable {
    let success: Bool
    let data: [StudyRecord]
}

// 扩展的学习记录模型，包含间隔时间信息
struct StudyRecordWithInterval {
    let record: StudyRecord
    let intervalText: String?
    
    var id: String { record.id }
    var reviewDate: String { record.reviewDate }
    var reviewResult: Int { record.reviewResult }
    var formattedDate: String { record.formattedDate }
    var isCorrect: Bool { record.isCorrect }
} 
