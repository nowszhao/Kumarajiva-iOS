import Foundation
import SwiftUI

enum AuthError: Error, LocalizedError {
    case invalidURL
    case invalidResponse
    case networkError(Error)
    case decodingError(Error)
    case tokenExpired
    case noRefreshToken
    case authenticationFailed
    
    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "无效的URL"
        case .invalidResponse:
            return "无效的响应"
        case .networkError(let error):
            return "网络错误: \(error.localizedDescription)"
        case .decodingError(let error):
            return "数据解析错误: \(error.localizedDescription)"
        case .tokenExpired:
            return "登录已过期，请重新登录"
        case .noRefreshToken:
            return "无刷新令牌"
        case .authenticationFailed:
            return "认证失败"
        }
    }
}

@MainActor
class AuthService: ObservableObject {
    static let shared = AuthService()
    
    @Published var isAuthenticated = false
    @Published var currentUser: User?
    @Published var isLoading = false
    @Published var errorMessage: String?
    
     private let baseURL = "http://47.121.117.100:3000/api"
//    private let baseURL = "http://127.0.0.1:3000/api"
    private static let keychainService = "com.kumarajiva.ios"
    
    private var accessToken: String? {
        get { KeychainHelper.get(key: "access_token", service: AuthService.keychainService) }
        set { 
            if let token = newValue {
                KeychainHelper.save(key: "access_token", value: token, service: AuthService.keychainService)
            } else {
                KeychainHelper.delete(key: "access_token", service: AuthService.keychainService)
            }
        }
    }
    
    private var refreshToken: String? {
        get { KeychainHelper.get(key: "refresh_token", service: AuthService.keychainService) }
        set {
            if let token = newValue {
                KeychainHelper.save(key: "refresh_token", value: token, service: AuthService.keychainService)
            } else {
                KeychainHelper.delete(key: "refresh_token", service: AuthService.keychainService)
            }
        }
    }
    
    private init() {
        checkAuthenticationStatus()
    }
    
    // MARK: - Public Methods
    
    /// 启动GitHub OAuth登录流程
    func startGitHubOAuth() {
        print("🔐 [AuthService] 开始GitHub OAuth登录流程")
        guard let url = URL(string: "\(baseURL)/auth/github?client_type=ios") else {
            print("❌ [AuthService] 无效的登录URL: \(baseURL)/auth/github?client_type=ios")
            errorMessage = "无效的登录URL"
            return
        }
        
        print("🔗 [AuthService] OAuth URL: \(url)")
        isLoading = true
        errorMessage = nil
        
        DispatchQueue.main.async {
            UIApplication.shared.open(url)
        }
    }
    
    /// 处理OAuth回调
    func handleOAuthCallback(url: URL) -> Bool {
        print("📱 [AuthService] 收到OAuth回调: \(url)")
        guard url.scheme == "kumarajiva-ios" else { 
            print("❌ [AuthService] URL scheme不匹配: \(url.scheme ?? "nil"), 期望: kumarajiva-ios")
            return false 
        }
        
        if url.host == "oauth-callback" {
            print("✅ [AuthService] OAuth回调成功")
            let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
            
            let accessToken = components?.queryItems?.first(where: { $0.name == "access_token" })?.value
            let refreshToken = components?.queryItems?.first(where: { $0.name == "refresh_token" })?.value
            
            print("🔑 [AuthService] Access Token: \(accessToken != nil ? "已获取(\(accessToken!.prefix(10))...)" : "未获取")")
            print("🔄 [AuthService] Refresh Token: \(refreshToken != nil ? "已获取(\(refreshToken!.prefix(10))...)" : "未获取")")
            
            if let accessToken = accessToken, let refreshToken = refreshToken {
                self.accessToken = accessToken
                self.refreshToken = refreshToken
                
                print("💾 [AuthService] Token已保存到Keychain")
                
                Task {
                    await fetchUserProfile()
                }
                
                return true
            } else {
                print("❌ [AuthService] Token获取失败")
                errorMessage = "Token获取失败"
                isLoading = false
            }
        } else if url.host == "oauth-error" {
            let error = URLComponents(url: url, resolvingAgainstBaseURL: false)?
                .queryItems?.first(where: { $0.name == "error" })?.value ?? "未知错误"
            
            print("❌ [AuthService] OAuth错误: \(error)")
            
            DispatchQueue.main.async {
                self.errorMessage = "登录失败: \(error)"
                self.isLoading = false
            }
            
            return true
        }
        
        print("❌ [AuthService] 未知的OAuth回调")
        return false
    }
    
    /// 登出
    func logout() {
        accessToken = nil
        refreshToken = nil
        currentUser = nil
        isAuthenticated = false
        errorMessage = nil
    }
    
    /// 检查认证状态
    func checkAuthenticationStatus() {
        print("🔍 [AuthService] 检查认证状态")
        guard accessToken != nil else {
            print("❌ [AuthService] 没有访问令牌，设置为未认证")
            isAuthenticated = false
            return
        }
        
        print("✅ [AuthService] 发现访问令牌，开始验证")
        Task {
            await fetchUserProfile()
        }
    }
    
    /// 获取认证头
    nonisolated func getAuthHeaders() -> [String: String] {
        guard let token = KeychainHelper.get(key: "access_token", service: AuthService.keychainService) else { 
            return [:] 
        }
        return ["Authorization": "Bearer \(token)"]
    }
    
    // MARK: - Private Methods
    
