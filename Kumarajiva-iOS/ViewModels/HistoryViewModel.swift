import Foundation
import SwiftUI

@MainActor
class HistoryViewModel: ObservableObject {
    @Published var histories: [ReviewHistoryItem] = []
    @Published var isLoading = false
    @Published var error: String?
    @Published var total: Int = 0
    @Published var hasMoreData = true
    
    private var currentOffset = 0
    private let pageSize = 100
    private let authService = AuthService.shared
    
    func loadHistory(filter: HistoryFilter? = nil, wordType: WordTypeFilter? = nil, reset: Bool = false) async {
        if reset {
            currentOffset = 0
            histories = []
            total = 0
            hasMoreData = true
        }
        
        guard !isLoading && hasMoreData else { return }
        
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
            
            if reset {
                histories = response.data.data
            } else {
                histories.append(contentsOf: response.data.data)
            }
            
            // Update total count and pagination info from response
            total = response.data.total
            currentOffset = response.data.offset + response.data.data.count
            
            // Determine if there's more data
            hasMoreData = response.data.data.count == response.data.limit && currentOffset < total
            
        } catch {
            handleError(error)
        }
        isLoading = false
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
    
    func reset() {
        currentOffset = 0
        histories = []
        total = 0
        hasMoreData = true
    }
} 
