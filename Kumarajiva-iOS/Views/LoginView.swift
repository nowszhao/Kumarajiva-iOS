import SwiftUI

struct LoginView: View {
    @StateObject private var authService = AuthService.shared
    @State private var showingAlert = false
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // 背景渐变
                LinearGradient(
                    gradient: Gradient(colors: [
                        Color.blue.opacity(0.1),
                        Color.purple.opacity(0.1)
                    ]),
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .ignoresSafeArea()
                
                VStack(spacing: 40) {
                    Spacer()
                    
                    // Logo和标题
                    VStack(spacing: 20) {
                        Image(systemName: "book.circle.fill")
                            .font(.system(size: 80))
                            .foregroundColor(.blue)
                        
                        Text("LEiP")
                            .font(.largeTitle)
                            .fontWeight(.bold)
                            .foregroundColor(.primary)
                        
                        Text("智能词汇学习助手")
                            .font(.title3)
                            .foregroundColor(.secondary)
                    }
                    
                    Spacer()
                    
                    // 登录说明
                    VStack(spacing: 16) {
                        Text("欢迎使用 LEiP")
                            .font(.title2)
                            .fontWeight(.semibold)
                            .multilineTextAlignment(.center)
                        
                        Text("请使用 GitHub 账号登录，享受个性化的词汇学习体验")
                            .font(.body)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 20)
                    }
                    
                    // 登录按钮
                    VStack(spacing: 16) {
                        Button(action: {
                            print("🔘 [LoginView] 用户点击GitHub登录按钮")
                            authService.startGitHubOAuth()
                        }) {
                            HStack(spacing: 12) {
                                if authService.isLoading {
                                    ProgressView()
                                        .scaleEffect(0.8)
                                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                } else {
                                    Image(systemName: "person.circle.fill")
                                        .font(.title3)
                                }
                                
                                Text(authService.isLoading ? "登录中..." : "使用 GitHub 登录")
                                    .font(.headline)
                                    .fontWeight(.semibold)
                            }
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .frame(height: 56)
                            .background(
                                LinearGradient(
                                    gradient: Gradient(colors: [Color.blue, Color.purple]),
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .cornerRadius(16)
                            .shadow(color: Color.blue.opacity(0.3), radius: 8, x: 0, y: 4)
                        }
                        .disabled(authService.isLoading)
                        .padding(.horizontal, 32)
                        
                        // 错误信息
                        if let errorMessage = authService.errorMessage {
                            Text(errorMessage)
                                .font(.caption)
                                .foregroundColor(.red)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, 32)
                        }
                    }
                    
                    Spacer()
                    
                    // 底部说明
                    VStack(spacing: 8) {
                        Text("登录即表示您同意我们的服务条款")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        
                        Text("您的数据将安全存储并仅用于学习功能")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding(.bottom, 20)
                }
            }
        }
        .alert("登录失败", isPresented: $showingAlert) {
            Button("确定") { }
        } message: {
            Text(authService.errorMessage ?? "未知错误")
        }
        .onChange(of: authService.errorMessage) { errorMessage in
            if let error = errorMessage {
                print("❌ [LoginView] 收到错误消息: \(error)")
                showingAlert = true
            }
        }
        .onAppear {
            print("📱 [LoginView] 登录视图出现")
            print("🔐 [LoginView] 当前认证状态: \(authService.isAuthenticated)")
            print("⏳ [LoginView] 当前加载状态: \(authService.isLoading)")
        }
    }
}

#Preview {
    LoginView()
} 
