import SwiftUI

struct VocabularyAnalysisView: View {
    @ObservedObject var playerService: PodcastPlayerService
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // 标题区域
                headerView
                
                // 内容区域
                contentView
            }
            .navigationBarHidden(true)
            .background(Color(.systemGroupedBackground))
        }
    }
    
    // MARK: - 标题区域
    private var headerView: some View {
        VStack(spacing: 0) {
            // 导航栏
            HStack {
                Button("取消") {
                    dismiss()
                }
                .font(.system(size: 17))
                .foregroundColor(.accentColor)
                
                Spacer()
                
                Text("生词列表")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundColor(.primary)
                
                Spacer()
                
                // 占位符保持平衡
                Text("取消")
                    .font(.system(size: 17))
                    .foregroundColor(.clear)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(Color(.systemBackground))
            
            Divider()
        }
    }
    
    // MARK: - 内容区域
    private var contentView: some View {
        Group {
            switch playerService.vocabularyAnalysisState {
            case .idle:
                idleView
            case .analyzing:
                analyzingView
            case .completed(let vocabulary):
                vocabularyListView(vocabulary)
            case .failed(let error):
                errorView(error)
            }
        }
    }
    
    // MARK: - 空闲状态
    private var idleView: some View {
        VStack(spacing: 24) {
            Spacer()
            
            Image(systemName: "text.magnifyingglass")
                .font(.system(size: 60))
                .foregroundColor(.secondary)
            
            VStack(spacing: 12) {
                Text("生词解析")
                    .font(.title2)
                    .fontWeight(.semibold)
                    .foregroundColor(.primary)
                
                Text("AI将分析当前播客字幕中的难词\n帮助您更好地学习英语")
                    .font(.body)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .lineSpacing(2)
            }
            
            Button {
                Task {
                    await playerService.analyzeVocabulary()
                }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "sparkles")
                    Text("开始解析")
                }
                .font(.system(size: 17, weight: .medium))
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 50)
                .background(Color.accentColor)
                .cornerRadius(12)
            }
            .padding(.horizontal, 32)
            .disabled(playerService.currentSubtitles.isEmpty)
            
            if playerService.currentSubtitles.isEmpty {
                Text("请先生成字幕后再进行生词解析")
                    .font(.caption)
                    .foregroundColor(.orange)
                    .multilineTextAlignment(.center)
            }
            
            Spacer()
        }
        .padding(.horizontal, 20)
    }
    
    // MARK: - 分析中状态
    private var analyzingView: some View {
        VStack(spacing: 24) {
            Spacer()
            
            // 加载动画
            ZStack {
                Circle()
                    .stroke(Color.gray.opacity(0.3), lineWidth: 4)
                    .frame(width: 60, height: 60)
                
                Circle()
                    .trim(from: 0, to: 0.7)
                    .stroke(Color.accentColor, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                    .frame(width: 60, height: 60)
                    .rotationEffect(.degrees(-90))
                    .animation(.linear(duration: 1).repeatForever(autoreverses: false), value: UUID())
                
                Image(systemName: "sparkles")
                    .font(.title3)
                    .foregroundColor(.accentColor)
            }
            
            VStack(spacing: 8) {
                Text("AI正在分析中...")
                    .font(.headline)
                    .foregroundColor(.primary)
                
                Text("请稍候，这可能需要几秒钟")
                    .font(.body)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
        }
    }
    
    // MARK: - 生词列表
    private func vocabularyListView(_ vocabulary: [DifficultVocabulary]) -> some View {
        ScrollView {
            LazyVStack(spacing: 12) {
                // 统计信息
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("共找到 \(vocabulary.count) 个生词")
                            .font(.headline)
                            .foregroundColor(.primary)
                        
                        Text("点击单词查看详细信息")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    
                    Spacer()
                }
                .padding(.horizontal, 16)
                .padding(.top, 16)
                
                // 生词卡片列表
                ForEach(vocabulary) { word in
                    VocabularyCardView(vocabulary: word)
                        .padding(.horizontal, 16)
                }
                
                // 底部间距
                Color.clear.frame(height: 20)
            }
        }
    }
    
    // MARK: - 错误状态
    private func errorView(_ error: String) -> some View {
        VStack(spacing: 24) {
            Spacer()
            
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 50))
                .foregroundColor(.orange)
            
            VStack(spacing: 12) {
                Text("解析失败")
                    .font(.title2)
                    .fontWeight(.semibold)
                    .foregroundColor(.primary)
                
                Text(error)
                    .font(.body)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }
            
            Button {
                Task {
                    await playerService.analyzeVocabulary()
                }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "arrow.clockwise")
                    Text("重试")
                }
                .font(.system(size: 17, weight: .medium))
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 50)
                .background(Color.accentColor)
                .cornerRadius(12)
            }
            .padding(.horizontal, 32)
            
            Spacer()
        }
        .padding(.horizontal, 20)
    }
}