    /// 获取用户资料
    private func fetchUserProfile() async {
        print("👤 [AuthService] 开始获取用户资料")
        guard let token = accessToken else {
            print("❌ [AuthService] 没有访问令牌")
            await MainActor.run {
                isAuthenticated = false
                isLoading = false
            }
            return
        }
        
        print("🔑 [AuthService] 使用Token: \(token.prefix(10))...")
        
        do {
            let profileURL = "\(baseURL)/auth/profile"
            print("🌐 [AuthService] 请求URL: \(profileURL)")
            
            let url = URL(string: profileURL)!
            var request = URLRequest(url: url)
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            
            print("📤 [AuthService] 发送请求...")
            let (data, response) = try await URLSession.shared.data(for: request)
            
            print("📥 [AuthService] 收到响应")
            
            guard let httpResponse = response as? HTTPURLResponse else {
                print("❌ [AuthService] 无效的HTTP响应")
                throw AuthError.invalidResponse
            }
            
            print("📊 [AuthService] HTTP状态码: \(httpResponse.statusCode)")
            
            if let responseString = String(data: data, encoding: .utf8) {
                print("📦 [AuthService] 响应数据: \(responseString)")
            } else {
                print("❌ [AuthService] 无法解析响应数据为字符串")
            }
            
            if httpResponse.statusCode == 401 {
                print("🔄 [AuthService] Token过期，尝试刷新")
                // Token过期，尝试刷新
                try await refreshAccessToken()
                // 递归调用重试
                await fetchUserProfile()
                return
            }
            
            guard (200...299).contains(httpResponse.statusCode) else {
                print("❌ [AuthService] HTTP错误状态码: \(httpResponse.statusCode)")
                throw AuthError.invalidResponse
            }
            
            let decoder = JSONDecoder()
            decoder.keyDecodingStrategy = .convertFromSnakeCase
            
            print("🔍 [AuthService] 开始解析JSON数据")
            let profileResponse = try decoder.decode(ProfileResponse.self, from: data)
            
            print("✅ [AuthService] JSON解析成功")
            print("👤 [AuthService] 用户信息: \(profileResponse.data.user.username)")
            print("📊 [AuthService] 用户统计: 总词汇\(profileResponse.data.stats.totalVocabularies), 已掌握\(profileResponse.data.stats.masteredVocabularies)")
            
            await MainActor.run {
                print("✅ [AuthService] 用户认证成功: \(profileResponse.data.user.username)")
                self.currentUser = profileResponse.data.user
                self.isAuthenticated = true
                self.isLoading = false
                self.errorMessage = nil
            }
            
        } catch {
            print("❌ [AuthService] 获取用户资料失败: \(error)")
            if let decodingError = error as? DecodingError {
                print("🔍 [AuthService] 解码错误详情: \(decodingError)")
            }
            
            await MainActor.run {
                self.isAuthenticated = false
                self.isLoading = false
                if case AuthError.tokenExpired = error {
                    self.errorMessage = error.localizedDescription
                    self.logout()
                } else {
                    self.errorMessage = "获取用户信息失败: \(error.localizedDescription)"
                }
            }
        }
    }
    
    /// 刷新访问令牌
    private func refreshAccessToken() async throws {
        print("🔄 [AuthService] 开始刷新访问令牌")
        guard let refreshToken = refreshToken else {
            print("❌ [AuthService] 没有刷新令牌")
            throw AuthError.noRefreshToken
        }
        
        print("🔑 [AuthService] 使用Refresh Token: \(refreshToken.prefix(10))...")
        
        let refreshURL = "\(baseURL)/auth/refresh"
        print("🌐 [AuthService] 刷新URL: \(refreshURL)")
        
        let url = URL(string: refreshURL)!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("ios", forHTTPHeaderField: "X-Client-Type")
        
        let body = ["refresh_token": refreshToken]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        
        print("📤 [AuthService] 发送刷新请求...")
        let (data, response) = try await URLSession.shared.data(for: request)
        
        print("📥 [AuthService] 收到刷新响应")
        
        if let responseString = String(data: data, encoding: .utf8) {
            print("📦 [AuthService] 刷新响应数据: \(responseString)")
        }
        
        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            print("❌ [AuthService] 刷新令牌失败，状态码: \((response as? HTTPURLResponse)?.statusCode ?? -1)")
            throw AuthError.tokenExpired
        }
        
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let refreshResponse = try decoder.decode(RefreshTokenResponse.self, from: data)
        
        print("✅ [AuthService] 令牌刷新成功")
        print("🔑 [AuthService] 新Access Token: \(refreshResponse.data.accessToken.prefix(10))...")
        print("🔄 [AuthService] 新Refresh Token: \(refreshResponse.data.refreshToken.prefix(10))...")
        
        self.accessToken = refreshResponse.data.accessToken
        self.refreshToken = refreshResponse.data.refreshToken
    }
}

// MARK: - Keychain Helper
private class KeychainHelper {
    static func save(key: String, value: String, service: String) {
        let data = value.data(using: .utf8)!
        
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecValueData as String: data
        ]
        
        SecItemDelete(query as CFDictionary)
        SecItemAdd(query as CFDictionary, nil)
    }
    
    static func get(key: String, service: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        
        guard status == errSecSuccess,
              let data = result as? Data,
              let string = String(data: data, encoding: .utf8) else {
            return nil
        }
        
        return string
    }
    
    static func delete(key: String, service: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key
        ]
        
        SecItemDelete(query as CFDictionary)
    }
} 
