import SwiftUI

struct MainView: View {
    var body: some View {
        TabView {
            ReviewView()
                .tabItem {
                    Label("今日回顾", systemImage: "book.fill")
                }
            
            HistoryView()
                .tabItem {
                    Label("历史记录", systemImage: "clock.fill")
                }
            
            SettingsView()
                .tabItem {
                    Label("设置", systemImage: "gear")
                }
        }
    }
} 