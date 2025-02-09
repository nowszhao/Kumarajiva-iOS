import Foundation

enum HistoryFilter: CaseIterable {
    case today
    case yesterday
    case lastWeek
    case lastMonth
    
    var title: String {
        switch self {
        case .today: return "今天"
        case .yesterday: return "昨天"
        case .lastWeek: return "最近7天"
        case .lastMonth: return "最近30天"
        }
    }
    
    var dateRange: (Date, Date) {
        let now = Date()
        let calendar = Calendar.current
        
        switch self {
        case .today:
            let startOfDay = calendar.startOfDay(for: now)
            return (startOfDay, now)
            
        case .yesterday:
            let startOfYesterday = calendar.date(byAdding: .day, value: -1, to: calendar.startOfDay(for: now))!
            let endOfYesterday = calendar.date(byAdding: .day, value: 1, to: startOfYesterday)!
            return (startOfYesterday, endOfYesterday)
            
        case .lastWeek:
            let startOfWeek = calendar.date(byAdding: .day, value: -7, to: calendar.startOfDay(for: now))!
            return (startOfWeek, now)
            
        case .lastMonth:
            let startOfMonth = calendar.date(byAdding: .day, value: -30, to: calendar.startOfDay(for: now))!
            return (startOfMonth, now)
        }
    }
} 