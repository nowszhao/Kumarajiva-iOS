import Foundation

@MainActor
class ProfileViewModel: ObservableObject {
    @Published var stats: Stats?
    @Published var isLoading = false
    @Published var error: String?
    
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
    
    private func handleError(_ error: Error) {
        if let apiError = error as? APIError, case .unauthorized = apiError {
            // 认证失败，自动登出
            authService.logout()
            self.error = "登录已过期，请重新登录"
        } else {
            self.error = error.localizedDescription
        }
    }
} 