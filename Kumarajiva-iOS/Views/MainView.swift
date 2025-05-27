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
            
            ListeningPracticeView()
                .tabItem {
                    Label("听力练习", systemImage: "headphones")
                }
            
            ProfileView()
                .tabItem {
                    Label("我的", systemImage: "person.fill")
                }
        }
    }
} 