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
    @StateObject private var dataService = PodcastDataService.shared
    @StateObject private var networkMonitor = NetworkMonitor.shared
    @Environment(\.scenePhase) private var scenePhase
    
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
                
                // 处理不同类型的OAuth回调
                if url.host == "oauth-callback" || url.host == "oauth-error" {
                    // GitHub OAuth回调
                    let handled = authService.handleOAuthCallback(url: url)
                    print("📱 [App] GitHub OAuth回调处理结果: \(handled)")
                } else if url.host == "aliyun-oauth-callback" {
                    // 阿里云盘OAuth回调
                    print("📱 [App] 阿里云盘OAuth回调，将由AddAliyunDriveView处理")
                    // 回调会被AddAliyunDriveView的onOpenURL处理器捕获
                } else {
                    print("⚠️ [App] 未知的URL回调类型: \(url.host ?? "nil")")
                }
            }
            .onAppear {
                print("📱 [App] 应用启动")
                print("🔐 [App] 当前认证状态: \(authService.isAuthenticated)")
                
                // 检查并清理UserDefaults中的大数据，解决4MB限制警告
                Task {
                    await MainActor.run {
                        let storage = PersistentStorageManager.shared
                        storage.checkUserDefaultsLargeData()
                        
                        // 自动清理大数据（可选择性启用）
                        storage.cleanupUserDefaultsLargeData()
                    }
                }
            }
            .onChange(of: scenePhase) { newPhase in
                switch newPhase {
                case .background:
                    print("📱 [App] 应用进入后台，同步字幕缓存")
                    Task {
                        await dataService.syncSubtitleCacheToMainData()
                        // 强制保存所有数据，确保不会丢失
                        await MainActor.run {
                            PersistentStorageManager.shared.forceSave(dataService.podcasts)
                        }
                    }
                case .active:
                    print("📱 [App] 应用变为活跃状态")
                    // 应用重新激活时，重新加载数据以确保同步
                    Task {
                        await MainActor.run {
                            dataService.objectWillChange.send()
                        }
                    }
                case .inactive:
                    print("📱 [App] 应用变为非活跃状态，预备保存数据")
                    // 应用即将进入后台时也保存数据
                    Task {
                        await dataService.syncSubtitleCacheToMainData()
                    }
                @unknown default:
                    break
                }
            }
        }
    }
}
