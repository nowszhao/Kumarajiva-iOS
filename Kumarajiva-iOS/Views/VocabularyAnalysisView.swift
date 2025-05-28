import SwiftUI

struct VocabularyAnalysisView: View {
    @ObservedObject var playerService: PodcastPlayerService
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var viewModel = VocabularyViewModel.shared
    
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
                    
                    // 重新解析按钮
                    Button {
                        Task {
                            await playerService.analyzeVocabulary()
                        }
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "arrow.clockwise")
                                .font(.system(size: 14, weight: .medium))
                            Text("重新解析")
                                .font(.system(size: 14, weight: .medium))
                        }
                        .foregroundColor(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(Color.accentColor)
                        .cornerRadius(8)
                    }
                    .disabled(playerService.vocabularyAnalysisState == .analyzing)
                }
                .padding(.horizontal, 16)
                .padding(.top, 16)
                
                // 生词卡片列表
                ForEach(vocabulary) { word in
                    VocabularyCardView(vocabulary: word, viewModel: viewModel)
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
    let viewModel: VocabularyViewModel
    @State private var isExpanded = false
    @State private var isCollected = false
    @State private var isLocallyAdded = false  // 是否为本地新词
    @State private var isFromCloud = false     // 是否为云端词汇
    @State private var isLoading = false
    @State private var showRemoveAlert = false  // 显示移除确认对话框
    
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
                    
                    // 收藏按钮
                    Button {
                        handleStarTap()
                    } label: {
                        if isLoading {
                            ProgressView()
                                .scaleEffect(0.8)
                                .frame(width: 24, height: 24)
                        } else {
                            Image(systemName: isCollected ? "star.fill" : "star")
                                .font(.system(size: 20))
                                .foregroundColor(starColor)
                                .scaleEffect(isCollected ? 1.1 : 1.0)
                                .animation(.easeInOut(duration: 0.2), value: isCollected)
                        }
                    }
                    .buttonStyle(PlainButtonStyle())
                    .padding(.trailing, 8)
                    .disabled(isCollected && isFromCloud)  // 云端词汇禁用点击
                    
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
                        
                        // 状态提示（仅在已收藏时显示）
                        if isCollected {
                            HStack(spacing: 6) {
                                Image(systemName: isLocallyAdded ? "iphone" : "cloud")
                                    .font(.system(size: 12))
                                    .foregroundColor(isLocallyAdded ? .blue : .gray)
                                
                                Text(statusText)
                                    .font(.system(size: 12))
                                    .foregroundColor(isLocallyAdded ? .blue : .gray)
                                
                                if isLocallyAdded {
                                    Text("• 点击星号可取消收藏")
                                        .font(.system(size: 11))
                                        .foregroundColor(.orange)
                                }
                            }
                            .padding(.top, 4)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 12)
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(.systemBackground))
                .shadow(color: Color.black.opacity(0.1), radius: 5, x: 0, y: 2)
        )
        .task {
            updateCollectionStatus()
        }
        .onChange(of: viewModel.vocabularies) { _ in
            updateCollectionStatus()
        }
        .alert("取消收藏", isPresented: $showRemoveAlert) {
            Button("取消", role: .cancel) { }
            Button("确认取消", role: .destructive) {
                performRemoveVocabulary()
            }
        } message: {
            Text("确定要取消收藏生词 \"\(vocabulary.vocabulary)\" 吗？\n\n此操作将从本地生词库中移除该词汇。")
        }
    }
    
    // MARK: - Helper Methods
    
    private var starColor: Color {
        if !isCollected {
            return .gray.opacity(0.6)
        } else if isLocallyAdded {
            return .yellow  // 本地新词：黄色五星
        } else {
            return .gray.opacity(0.8)    // 云端词汇：灰色五星
        }
    }
    
    private var statusText: String {
        if isLocallyAdded {
            return "本地新词"
        } else {
            return "云端词汇"
        }
    }
    
    private func updateCollectionStatus() {
        isCollected = viewModel.isVocabularyCollected(vocabulary.vocabulary)
        isLocallyAdded = viewModel.isVocabularyLocallyAdded(vocabulary.vocabulary)
        isFromCloud = viewModel.isVocabularyFromCloud(vocabulary.vocabulary)
    }
    
    private func handleStarTap() {
        guard !isLoading else { return }
        
        // 添加触觉反馈
        let impactFeedback = UIImpactFeedbackGenerator(style: .medium)
        impactFeedback.impactOccurred()
        
        if isCollected {
            // 已收藏的情况
            if isLocallyAdded {
                // 本地新词：显示确认对话框
                showRemoveAlert = true
            } else {
                // 云端词汇：显示提示信息
                let notificationFeedback = UINotificationFeedbackGenerator()
                notificationFeedback.notificationOccurred(.warning)
                print("⚠️ 云端词汇 '\(vocabulary.vocabulary)' 不允许取消收藏")
                
                // 可以考虑添加一个临时的视觉提示
                withAnimation(.easeInOut(duration: 0.3)) {
                    // 这里可以添加一个临时的提示动画
                }
            }
        } else {
            // 未收藏的情况：添加到本地
            addVocabularyToLocal()
        }
    }
    
    private func addVocabularyToLocal() {
        isLoading = true
        
        // 添加成功的触觉反馈
        let notificationFeedback = UINotificationFeedbackGenerator()
        
        let item = VocabularyItem(from: vocabulary)
        viewModel.addVocabularyLocally(item)
        
        // 延迟更新状态，让用户看到加载动画
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            updateCollectionStatus()
            isLoading = false
            notificationFeedback.notificationOccurred(.success)
            print("✅ 已收藏生词 '\(vocabulary.vocabulary)'")
        }
    }
    
    private func performRemoveVocabulary() {
        isLoading = true
        
        // 移除成功的触觉反馈
        let notificationFeedback = UINotificationFeedbackGenerator()
        
        viewModel.removeLocalVocabulary(vocabulary.vocabulary)
        
        // 延迟更新状态
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            updateCollectionStatus()
            isLoading = false
            notificationFeedback.notificationOccurred(.success)
            print("✅ 已取消收藏本地生词 '\(vocabulary.vocabulary)'")
        }
    }
    
    private func typeColor(for type: String) -> Color {
        switch type.lowercased() {
        case "words":
            return .blue
        case "phrases":
            return .purple
        case "idioms":
            return .orange
        default:
            return .gray
        }
    }
}

// MARK: - 预览
#Preview {
    VocabularyAnalysisView(playerService: PodcastPlayerService.shared)
} 