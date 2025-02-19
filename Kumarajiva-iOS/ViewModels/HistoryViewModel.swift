import Foundation
import SwiftUI

@MainActor
class HistoryViewModel: ObservableObject {
    @Published var histories: [History] = []
    @Published var isLoading = false
    @Published var error: String?
    @Published var total: Int = 0
    
    private var currentOffset = 0
    private let pageSize = 100
    
    func loadHistory(filter: HistoryFilter? = nil, wordType: WordTypeFilter? = nil) async {
        isLoading = true
        do {
            // 构建请求参数
            var params: [String: Any] = [
                "limit": pageSize,
                "offset": currentOffset
            ]
            
            // 添加时间过滤
            if let filter = filter {
                let (startDate, endDate) = filter.dateRange
                params["startDate"] = Int64(startDate.timeIntervalSince1970 * 1000)
                params["endDate"] = Int64(endDate.timeIntervalSince1970 * 1000)
            }
            
            // 添加单词类型过滤
            if let wordType = wordType, wordType != .all {
                params["wordType"] = wordType.apiValue
            }
            
            let response = try await APIService.shared.getHistory(params: params)
            histories = response.data
            total = response.total
            
        } catch {
            self.error = error.localizedDescription
        }
        isLoading = false
    }
    
    func loadMore() async {
        guard !isLoading, histories.count < total else { return }
        
        currentOffset += pageSize
        await loadHistory()
    }
    
    func reset() {
        currentOffset = 0
        histories = []
        total = 0
    }
} 
