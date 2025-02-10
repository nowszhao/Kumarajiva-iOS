import Foundation

@MainActor
class HistoryViewModel: ObservableObject {
    @Published var histories: [History] = []
    @Published var isLoading = false
    @Published var error: String?
    
    func loadHistory(filter: HistoryFilter) async {
        isLoading = true
        do {
            let allHistories = try await APIService.shared.getHistory()
            let (startDate, endDate) = filter.dateRange
            
            histories = allHistories.filter { history in
                let historyDate = Date(timeIntervalSince1970: TimeInterval(history.lastReviewDate! / 1000))
                return historyDate >= startDate && historyDate <= endDate
            }
            
            // 按时间倒序排序
            histories.sort { $0.lastReviewDate! > $1.lastReviewDate! }
        } catch {
            self.error = error.localizedDescription
        }
        isLoading = false
    }
} 
