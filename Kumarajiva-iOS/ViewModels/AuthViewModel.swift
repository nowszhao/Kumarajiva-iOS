import Foundation
import SwiftUI

@MainActor
class AuthViewModel: ObservableObject {
    @Published var showingErrorAlert = false
    @Published var errorMessage = ""
    
    private let authService = AuthService.shared
    
    func handleAuthError(_ error: Error) {
        if let authError = error as? AuthError {
            errorMessage = authError.localizedDescription
        } else if let apiError = error as? APIError {
            switch apiError {
            case .unauthorized:
                errorMessage = "登录已过期，请重新登录"
                authService.logout()
            default:
                errorMessage = "网络错误，请检查网络连接"
            }
        } else {
            errorMessage = error.localizedDescription
        }
        showingErrorAlert = true
    }
    
    func retryLogin() {
        authService.startGitHubOAuth()
    }
} 