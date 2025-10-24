import SwiftUI
import AuthenticationServices

/// 使用 ASWebAuthenticationSession 进行 OAuth 授权
/// 优势：
/// 1. 自动使用 Safari 的登录状态，无需重复登录
/// 2. 系统级别的安全保护
/// 3. 更好的用户体验
struct AliyunOAuthAuthenticationSession {
    let authURL: URL
    let callbackURLScheme: String
    let onAuthCodeReceived: (String) -> Void
    let onError: (String) -> Void
    let onCancel: () -> Void
    
    func start(presentationContext: ASWebAuthenticationPresentationContextProviding) {
        print("🔐 [OAuth Session] 启动 ASWebAuthenticationSession")
        print("🔗 [OAuth Session] 授权 URL: \(authURL)")
        print("🔗 [OAuth Session] 回调 Scheme: \(callbackURLScheme)")
        
        let session = ASWebAuthenticationSession(
            url: authURL,
            callbackURLScheme: callbackURLScheme
        ) { callbackURL, error in
            if let error = error {
                // 检查是否是用户取消
                if case ASWebAuthenticationSessionError.canceledLogin = error {
                    print("⚠️ [OAuth Session] 用户取消授权")
                    onCancel()
                    return
                }
                
                print("❌ [OAuth Session] 授权失败: \(error.localizedDescription)")
                onError("授权失败: \(error.localizedDescription)")
                return
            }
            
            guard let callbackURL = callbackURL else {
                print("❌ [OAuth Session] 回调 URL 为空")
                onError("授权失败：未获取到回调 URL")
                return
            }
            
            print("✅ [OAuth Session] 收到回调 URL: \(callbackURL)")
            
            // 提取授权码
            guard let components = URLComponents(url: callbackURL, resolvingAgainstBaseURL: false),
                  let code = components.queryItems?.first(where: { $0.name == "code" })?.value else {
                print("❌ [OAuth Session] 未找到授权码")
                onError("授权失败：未获取到授权码")
                return
            }
            
            print("✅ [OAuth Session] 获取到授权码: \(code.prefix(10))...")
            onAuthCodeReceived(code)
        }
        
        // 设置展示上下文
        session.presentationContextProvider = presentationContext
        
        // iOS 13+ 支持：优先使用短暂的浏览器会话（不保存 Cookie）
        if #available(iOS 13.0, *) {
            session.prefersEphemeralWebBrowserSession = false  // 使用持久会话，保存登录状态
        }
        
        // 启动授权会话
        session.start()
        print("🚀 [OAuth Session] 授权会话已启动")
    }
}

/// ASWebAuthenticationSession 的展示上下文提供者
class AuthenticationSessionContextProvider: NSObject, ASWebAuthenticationPresentationContextProviding {
    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        // 返回当前的 key window
        return UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap { $0.windows }
            .first { $0.isKeyWindow } ?? UIWindow()
    }
}
