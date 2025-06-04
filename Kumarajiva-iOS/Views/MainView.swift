import SwiftUI

struct MainView: View {
    var body: some View {
        TabView {
            WordLearningView()
                .tabItem {
                    Label("单词", systemImage: "book.fill")
                }
            
            SubscriptionView()
                .tabItem {
                    Label("订阅", systemImage: "star.fill")
                }
            
            ProfileView()
                .tabItem {
                    Label("我的", systemImage: "person.fill")
                }
        }
        .accentColor(.accentColor)
    }
} 