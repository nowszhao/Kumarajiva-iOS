import SwiftUI

struct MainView: View {
    var body: some View {
        TabView {
            WordLearningView()
                .tabItem {
                    Label("记单词", systemImage: "book.fill")
                }
            
            ListeningPracticeView()
                .tabItem {
                    Label("练听力", systemImage: "headphones")
                }
            
            ProfileView()
                .tabItem {
                    Label("我的", systemImage: "person.fill")
                }
        }
        .accentColor(.accentColor)
    }
} 