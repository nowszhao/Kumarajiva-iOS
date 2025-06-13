import SwiftUI

// MARK: - 解析模式枚举
enum VocabularyAnalysisMode {
    case fullText    // 全文解析
    case selective   // 选择解析
}

// MARK: - 解析状态枚举  
enum VocabularyAnalysisStep {
    case modeSelection    // 模式选择
    case wordSelection    // 单词选择（仅限选择解析模式）
    case analyzing        // 分析中
    case completed        // 完成
    case failed           // 失败
}

struct VocabularyAnalysisView: View {
    @ObservedObject var playerService: PodcastPlayerService
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var viewModel = VocabularyViewModel.shared
    
    // 状态管理
    @State private var currentStep: VocabularyAnalysisStep = .modeSelection
    @State private var selectedMode: VocabularyAnalysisMode = .fullText
    @State private var selectedWords: Set<String> = []
    @State private var errorMessage: String = ""
    @State private var analysisResult: [DifficultVocabulary] = []
    
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
        .onAppear {
            initializeViewState()
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
                
                Text(navigationTitle)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundColor(.primary)
                
                Spacer()
                
                // 在分段解析时显示查看结果按钮
                Group {
                    if currentStep == .analyzing,
                       case .partialCompleted(let vocabulary, _, _) = playerService.vocabularyAnalysisState,
                       !vocabulary.isEmpty {
                        Button {
                            analysisResult = vocabulary
                            currentStep = .completed
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "list.bullet")
                                    .font(.system(size: 14))
                                Text("\(vocabulary.count)")
                                    .font(.system(size: 14, weight: .medium))
                            }
                            .foregroundColor(.accentColor)
                        }
                    } else {
                        // 占位符保持平衡
                        Text("取消")
                            .font(.system(size: 17))
                            .foregroundColor(.clear)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(Color(.systemBackground))
            
            Divider()
        }
    }
    
    // 动态标题
    private var navigationTitle: String {
        switch currentStep {
        case .modeSelection:
            return "生词解析"
        case .wordSelection:
            return "选择生词"
        case .analyzing:
            // 根据分析状态显示不同标题
            switch playerService.vocabularyAnalysisState {
            case .partialCompleted(_, let currentSegment, let totalSegments):
                return "分析中 (\(currentSegment)/\(totalSegments))"
            default:
                return "分析中"
            }
        case .completed, .failed:
            return "生词列表"
        }
    }
    
    // MARK: - 内容区域
    private var contentView: some View {
        Group {
            switch currentStep {
            case .modeSelection:
                modeSelectionView
            case .wordSelection:
                wordSelectionView
            case .analyzing:
                analyzingView
            case .completed:
                vocabularyListView(analysisResult)
            case .failed:
                errorView(errorMessage)
            }
        }
    }
    
    // MARK: - 模式选择视图
    private var modeSelectionView: some View {
        VStack(spacing: 32) {
            Spacer()
            
            // 图标和标题
            VStack(spacing: 16) {
                Image(systemName: "text.magnifyingglass")
                    .font(.system(size: 50))
                    .foregroundColor(.accentColor)
                
                VStack(spacing: 8) {
                    Text("生词解析")
                        .font(.title2)
                        .fontWeight(.semibold)
                        .foregroundColor(.primary)
                    
                    Text("选择您希望的解析方式")
                        .font(.body)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
            }
            
            // 解析模式选项
            VStack(spacing: 16) {
                // 全文解析
                Button {
                    selectedMode = .fullText
                    startFullTextAnalysis()
                } label: {
                    HStack(spacing: 16) {
                        Image(systemName: "doc.text.magnifyingglass")
                            .font(.system(size: 24))
                            .foregroundColor(.white)
                            .frame(width: 44, height: 44)
                            .background(Color.blue)
                            .cornerRadius(12)
                        
                        VStack(alignment: .leading, spacing: 4) {
                            Text("全文解析")
                                .font(.system(size: 17, weight: .semibold))
                                .foregroundColor(.primary)
                            
                            Text("AI自动分析所有字幕中的难词")
                                .font(.system(size: 15))
                                .foregroundColor(.secondary)
                        }
                        
                        Spacer()
                        
                        Image(systemName: "chevron.right")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(.secondary)
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 16)
                    .background(Color(.systemBackground))
                    .cornerRadius(16)
                    .shadow(color: .black.opacity(0.08), radius: 8, x: 0, y: 2)
                }
                .buttonStyle(PlainButtonStyle())
                .disabled(playerService.currentSubtitles.isEmpty)
                
                // 选择解析
                Button {
                    selectedMode = .selective
                    selectAllMarkedWords()
                    currentStep = .wordSelection
                } label: {
                    HStack(spacing: 16) {
                        Image(systemName: "hand.tap")
                            .font(.system(size: 24))
                            .foregroundColor(.white)
                            .frame(width: 44, height: 44)
                            .background(Color.purple)
                            .cornerRadius(12)
                        
                        VStack(alignment: .leading, spacing: 4) {
                            Text("选择解析")
                                .font(.system(size: 17, weight: .semibold))
                                .foregroundColor(.primary)
                            
                            Text("手动选择不熟悉的单词进行解析")
                                .font(.system(size: 15))
                                .foregroundColor(.secondary)
                        }
                        
                        Spacer()
                        
                        Image(systemName: "chevron.right")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(.secondary)
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 16)
                    .background(Color(.systemBackground))
                    .cornerRadius(16)
                    .shadow(color: .black.opacity(0.08), radius: 8, x: 0, y: 2)
                }
                .buttonStyle(PlainButtonStyle())
                .disabled(playerService.currentSubtitles.isEmpty)
            }
            .padding(.horizontal, 24)
            
            if playerService.currentSubtitles.isEmpty {
                Text("请先生成字幕后再进行生词解析")
                    .font(.caption)
                    .foregroundColor(.orange)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
            }
            
            Spacer()
        }
        .padding(.horizontal, 20)
    }
    
    // MARK: - 单词选择视图
    private var wordSelectionView: some View {
        VStack(spacing: 0) {
            // 选择状态栏
            selectionStatusBar
            
            // 字幕内容
            subtitleSelectionView
            
            // 底部操作栏
            selectionActionBar
        }
    }
    
    // 选择状态栏
    private var selectionStatusBar: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("点击选择不熟悉的单词")
                    .font(.headline)
                    .foregroundColor(.primary)
                
                Text("已选择 \(selectedWords.count) 个单词")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            // 全选/全不选按钮
            Button {
                if selectedWords.isEmpty {
                    selectAllWords()
                } else {
                    selectedWords.removeAll()
                }
            } label: {
                Text(selectedWords.isEmpty ? "全选" : "清空")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.accentColor)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Color(.systemBackground))
        .overlay(
            Rectangle()
                .frame(height: 1)
                .foregroundColor(Color(.separator))
                .frame(maxHeight: .infinity, alignment: .bottom)
        )
    }
    
    // 字幕选择视图
    private var subtitleSelectionView: some View {
        ScrollView {
            LazyVStack(spacing: 12) {
                ForEach(playerService.currentSubtitles) { subtitle in
                    SubtitleWordSelectionView(
                        subtitle: subtitle,
                        selectedWords: $selectedWords
                    )
                    .padding(.horizontal, 16)
                }
                
                // 底部间距
                Color.clear.frame(height: 80)
            }
            .padding(.top, 16)
        }
    }
    
    // 选择操作栏
    private var selectionActionBar: some View {
        VStack(spacing: 0) {
            Divider()
            
            HStack(spacing: 12) {
                Button("返回") {
                    currentStep = .modeSelection
                    selectedWords.removeAll()
                }
                .font(.system(size: 17))
                .foregroundColor(.secondary)
                .frame(maxWidth: .infinity)
                .frame(height: 50)
                .background(Color(.systemGray6))
                .cornerRadius(12)
                
                Button("开始解析") {
                    startSelectiveAnalysis()
                }
                .font(.system(size: 17, weight: .medium))
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 50)
                .background(selectedWords.isEmpty ? Color.gray : Color.accentColor)
                .cornerRadius(12)
                .disabled(selectedWords.isEmpty)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .background(Color(.systemBackground))
    }
    
    // MARK: - 分析中状态
    private var analyzingView: some View {
        VStack(spacing: 24) {
            Spacer()
            
            // 根据分析状态显示不同的视图
            Group {
                switch playerService.vocabularyAnalysisState {
                case .partialCompleted(_, let currentSegment, let totalSegments):
                    // 分段进度显示
                    VStack(spacing: 16) {
                        // 进度环
                        ZStack {
                            Circle()
                                .stroke(Color.gray.opacity(0.3), lineWidth: 4)
                                .frame(width: 80, height: 80)
                            
                            Circle()
                                .trim(from: 0, to: CGFloat(currentSegment) / CGFloat(totalSegments))
                                .stroke(Color.accentColor, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                                .frame(width: 80, height: 80)
                                .rotationEffect(.degrees(-90))
                                .animation(.easeInOut(duration: 0.5), value: currentSegment)
                            
                            VStack(spacing: 2) {
                                Text("\(currentSegment)")
                                    .font(.title2)
                                    .fontWeight(.bold)
                                    .foregroundColor(.accentColor)
                                Text("/\(totalSegments)")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                        
                        // 详细进度条
                        VStack(spacing: 8) {
                            ProgressView(value: Double(currentSegment), total: Double(totalSegments))
                                .progressViewStyle(LinearProgressViewStyle(tint: .accentColor))
                                .frame(width: 250)
                            
                            Text("每1000词为一段，正在处理第 \(currentSegment) 段")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                default:
                    // 默认加载动画
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
                }
            }
            
            VStack(spacing: 8) {
                Text(analyzingStatusText)
                    .font(.headline)
                    .foregroundColor(.primary)
                
                Text(analyzingSubtitleText)
                    .font(.body)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }
            
            // 在分段解析时显示 "查看已解析结果" 按钮
            if case .partialCompleted(let vocabulary, _, _) = playerService.vocabularyAnalysisState,
               !vocabulary.isEmpty {
                Button {
                    // 切换到完成状态，显示当前已解析的结果
                    analysisResult = vocabulary
                    currentStep = .completed
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "list.bullet")
                        Text("查看已解析的 \(vocabulary.count) 个生词")
                    }
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(.white)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 12)
                    .background(Color.accentColor)
                    .cornerRadius(10)
                }
                .animation(.easeInOut(duration: 0.3), value: vocabulary.count)
            }
            
            Spacer()
        }
    }
    
    // 动态分析状态文本
    private var analyzingStatusText: String {
        switch playerService.vocabularyAnalysisState {
        case .partialCompleted(_, let currentSegment, let totalSegments):
            return "分段解析进行中"
        default:
            return "AI正在分析中..."
        }
    }
    
    // 动态分析副标题文本
    private var analyzingSubtitleText: String {
        switch playerService.vocabularyAnalysisState {
        case .partialCompleted(let vocabulary, let currentSegment, let totalSegments):
            let progressPercent = Int((Double(currentSegment) / Double(totalSegments)) * 100)
            return "已完成 \(progressPercent)% (\(currentSegment)/\(totalSegments) 段)\n已解析出 \(vocabulary.count) 个生词，解析仍在继续..."
        default:
            return "正在准备分析文本，每1000词为一段逐步处理"
        }
    }
    
    // MARK: - 生词列表
    private func vocabularyListView(_ vocabulary: [DifficultVocabulary]) -> some View {
        ScrollView {
            LazyVStack(spacing: 12) {
                // 统计信息
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(vocabularyListTitle(for: vocabulary))
                            .font(.headline)
                            .foregroundColor(.primary)
                        
                        Text("点击单词查看详细信息")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    
                    Spacer()
                    
                    // 重新解析按钮
                    Button {
                        // 清除缓存和重置状态
                        playerService.clearVocabularyCache()
                        currentStep = .modeSelection
                        selectedWords.removeAll()
                        analysisResult.removeAll()
                        errorMessage = ""
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
                // 清除缓存和重置状态
                playerService.clearVocabularyCache()
                currentStep = .modeSelection
                selectedWords.removeAll()
                analysisResult.removeAll()
                errorMessage = ""
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
    
    // MARK: - Helper Methods
    
    // 初始化视图状态
    private func initializeViewState() {
        print("🔍 [VocabularyAnalysisView] 视图出现，初始化状态")
        
        // 检查是否有缓存的解析结果
        if playerService.hasCachedVocabularyResult() {
            let cachedResult = playerService.getCachedVocabularyResult()
            print("🔍 [VocabularyAnalysisView] 发现缓存结果，直接显示，生词数量: \(cachedResult.count)")
            
            analysisResult = cachedResult
            currentStep = .completed
            playerService.vocabularyAnalysisState = .completed(cachedResult)
            return
        }
        
        // 检查当前解析状态
        switch playerService.vocabularyAnalysisState {
        case .completed(let vocabulary):
            if !vocabulary.isEmpty && analysisResult.isEmpty {
                print("🔍 [VocabularyAnalysisView] 检测到已完成的解析状态，加载结果")
                analysisResult = vocabulary
                currentStep = .completed
            }
        case .partialCompleted(let vocabulary, _, _):
            if !vocabulary.isEmpty {
                print("🔍 [VocabularyAnalysisView] 检测到部分完成状态，切换到分析中")
                analysisResult = vocabulary
                currentStep = .analyzing
            }
        case .analyzing:
            print("🔍 [VocabularyAnalysisView] 检测到正在分析状态")
            currentStep = .analyzing
        case .failed(let error):
            if !error.isEmpty && errorMessage.isEmpty {
                print("🔍 [VocabularyAnalysisView] 检测到失败状态：\(error)")
                errorMessage = error
                currentStep = .failed
            }
        case .idle:
            print("🔍 [VocabularyAnalysisView] 无缓存结果，显示模式选择")
            currentStep = .modeSelection
        }
    }
    
    // 生词列表标题（支持分段解析信息）
    private func vocabularyListTitle(for vocabulary: [DifficultVocabulary]) -> String {
        switch playerService.vocabularyAnalysisState {
        case .partialCompleted(_, let currentSegment, let totalSegments):
            return "共解析 \(vocabulary.count) 个生词（第 \(currentSegment)/\(totalSegments) 段）"
        case .completed:
            return "共解析 \(vocabulary.count) 个生词（解析完成）"
        default:
            return "共解析 \(vocabulary.count) 个生词"
        }
    }
    
    private func selectAllWords() {
        var allWords: Set<String> = []
        for subtitle in playerService.currentSubtitles {
            let words = subtitle.text.components(separatedBy: .whitespacesAndNewlines)
                .map { $0.trimmingCharacters(in: .punctuationCharacters) }
                .filter { !$0.isEmpty && $0.rangeOfCharacter(from: .letters) != nil }
            allWords.formUnion(words)
        }
        selectedWords = allWords
    }
    
    private func startFullTextAnalysis() {
        currentStep = .analyzing
        Task {
            await performFullTextAnalysis()
        }
    }
    
    private func startSelectiveAnalysis() {
        currentStep = .analyzing
        Task {
            await performSelectiveAnalysis()
        }
    }
    
    @MainActor
    private func performFullTextAnalysis() async {
        // 使用现有的全文解析逻辑
        await playerService.analyzeVocabulary()
        
        // 定期检查分析状态直到完成
        while true {
            switch playerService.vocabularyAnalysisState {
            case .partialCompleted(let vocabulary, _, _):
                // 部分完成，立即更新结果并显示
                analysisResult = vocabulary
                currentStep = .completed
                // 继续等待完全完成，但用户已经可以看到部分结果
                try? await Task.sleep(nanoseconds: 300_000_000) // 减少到0.3秒，更快响应
                continue
            case .completed(let vocabulary):
                analysisResult = vocabulary
                currentStep = .completed
                return
            case .failed(let error):
                errorMessage = error
                currentStep = .failed
                return
            case .analyzing:
                // 继续等待
                try? await Task.sleep(nanoseconds: 300_000_000) // 减少到0.3秒
                continue
            case .idle:
                // 如果还是idle状态，说明出现了问题
                errorMessage = "分析状态异常，请重试"
                currentStep = .failed
                return
            }
        }
    }
    
    @MainActor
    private func performSelectiveAnalysis() async {
        guard !selectedWords.isEmpty else {
            errorMessage = "请选择要解析的单词"
            currentStep = .failed
            return
        }
        
        // 调用PodcastPlayerService中的选择解析方法
        await playerService.analyzeSelectedWords(selectedWords)
        
        // 定期检查分析状态直到完成
        while true {
            switch playerService.vocabularyAnalysisState {
            case .partialCompleted(let vocabulary, _, _):
                // 选择解析模式不应该出现部分完成，直接当作完成处理
                analysisResult = vocabulary
                currentStep = .completed
                try? await Task.sleep(nanoseconds: 500_000_000) // 0.5秒
                continue
            case .completed(let vocabulary):
                analysisResult = vocabulary
                currentStep = .completed
                return
            case .failed(let error):
                errorMessage = error
                currentStep = .failed
                return
            case .analyzing:
                // 继续等待
                try? await Task.sleep(nanoseconds: 500_000_000) // 0.5秒
                continue
            case .idle:
                // 如果还是idle状态，说明出现了问题
                errorMessage = "分析状态异常，请重试"
                currentStep = .failed
                return
            }
        }
    }
    
    private func selectAllMarkedWords() {
        var marked: Set<String> = []
        for subtitle in playerService.currentSubtitles {
            let words = subtitle.text.components(separatedBy: .whitespacesAndNewlines)
                .map { $0.trimmingCharacters(in: .punctuationCharacters) }
                .filter { !$0.isEmpty && $0.rangeOfCharacter(from: .letters) != nil }
            for word in words {
                if PodcastPlayerService.shared.isWordMarked(word) {
                    marked.insert(word.lowercased())
                }
            }
        }
        selectedWords = marked
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

// MARK: - 字幕单词选择组件
struct SubtitleWordSelectionView: View {
    let subtitle: Subtitle
    @Binding var selectedWords: Set<String>
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // 时间标签
            HStack {
                Text(formatTime(subtitle.startTime))
                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color(.systemGray6))
                    .cornerRadius(6)
                
                Spacer()
            }
            
            // 单词流式布局
            wordFlowView
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Color(.systemBackground))
        .cornerRadius(12)
        .shadow(color: .black.opacity(0.05), radius: 4, x: 0, y: 2)
    }
    
    private var wordFlowView: some View {
        FlowLayout(spacing: 8) {
            ForEach(Array(words.enumerated()), id: \.offset) { index, word in
                wordButton(word)
            }
        }
    }
    
    private func wordButton(_ word: String) -> some View {
        let isSelected = isWordSelected(word)
        let isMarked = PodcastPlayerService.shared.isWordMarked(word)
        
        return Button {
            toggleWordSelection(word)
        } label: {
            Text(word)
                .font(.system(size: 16, weight: isMarked ? .bold : .regular))
                .foregroundColor(buttonTextColor(isSelected: isSelected, isMarked: isMarked))
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(buttonBackgroundColor(isSelected: isSelected, isMarked: isMarked))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(buttonBorderColor(isSelected: isSelected, isMarked: isMarked), lineWidth: isMarked ? 2 : 1)
                )
        }
        .buttonStyle(PlainButtonStyle())
        .scaleEffect(isSelected ? 1.05 : 1.0)
        .animation(.easeInOut(duration: 0.2), value: isSelected)
    }
    
    // 处理的单词列表（过滤标点符号等）
    private var words: [String] {
        subtitle.text.components(separatedBy: .whitespacesAndNewlines)
            .map { $0.trimmingCharacters(in: .punctuationCharacters) }
            .filter { !$0.isEmpty && $0.rangeOfCharacter(from: .letters) != nil }
    }
    
    private func isWordSelected(_ word: String) -> Bool {
        selectedWords.contains(word.lowercased())
    }
    
    private func toggleWordSelection(_ word: String) {
        let lowercaseWord = word.lowercased()
        if selectedWords.contains(lowercaseWord) {
            selectedWords.remove(lowercaseWord)
        } else {
            selectedWords.insert(lowercaseWord)
        }
        
        // 添加触觉反馈
        let impactFeedback = UIImpactFeedbackGenerator(style: .light)
        impactFeedback.impactOccurred()
    }
    
    /// 按钮文字颜色
    private func buttonTextColor(isSelected: Bool, isMarked: Bool) -> Color {
        if isSelected {
            return .white
        } else if isMarked {
            return .orange
        } else {
            return .primary
        }
    }
    
    /// 按钮背景颜色
    private func buttonBackgroundColor(isSelected: Bool, isMarked: Bool) -> Color {
        if isSelected {
            return isMarked ? Color.orange : Color.accentColor
        } else if isMarked {
            return Color.orange.opacity(0.1)
        } else {
            return Color(.systemGray6)
        }
    }
    
    /// 按钮边框颜色
    private func buttonBorderColor(isSelected: Bool, isMarked: Bool) -> Color {
        if isSelected {
            return isMarked ? Color.orange : Color.accentColor
        } else if isMarked {
            return Color.orange
        } else {
            return Color.clear
        }
    }
    
    private func formatTime(_ time: TimeInterval) -> String {
        let minutes = Int(time) / 60
        let seconds = Int(time) % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }
}

// MARK: - 流式布局组件
struct FlowLayout: Layout {
    let spacing: CGFloat
    
    init(spacing: CGFloat = 8) {
        self.spacing = spacing
    }
    
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = FlowResult(
            in: proposal.replacingUnspecifiedDimensions().width,
            subviews: subviews,
            spacing: spacing
        )
        return CGSize(width: proposal.width ?? 0, height: result.height)
    }
    
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = FlowResult(
            in: bounds.width,
            subviews: subviews,
            spacing: spacing
        )
        
        for index in subviews.indices {
            let position = result.positions[index]
            subviews[index].place(
                at: CGPoint(x: bounds.minX + position.x, y: bounds.minY + position.y),
                proposal: ProposedViewSize(result.sizes[index])
            )
        }
    }
}

// MARK: - 流式布局计算
struct FlowResult {
    let positions: [CGPoint]
    let sizes: [CGSize]
    let height: CGFloat
    
    init(in maxWidth: CGFloat, subviews: LayoutSubviews, spacing: CGFloat) {
        var positions: [CGPoint] = []
        var sizes: [CGSize] = []
        var currentRow: (offset: CGFloat, height: CGFloat) = (0, 0)
        var totalHeight: CGFloat = 0
        
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            sizes.append(size)
            
            if currentRow.offset + size.width > maxWidth && currentRow.offset > 0 {
                // 需要换行
                totalHeight += currentRow.height + spacing
                currentRow = (0, 0)
            }
            
            positions.append(CGPoint(x: currentRow.offset, y: totalHeight))
            currentRow.offset += size.width + spacing
            currentRow.height = max(currentRow.height, size.height)
        }
        
        totalHeight += currentRow.height
        
        self.positions = positions
        self.sizes = sizes
        self.height = totalHeight
    }
}

// MARK: - 预览
#Preview {
    VocabularyAnalysisView(playerService: PodcastPlayerService.shared)
} 