// MARK: - 生词卡片视图
struct VocabularyCardView: View {
    let vocabulary: DifficultVocabulary
    @State private var isExpanded = false
    
    var body: some View {
        VStack(spacing: 0) {
            // 主要信息区域
            Button {
                withAnimation(.easeInOut(duration: 0.3)) {
                    isExpanded.toggle()
                }
            } label: {
                HStack(spacing: 12) {
                    // 单词和类型
                    VStack(alignment: .leading, spacing: 4) {
                        Text(vocabulary.vocabulary)
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundColor(.accentColor)
                            .multilineTextAlignment(.leading)
                        
                        HStack(spacing: 8) {
                            Text(vocabulary.phonetic)
                                .font(.system(size: 13, weight: .medium, design: .monospaced))
                                .foregroundColor(.secondary)
                            
                            Text(vocabulary.partOfSpeech)
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(.white)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(typeColor(for: vocabulary.type))
                                .cornerRadius(4)
                        }
                    }
                    
                    Spacer()
                    
                    // 展开/收起图标
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.secondary)
                        .animation(.easeInOut(duration: 0.3), value: isExpanded)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
            .buttonStyle(PlainButtonStyle())
            
            // 详细信息区域（可展开）
            if isExpanded {
                VStack(alignment: .leading, spacing: 12) {
                    Divider()
                        .padding(.horizontal, 16)
                    
                    VStack(alignment: .leading, spacing: 8) {
                        // 中文释义
                        HStack(alignment: .top, spacing: 8) {
                            Text("释义:")
                                .font(.system(size: 14, weight: .medium))
                                .foregroundColor(.secondary)
                                .frame(width: 40, alignment: .leading)
                            
                            Text(vocabulary.chineseMeaning)
                                .font(.system(size: 15))
                                .foregroundColor(.primary)
                                .multilineTextAlignment(.leading)
                        }
                        
                        // 例句
                        HStack(alignment: .top, spacing: 8) {
                            Text("例句:")
                                .font(.system(size: 14, weight: .medium))
                                .foregroundColor(.secondary)
                                .frame(width: 40, alignment: .leading)
                            
                            Text(vocabulary.chineseEnglishSentence)
                                .font(.system(size: 15))
                                .foregroundColor(.primary)
                                .lineSpacing(2)
                                .multilineTextAlignment(.leading)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 12)
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .background(Color(.systemBackground))
        .cornerRadius(12)
        .shadow(color: .black.opacity(0.05), radius: 2, x: 0, y: 1)
    }
    
    private func typeColor(for type: String) -> Color {
        switch type.lowercased() {
        case "words":
            return .blue
        case "phrases":
            return .green
        case "slang":
            return .orange
        case "abbreviations":
            return .purple
        default:
            return .gray
        }
    }
}

// MARK: - 预览
#Preview {
    VocabularyAnalysisView(playerService: PodcastPlayerService.shared)
} 