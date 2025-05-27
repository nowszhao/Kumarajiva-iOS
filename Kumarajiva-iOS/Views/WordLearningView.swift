import SwiftUI

struct WordLearningView: View {
    @State private var selectedTab = 0
    
    var body: some View {
        VStack(spacing: 0) {
            // 顶部导航
            segmentedControl
            
            // 内容区域
            contentView
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
        case 0: return "每日测验"
        case 1: return "回顾"
        case 2: return "生词库"
        default: return ""
        }
    }
    
    // MARK: - 内容视图
    private var contentView: some View {
        Group {
            switch selectedTab {
            case 0:
                // 每日测验 - 对应原来的今日回顾
                ReviewView()
                .transition(.asymmetric(
                    insertion: .move(edge: .trailing).combined(with: .opacity),
                    removal: .move(edge: .leading).combined(with: .opacity)
                ))
            case 1:
                // 回顾 - 对应原来的历史记录
                HistoryView()
                .transition(.asymmetric(
                    insertion: .move(edge: selectedTab > 1 ? .leading : .trailing).combined(with: .opacity),
                    removal: .move(edge: selectedTab > 1 ? .trailing : .leading).combined(with: .opacity)
                ))
            case 2:
                // 生词库 - 预留功能
                VocabularyLibraryView()
                    .transition(.asymmetric(
                        insertion: .move(edge: .leading).combined(with: .opacity),
                        removal: .move(edge: .trailing).combined(with: .opacity)
                    ))
            default:
                    ReviewView()
                
            }
        }
        .animation(.easeInOut(duration: 0.25), value: selectedTab)
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

// MARK: - 生词库视图（预留）
struct VocabularyLibraryView: View {
    var body: some View {
        VStack(spacing: 0) {            
            // 内容区域
            ScrollView {
                VStack(spacing: 0) {
                    // 空状态视图
                    emptyStateView
                        .padding(.top, 60)
                }
            }
            // .background(Color(.systemGroupedBackground))
        }
    }
    
    private var emptyStateView: some View {
        VStack(spacing: 16) {
            // 图标
            ZStack {
                Circle()
                    .fill(Color(.systemGray6))
                    .frame(width: 80, height: 80)
                
                Image(systemName: "book.closed.fill")
                    .font(.system(size: 32, weight: .medium))
                    .foregroundColor(.secondary)
            }
            
            // 描述
            VStack(spacing: 8) {
                Text("这里将展示您收集的所有生词")
                    .font(.system(size: 16))
                    .foregroundColor(.secondary)
                
                Text("敬请期待")
                    .font(.system(size: 16))
                    .foregroundColor(.secondary)
            }
            .multilineTextAlignment(.center)
            
            // 占位按钮
            Button(action: {
                // 预留功能
            }) {
                HStack(spacing: 6) {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 14, weight: .medium))
                    Text("添加生词")
                        .font(.system(size: 14, weight: .medium))
                }
                .foregroundColor(.white)
                .padding(.horizontal, 20)
                .padding(.vertical, 10)
                .background(Color.accentColor)
                .clipShape(Capsule())
            }
            .disabled(true)
            .opacity(0.6)
        }
        .padding(.horizontal, 24)
    }
}

#Preview {
    WordLearningView()
} 