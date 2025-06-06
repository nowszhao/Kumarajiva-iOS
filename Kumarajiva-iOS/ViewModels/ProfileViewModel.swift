import Foundation

@MainActor
class ProfileViewModel: ObservableObject {
    @Published var stats: Stats?
    @Published var isLoading = false
    @Published var error: String?
    
    // 贡献图相关属性
    @Published var contributionData: [ContributionData] = []
    @Published var isLoadingContribution = false
    @Published var contributionError: String?
    
    private let authService = AuthService.shared
    
    func loadStats() async {
        isLoading = true
        do {
            stats = try await APIService.shared.getStats()
        } catch {
            handleError(error)
        }
        isLoading = false
    }
    
    func loadContributionData() async {
        isLoadingContribution = true
        contributionError = nil
        
        do {
            let data = try await APIService.shared.getContributionData()
            contributionData = data
        } catch {
            handleContributionError(error)
        }
        
        isLoadingContribution = false
    }
    
    // 生成最近180天的完整贡献图数据（包含空数据）
    func getContributionGrid() -> [[ContributionData?]] {
        let calendar = Calendar.current
        let today = Date()
        
        // 计算今天是星期几（1=周日，2=周一...7=周六）
        let todayWeekday = calendar.component(.weekday, from: today)
        let daysFromMonday = (todayWeekday == 1) ? 6 : todayWeekday - 2 // 转换为从周一开始计算
        
        // 计算本周的周一
        let thisWeekMonday = calendar.date(byAdding: .day, value: -daysFromMonday, to: today)!
        
        // 从本周周一往前推25周，得到起始周的周一（总共26周）
        let startDate = calendar.date(byAdding: .weekOfYear, value: -25, to: thisWeekMonday)!
        
        // 创建日期到数据的映射
        var dataMap: [String: ContributionData] = [:]
        for item in contributionData {
            dataMap[item.date] = item
        }
        
        // 生成26周的网格数据
        var weeks: [[ContributionData?]] = []
        var currentDate = startDate
        
        for _ in 0..<ContributionConfig.weeksToShow {
            var week: [ContributionData?] = []
            
            for _ in 0..<ContributionConfig.daysInWeek {
                let dateString = formatDateForAPI(currentDate)
                let contributionItem = dataMap[dateString]
                
                // 如果没有数据，创建一个空的贡献数据
                let item = contributionItem ?? ContributionData(
                    date: dateString,
                    totalWords: 0,
                    completed: 0,
                    correct: 0
                )
                
                week.append(item)
                currentDate = calendar.date(byAdding: .day, value: 1, to: currentDate)!
            }
            
            weeks.append(week)
        }
        
        let endDate = calendar.date(byAdding: .day, value: -1, to: currentDate)!
        print("Date range: \(formatDateForAPI(startDate)) to \(formatDateForAPI(endDate))")
        print("Today: \(formatDateForAPI(today))")
        print("This week Monday: \(formatDateForAPI(thisWeekMonday))")
        print("Days from Monday to today: \(daysFromMonday)")
        print("Generated weeks count: \(weeks.count)")
        
        return weeks
    }
    
    private func formatDateForAPI(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }
    
    private func handleError(_ error: Error) {
        if let apiError = error as? APIError, case .unauthorized = apiError {
            // 认证失败，自动登出
            authService.logout()
            self.error = "登录已过期，请重新登录"
        } else {
            self.error = error.localizedDescription
        }
    }
    
    private func handleContributionError(_ error: Error) {
        if let apiError = error as? APIError, case .unauthorized = apiError {
            // 认证失败，自动登出
            authService.logout()
            contributionError = "登录已过期，请重新登录"
        } else {
            contributionError = error.localizedDescription
        }
    }
} 
