//
//  Kumarajiva_iOSApp.swift
//  Kumarajiva-iOS
//
//  Created by changhozhao on 2025/2/9.
//

import SwiftUI

@main
struct Kumarajiva_iOSApp: App {
    @StateObject private var authService = AuthService.shared
    
    var body: some Scene {
        WindowGroup {
            Group {
                if authService.isAuthenticated {
                    MainView()
                } else {
                    LoginView()
                }
            }
            .onOpenURL { url in
                print("📱 [App] 收到URL回调: \(url)")
                // 处理OAuth回调
                let handled = authService.handleOAuthCallback(url: url)
                print("📱 [App] URL回调处理结果: \(handled)")
            }
            .onAppear {
                print("📱 [App] 应用启动")
                print("🔐 [App] 当前认证状态: \(authService.isAuthenticated)")
            }
        }
    }
}
