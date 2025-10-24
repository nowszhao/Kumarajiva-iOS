import SwiftUI
import WebKit

struct AliyunOAuthWebView: UIViewRepresentable {
    let authURL: URL
    let onAuthCodeReceived: (String) -> Void
    let onError: (String) -> Void
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    func makeUIView(context: Context) -> WKWebView {
        // 配置 WebView
        let configuration = WKWebViewConfiguration()
        
        // 允许 JavaScript
        let preferences = WKWebpagePreferences()
        preferences.allowsContentJavaScript = true
        configuration.defaultWebpagePreferences = preferences
        
        // 允许内联媒体播放
        configuration.allowsInlineMediaPlayback = true
        
        // 允许 AirPlay
        configuration.allowsAirPlayForMediaPlayback = true
        
        // 允许画中画
        configuration.allowsPictureInPictureMediaPlayback = true
        
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        
        // 允许返回手势
        webView.allowsBackForwardNavigationGestures = true
        
        // 设置 User Agent（模拟移动端浏览器）
        webView.customUserAgent = "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1"
        
        // 加载授权页面
        var request = URLRequest(url: authURL)
        request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        webView.load(request)
        
        print("🌐 [OAuth WebView] 加载授权页面: \(authURL)")
        
        return webView
    }
    
    func updateUIView(_ webView: WKWebView, context: Context) {
        // 不需要更新
    }
    
    class Coordinator: NSObject, WKNavigationDelegate {
        let parent: AliyunOAuthWebView
        
        init(_ parent: AliyunOAuthWebView) {
            self.parent = parent
        }
        
        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            guard let url = navigationAction.request.url else {
                print("⚠️ [OAuth WebView] 导航 URL 为空")
                decisionHandler(.allow)
                return
            }
            
            print("🔗 [OAuth WebView] 导航到: \(url)")
            print("🔗 [OAuth WebView] Scheme: \(url.scheme ?? "nil"), Host: \(url.host ?? "nil")")
            
            // 检查是否是回调 URL
            if url.scheme == "kumarajiva-ios" && url.host == "aliyun-oauth-callback" {
                print("✅ [OAuth WebView] 检测到回调 URL")
                
                // 提取授权码
                if let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
                   let code = components.queryItems?.first(where: { $0.name == "code" })?.value {
                    print("✅ [OAuth WebView] 获取到授权码: \(code.prefix(10))...")
                    parent.onAuthCodeReceived(code)
                } else {
                    print("❌ [OAuth WebView] 未找到授权码")
                    parent.onError("未获取到授权码")
                }
                
                decisionHandler(.cancel)
                return
            }
            
            // 允许所有其他导航
            decisionHandler(.allow)
        }
        
        func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
            print("🌐 [OAuth WebView] 开始加载页面")
        }
        
        func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {
            print("🌐 [OAuth WebView] 页面内容开始返回")
        }
        
        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            print("✅ [OAuth WebView] 页面加载完成")
            if let currentURL = webView.url {
                print("✅ [OAuth WebView] 当前 URL: \(currentURL)")
            }
        }
        
        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            let nsError = error as NSError
            print("❌ [OAuth WebView] 加载失败: \(error.localizedDescription)")
            print("❌ [OAuth WebView] 错误域: \(nsError.domain), 错误码: \(nsError.code)")
            
            // 忽略用户取消的错误
            if nsError.domain == "WebKitErrorDomain" && nsError.code == 102 {
                print("⚠️ [OAuth WebView] 帧加载中断（可能是正常的重定向）")
                return
            }
            
            parent.onError("页面加载失败: \(error.localizedDescription)")
        }
        
        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            let nsError = error as NSError
            print("❌ [OAuth WebView] 临时导航失败: \(error.localizedDescription)")
            print("❌ [OAuth WebView] 错误域: \(nsError.domain), 错误码: \(nsError.code)")
            
            // 忽略帧加载中断错误（通常是因为重定向到自定义 scheme）
            if nsError.domain == "WebKitErrorDomain" && nsError.code == 102 {
                print("⚠️ [OAuth WebView] 帧加载中断（可能是重定向到回调 URL）")
                return
            }
            
            parent.onError("页面加载失败: \(error.localizedDescription)")
        }
    }
}

// MARK: - OAuth WebView 容器
struct AliyunOAuthWebViewContainer: View {
    let authURL: URL
    let onAuthCodeReceived: (String) -> Void
    let onCancel: () -> Void
    let onError: (String) -> Void
    
    var body: some View {
        NavigationView {
            ZStack {
                AliyunOAuthWebView(
                    authURL: authURL,
                    onAuthCodeReceived: onAuthCodeReceived,
                    onError: onError
                )
                .edgesIgnoringSafeArea(.all)
            }
            .navigationTitle("阿里云盘授权")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("取消") {
                        onCancel()
                    }
                }
            }
        }
    }
}
