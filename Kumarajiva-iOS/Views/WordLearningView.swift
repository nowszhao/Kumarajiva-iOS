import SwiftUI

struct WordLearningView: View {
    @State private var selectedTab = 0
    
    var body: some View {
        VStack(spacing: 0) {
            // 顶部导航
            segmentedControl
            
            // 内容区域 - 使用TabView支持滑动
            TabView(selection: $selectedTab) {
                // 今日学习
                ReviewView()
                    .tag(0)
                
                // 历史复习
                HistoryView()
                    .tag(1)
                
                // 生词库
                VocabularyView()
                    .tag(2)
            }
            .tabViewStyle(PageTabViewStyle(indexDisplayMode: .never))
        }
        .background(Color(.systemBackground))
    }
    
    // MARK: - 分段控制器
    private var segmentedControl: some View {
        VStack(spacing: 0) {
            // 安全区域顶部间距
            Rectangle()
                .fill(Color.clear)
                .frame(height: 22)
            
            // 自定义分段控制器
            HStack(spacing: 0) {
                ForEach(0..<3) { index in
                    Button(action: {
                        withAnimation(.easeInOut(duration: 0.3)) {
                            selectedTab = index
                        }
                    }) {
                        VStack(spacing: 8) {
                            Text(tabTitle(for: index))
                                .font(.system(size: 16, weight: selectedTab == index ? .semibold : .medium))
                                .foregroundColor(selectedTab == index ? .primary : .secondary)
                            
                            // 下划线指示器
                            Rectangle()
                                .fill(selectedTab == index ? Color.accentColor : Color.clear)
                                .frame(height: 2)
                                .frame(width: 24)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                    }
                    .buttonStyle(PlainButtonStyle())
                }
            }
            .padding(.horizontal, 20)
            
            // 底部分割线
            Rectangle()
                .fill(Color(.separator).opacity(0.3))
                .frame(height: 0.5)
        }
        .background(Color(.systemBackground))
    }
    
    private func tabTitle(for index: Int) -> String {
        switch index {
        case 0: return "今日学习"
        case 1: return "历史复习"
        case 2: return "生词库"
        default: return ""
        }
    }
}

// MARK: - 内容包装器视图
struct ContentWrapperView<Content: View>: View {
    let title: String
    let content: Content
    
    init(title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // 页面标题
            HStack {
                Text(title)
                    .font(.system(size: 24, weight: .bold))
                    .foregroundColor(.primary)
                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.top, 20)
            .padding(.bottom, 16)
            .background(Color(.systemBackground))
            
            // 内容区域
            content
        }
    }
}

#Preview {
    WordLearningView()
} 