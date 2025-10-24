import SwiftUI
import AuthenticationServices

struct AddAliyunDriveView: View {
    @StateObject private var service = AliyunDriveService.shared
    @Environment(\.dismiss) private var dismiss
    
    @State private var isLoading = false
    @State private var showingError = false
    @State private var errorMessage = ""
    @State private var savedState: String?
    @State private var savedCodeVerifier: String?
    
    // ASWebAuthenticationSession 的上下文提供者
    private let authContextProvider = AuthenticationSessionContextProvider()
    
    var body: some View {
        NavigationView {
            VStack(spacing: 32) {
                Spacer()
                
                // 标题和说明
                VStack(spacing: 16) {
                    Image(systemName: "cloud.fill")
                        .font(.system(size: 80))
                        .foregroundColor(.blue)
                    
                    Text("添加阿里云盘")
                        .font(.title)
                        .fontWeight(.bold)
                    
                    VStack(spacing: 8) {
                        Text("点击下方按钮授权登录")
                            .font(.body)
                            .foregroundColor(.secondary)
                        
                        Text("将跳转到阿里云盘进行授权")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .multilineTextAlignment(.center)
                }
                
                Spacer()
                
                // 操作按钮
                VStack(spacing: 16) {
                    Button {
                        startOAuthLogin()
                    } label: {
                        HStack(spacing: 12) {
                            if isLoading {
                                ProgressView()
                                    .scaleEffect(0.8)
                                    .foregroundColor(.white)
                            } else {
                                Image(systemName: "arrow.right.circle.fill")
                                    .font(.system(size: 20))
                            }
                            Text(isLoading ? "正在跳转..." : "授权登录阿里云盘")
                                .font(.headline)
                        }
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 54)
                        .background(
                            LinearGradient(
                                gradient: Gradient(colors: [Color.blue, Color.blue.opacity(0.8)]),
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .cornerRadius(12)
                        .shadow(color: Color.blue.opacity(0.3), radius: 8, x: 0, y: 4)
                    }
                    .disabled(isLoading)
                    
                    Button("取消") {
                        dismiss()
                    }
                    .font(.body)
                    .foregroundColor(.secondary)
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 32)
            }
            .navigationTitle("添加云盘")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("取消") {
                        dismiss()
                    }
                }
            }
        }
        .alert("错误", isPresented: $showingError) {
            Button("确定", role: .cancel) { }
        } message: {
            Text(errorMessage)
        }
    }
    
    // MARK: - 方法
    
    private func startOAuthLogin() {
        print("☁️ [AddAliyunDrive] 开始 OAuth 授权流程")
        isLoading = true
        
        // 1. 生成 state 防止 CSRF
        let state = UUID().uuidString
        savedState = state
        
        print("🔐 [AddAliyunDrive] State: \(state)")
        
        // 2. 构建授权 URL（使用 client_secret 模式，不使用 PKCE）
        let redirectUri = "kumarajiva-ios://aliyun-oauth-callback"
        
        var components = URLComponents(string: "https://openapi.alipan.com/oauth/authorize")!
        components.queryItems = [
            URLQueryItem(name: "client_id", value: service.clientId),
            URLQueryItem(name: "redirect_uri", value: redirectUri),
            URLQueryItem(name: "scope", value: "user:base,file:all:read,file:all:write"),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "state", value: state)
        ]
        
        guard let authURL = components.url else {
            isLoading = false
            errorMessage = "无法构建授权 URL"
            showingError = true
            return
        }
        
        print("🔗 [AddAliyunDrive] 授权 URL: \(authURL)")
        
        // 3. 使用 ASWebAuthenticationSession 进行授权
        // 优势：自动使用 Safari 的登录状态，无需重复登录
        let authSession = AliyunOAuthAuthenticationSession(
            authURL: authURL,
            callbackURLScheme: "kumarajiva-ios",
            onAuthCodeReceived: { code in
                DispatchQueue.main.async {
                    self.isLoading = false
                    self.handleAuthCode(code)
                }
            },
            onError: { error in
                DispatchQueue.main.async {
                    self.isLoading = false
                    self.errorMessage = error
                    self.showingError = true
                }
            },
            onCancel: {
                DispatchQueue.main.async {
                    self.isLoading = false
                }
            }
        )
        
        authSession.start(presentationContext: authContextProvider)
    }
    
    private func handleAuthCode(_ authCode: String) {
        print("✅ [AddAliyunDrive] 获取到授权码: \(authCode.prefix(10))...")
        print("🔐 [AddAliyunDrive] 完整授权码: \(authCode)")
        
        // 使用授权码获取 Token（使用 client_secret 模式）
        Task {
            do {
                isLoading = true
                
                // 1. 获取 Access Token（使用 client_secret）
                try await service.getAccessToken(authCode: authCode, codeVerifier: nil)
                
                // 2. 添加云盘
                try await service.addDrive()
                
                await MainActor.run {
                    isLoading = false
                    print("✅ [AddAliyunDrive] 云盘添加成功")
                    dismiss()
                }
            } catch {
                print("❌ [AddAliyunDrive] 添加云盘失败: \(error)")
                
                await MainActor.run {
                    isLoading = false
                    errorMessage = "添加云盘失败: \(error.localizedDescription)"
                    showingError = true
                }
            }
        }
    }
}

// MARK: - 预览
#Preview {
    AddAliyunDriveView()
}
