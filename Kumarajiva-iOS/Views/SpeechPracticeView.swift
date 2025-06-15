import SwiftUI
import AVFoundation
import UIKit

struct SpeechPracticeView: View {
    let history: History
    @StateObject private var viewModel = SpeechPracticeViewModel()
    @State private var selectedTab = 0
    @Environment(\.presentationMode) var presentationMode
    
    // New initializer for ReviewHistoryItem
    init(reviewHistory: ReviewHistoryItem) {
        // Convert ReviewHistoryItem to History format for compatibility
        self.history = History(
            word: reviewHistory.word,
            definitions: reviewHistory.definitions,
            examples: reviewHistory.examples,
            lastReviewDate: reviewHistory.lastReviewDate,
            reviewCount: reviewHistory.reviewCount,
            correctCount: reviewHistory.correctCount,
            pronunciation: reviewHistory.pronunciation.map { pronunciation in
                History.Pronunciation(
                    American: pronunciation.American,
                    British: pronunciation.British
                )
            },
            memoryMethod: reviewHistory.memoryMethod,
            mastered: reviewHistory.mastered,
            timestamp: reviewHistory.timestamp
        )
    }
    
    // Original initializer for History
    init(history: History) {
        self.history = history
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Navigation bar with back button
            HStack {
                Button(action: {
                    // Stop any audio before dismissing
                    AudioService.shared.stopPlayback()
                    viewModel.stopPlayback()
                    presentationMode.wrappedValue.dismiss()
                }) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 16, weight: .semibold))
                }
                
                Spacer()
                
                Text("单词深度解析")
                    .font(.headline)
                
                Spacer()
                
                // Empty view for balanced layout
                Image(systemName: "chevron.left")
                    .font(.system(size: 16, weight: .semibold))
                    .opacity(0)
            }
            .padding(.horizontal)
            .padding(.vertical, 12)
            
            // Custom segmented control
            HStack(spacing: 0) {
                TabButton(title: "跟读练习", isSelected: selectedTab == 0) {
                    // Stop any audio when switching tabs
                    AudioService.shared.stopPlayback()
                    viewModel.stopPlayback()
                    selectedTab = 0
                }
                
                TabButton(title: "智能解析", isSelected: selectedTab == 3) {
                    // Stop any audio when switching tabs
                    AudioService.shared.stopPlayback()
                    viewModel.stopPlayback()
                    selectedTab = 3
                    // 检查是否有缓存的解析结果
                    if case .notAnalyzed = viewModel.analysisState {
                        // 检查缓存
                        if WordAnalysisService.shared.hasAnalysis(for: history.word) {
                            if let cachedAnalysis = WordAnalysisService.shared.getAnalysis(for: history.word) {
                                viewModel.analysisState = .analyzed(cachedAnalysis)
                            }
                        }
                    }
                }
                
                TabButton(title: "练习记录", isSelected: selectedTab == 1) {
                    // Stop any audio when switching tabs
                    AudioService.shared.stopPlayback()
                    viewModel.stopPlayback()
                    selectedTab = 1
                }
                
                TabButton(title: "学习记录", isSelected: selectedTab == 2) {
                    // Stop any audio when switching tabs
                    AudioService.shared.stopPlayback()
                    viewModel.stopPlayback()
                    selectedTab = 2
                    // 获取学习记录
                    viewModel.fetchStudyRecords(for: history.word)
                }
            }
            .padding(.top, 8)
            
            // Content based on selected tab
            if selectedTab == 0 {
                PracticeTabView(history: history, viewModel: viewModel)
            } else if selectedTab == 1 {
                RecordsTabView(viewModel: viewModel, history: history)
            } else if selectedTab == 2 {
                StudyRecordsTabView(viewModel: viewModel, history: history)
            } else {
                IntelligentAnalysisTabView(viewModel: viewModel, history: history)
            }
        }
        .navigationBarHidden(true)
        .onDisappear {
            // Clean up when view disappears
            AudioService.shared.stopPlayback()
            viewModel.stopPlayback()
            // 清空解析状态（可选）
            // viewModel.clearAnalysisState()
        }
    }
}

// Tab button component
struct TabButton: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                Text(title)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(isSelected ? .blue : .primary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 8)
                
                Rectangle()
                    .fill(isSelected ? Color.blue : Color.clear)
                    .frame(height: 2)
            }
        }
        .frame(maxWidth: .infinity)
    }
}

// Records tab content
struct RecordsTabView: View {
    @ObservedObject var viewModel: SpeechPracticeViewModel
    @State private var playingRecordID: UUID? = nil
    @State private var showingDeleteConfirmation = false
    let history: History
    
    // 过滤当前单词的练习记录
    private var filteredRecords: [SpeechPracticeRecord] {
        return viewModel.records.filter { $0.word == history.word }
    }
    
    var body: some View {
        Group {
            if filteredRecords.isEmpty {
                VStack(spacing: 16) {
                    Image(systemName: "waveform")
                        .font(.system(size: 48))
                        .foregroundColor(.secondary)
                    Text("暂无该单词的练习记录")
                        .font(.headline)
                        .foregroundColor(.secondary)
                }
                .frame(maxHeight: .infinity)
            } else {
                VStack(spacing: 0) {
                    // 清空按钮
                    HStack {
                        Spacer()
                        Button(action: {
                            showingDeleteConfirmation = true
                        }) {
                            HStack(spacing: 4) {
                                Image(systemName: "trash")
                                    .font(.system(size: 14))
                                Text("清空记录")
                                    .font(.system(size: 14))
                            }
                            .foregroundColor(.red)
                                                                     .padding(.vertical, 6)
                                         .padding(.horizontal, 10)
                            .background(Color(UIColor.systemGray6))
                            .cornerRadius(16)
                        }
                        .padding(.trailing, 16)
                        .padding(.top, 8)
                        .padding(.bottom, 4)
                    }
                    
                    List {
                        ForEach(filteredRecords) { record in
                            RecordItemView(
                                record: record,
                                isPlaying: playingRecordID == record.id,
                                onPlay: {
                                    if playingRecordID == record.id {
                                        playingRecordID = nil
                                        viewModel.stopPlayback()
                                    } else {
                                        playingRecordID = record.id
                                        viewModel.playRecording(at: record.audioURL) {
                                            // Callback when playback finishes
                                            playingRecordID = nil
                                        }
                                    }
                                }
                            )
                            .swipeActions(edge: .trailing) {
                                Button(role: .destructive) {
                                    viewModel.deleteRecord(id: record.id)
                                    if playingRecordID == record.id {
                                        playingRecordID = nil
                                    }
                                } label: {
                                    Label("删除", systemImage: "trash")
                                }
                            }
                        }
                    }
                    .listStyle(InsetGroupedListStyle())
                }
            }
        }
        .onDisappear {
            // Stop any playing recordings when tab disappears
            if playingRecordID != nil {
                viewModel.stopPlayback()
                playingRecordID = nil
            }
        }
        .alert("确认删除", isPresented: $showingDeleteConfirmation) {
            Button("取消", role: .cancel) { }
            Button("删除", role: .destructive) {
                // 停止任何正在播放的录音
                if playingRecordID != nil {
                    viewModel.stopPlayback()
                    playingRecordID = nil
                }
                // 执行删除操作
                viewModel.deleteAllRecordsForWord(history.word)
            }
        } message: {
            Text("确定要删除所有关于 '\(history.word)' 的练习记录吗？此操作无法撤销。")
        }
    }
}

// Record item for the records tab
struct RecordItemView: View {
    let record: SpeechPracticeRecord
    let isPlaying: Bool
    let onPlay: () -> Void
    
    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            // Playback button
            Button(action: onPlay) {
                Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 16))
                    .foregroundColor(isPlaying ? .red : .blue)
                    .frame(width: 36, height: 36)
                    .background(Color(UIColor.systemGray6).opacity(0.8))
                    .cornerRadius(18)
            }
            
            // Record info
            VStack(alignment: .leading, spacing: 4) {
                Text(record.word)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(.primary)
                
                Text(formatDate(record.timestamp))
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            // Score badge
            Text("\(record.score)")
                .font(.system(size: 14, weight: .bold))
                .foregroundColor(.white)
                .frame(width: 32, height: 32)
                .background(scoreColor(record.score))
                .cornerRadius(16)
        }
        .padding(.vertical, 6)
    }
    
    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        return formatter.string(from: date)
    }
    
    private func scoreColor(_ score: Int) -> Color {
        if score >= 90 {
            return .green
        } else if score >= 70 {
            return .blue
        } else if score >= 50 {
            return .orange
        } else {
            return .red
        }
    }
}

// Legend item component
struct LegendItem: View {
    let color: Color
    let text: String
    
    var body: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(color)
                .frame(width: 8, height: 8)
            Text(text)
                .font(.system(size: 12))
                .foregroundColor(.secondary)
        }
    }
}

// Highlighted text view - 按行自动换行布局
struct HighlightedTextView: View {
    let results: [WordMatchResult]
    let viewModel: SpeechPracticeViewModel
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                WordWrappedText(results: results, viewModel: viewModel)
            }
        }
    }
}

// 文字自动换行组件
struct WordWrappedText: View {
    let results: [WordMatchResult]
    let viewModel: SpeechPracticeViewModel
    
    @State private var totalWidth: CGFloat = 0
    
    var body: some View {
        ZStack(alignment: .topLeading) {
            Color.clear
                .frame(height: 1)
                .readSize { size in
                    totalWidth = size.width
                }
            
            TextFlowLayout(width: totalWidth, spacing: 4) {
                ForEach(results) { result in
                    Text(result.word)
                        .font(.system(size: 15))
                        .padding(.horizontal, 3)
                        .padding(.vertical, 1)
                        .background(
                            RoundedRectangle(cornerRadius: 3)
                                .fill(viewModel.colorForMatchType(result.type).opacity(0.15))
                        )
                        .foregroundColor(viewModel.colorForMatchType(result.type))
                        .fixedSize()
                }
            }
        }
    }
}

// 文字流式布局
struct TextFlowLayout: Layout {
    var width: CGFloat
    var spacing: CGFloat
    
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let sizes = subviews.map { $0.sizeThatFits(.unspecified) }
        return arrangeSubviews(sizes: sizes, width: width)
    }
    
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let sizes = subviews.map { $0.sizeThatFits(.unspecified) }
        var origin = bounds.origin
        var lineHeight: CGFloat = 0
        
        for (index, subview) in subviews.enumerated() {
            let size = sizes[index]
            
            // 检查是否需要换行
            if index > 0 && origin.x + size.width > bounds.maxX {
                origin.x = bounds.origin.x
                origin.y += lineHeight + spacing
                lineHeight = 0
            }
            
            subview.place(at: origin, proposal: .unspecified)
            
            // 更新下一个子视图的位置和当前行高
            origin.x += size.width + spacing
            lineHeight = max(lineHeight, size.height)
        }
    }
    
    private func arrangeSubviews(sizes: [CGSize], width: CGFloat) -> CGSize {
        var result = CGSize.zero
        var lineWidth: CGFloat = 0
        var lineHeight: CGFloat = 0
        
        for size in sizes {
            if lineWidth + size.width > width && lineWidth > 0 {
                // 换行
                result.height += lineHeight + spacing
                result.width = max(result.width, lineWidth - spacing)
                lineWidth = size.width + spacing
                lineHeight = size.height
            } else {
                // 同一行
                lineWidth += size.width + spacing
                lineHeight = max(lineHeight, size.height)
            }
        }
        
        // 添加最后一行
        result.height += lineHeight
        result.width = max(result.width, lineWidth - spacing)
        
        return result
    }
}

// Flexible view for word wrapping
struct FlexibleView<Data: Collection, Content: View>: View where Data.Element: Identifiable {
    let data: Data
    let spacing: CGFloat
    let alignment: HorizontalAlignment
    let content: (Data.Element) -> Content
    
    @State private var availableWidth: CGFloat = 0
    
    var body: some View {
        ZStack(alignment: Alignment(horizontal: alignment, vertical: .center)) {
            Color.clear
                .frame(height: 1)
                .readSize { size in
                    availableWidth = size.width
                }
            
            VStack(alignment: alignment, spacing: 8) {
                ForEach(computeRows()) { row in
                    HStack(spacing: spacing) {
                        ForEach(row.items) { element in
                            content(element)
                        }
                    }
                }
            }
        }
    }
    
    private func computeRows() -> [Row] {
        var rows: [Row] = []
        var currentRow = Row(items: [])
        var remainingWidth = availableWidth
        
        for element in data {
            let text = "\(element.id)"
            // Estimated width plus spacing
            let textWidth = text.size().width + 20
            
            if remainingWidth - textWidth >= 0 {
                currentRow.items.append(element)
                remainingWidth -= (textWidth + spacing)
            } else {
                rows.append(currentRow)
                currentRow = Row(items: [element])
                remainingWidth = availableWidth - textWidth
            }
        }
        
        if !currentRow.items.isEmpty {
            rows.append(currentRow)
        }
        
        return rows
    }
    
    struct Row: Identifiable {
        let id = UUID()
        var items: [Data.Element]
    }
}

// Helper extension for measuring text
extension String {
    func size(with font: UIFont = UIFont.systemFont(ofSize: 17)) -> CGSize {
        return (self as NSString).size(withAttributes: [NSAttributedString.Key.font: font])
    }
}

// Helper view for reading size
struct SizePreferenceKey: PreferenceKey {
    static var defaultValue: CGSize = .zero
    static func reduce(value: inout CGSize, nextValue: () -> CGSize) {
        value = nextValue()
    }
}

extension View {
    func readSize(onChange: @escaping (CGSize) -> Void) -> some View {
        background(
            GeometryReader { geometryProxy in
                Color.clear
                    .preference(key: SizePreferenceKey.self, value: geometryProxy.size)
            }
        )
        .onPreferenceChange(SizePreferenceKey.self, perform: onChange)
    }
}

// ExampleSentenceView - 显示例句并高亮匹配单词
struct ExampleSentenceView: View {
    let example: String
    let recognizedResults: [WordMatchResult]
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            WordWrappedExampleText(example: example, recognizedResults: recognizedResults)
        }
    }
}

// 例句自动换行组件
struct WordWrappedExampleText: View {
    let example: String
    let recognizedResults: [WordMatchResult]
    
    @State private var totalWidth: CGFloat = 0
    
    var body: some View {
        ZStack(alignment: .topLeading) {
            Color.clear
                .frame(height: 1)
                .readSize { size in
                    totalWidth = size.width
                }
            
            let words = example.components(separatedBy: .whitespaces).filter { !$0.isEmpty }
            
            TextFlowLayout(width: totalWidth, spacing: 4) {
                ForEach(Array(words.enumerated()), id: \.offset) { index, word in
                    let isMatched = isWordMatched(word)
                    Text(word)
                        .font(.system(size: 15))
                        .padding(.horizontal, 3)
                        .padding(.vertical, 1)
                        .foregroundColor(isMatched ? .green : .secondary)
                        .fixedSize()
                }
            }
        }
    }
    
    // 检查单词是否在识别结果中匹配
    private func isWordMatched(_ word: String) -> Bool {
        let normalizedWord = word.lowercased().trimmingCharacters(in: .punctuationCharacters)
        return recognizedResults.contains { result in
            result.type == .matched && 
            result.word.lowercased().trimmingCharacters(in: .punctuationCharacters) == normalizedWord
        }
    }
}

// MARK: - Study Records Tab
// 学习记录标签页内容
struct StudyRecordsTabView: View {
    @ObservedObject var viewModel: SpeechPracticeViewModel
    let history: History
    
    // 计算带间隔时间的记录列表
    private var recordsWithInterval: [StudyRecordWithInterval] {
        let sortedRecords = viewModel.studyRecords.sorted { $0.reviewDate > $1.reviewDate }
        
        return sortedRecords.enumerated().map { index, record in
            let previousRecord = index < sortedRecords.count - 1 ? sortedRecords[index + 1] : nil
            let intervalText = record.intervalSince(previousRecord)
            return StudyRecordWithInterval(record: record, intervalText: intervalText)
        }
    }
    
    var body: some View {
        VStack(spacing: 0) {
            if viewModel.isLoadingStudyRecords {
                // 加载状态
                VStack(spacing: 16) {
                    ProgressView()
                        .scaleEffect(1.2)
                    Text("正在加载学习记录...")
                        .font(.headline)
                        .foregroundColor(.secondary)
                }
                .frame(maxHeight: .infinity)
            } else if let error = viewModel.studyRecordsError {
                // 错误状态
                VStack(spacing: 16) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.system(size: 48))
                        .foregroundColor(.red)
                    Text("加载失败")
                        .font(.headline)
                        .foregroundColor(.secondary)
                    Text(error)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                    
                    Button("重试") {
                        viewModel.fetchStudyRecords(for: history.word)
                    }
                    .buttonStyle(.borderedProminent)
                }
                .padding()
                .frame(maxHeight: .infinity)
            } else if viewModel.studyRecords.isEmpty {
                // 空状态
                VStack(spacing: 16) {
                    Image(systemName: "doc.text")
                        .font(.system(size: 48))
                        .foregroundColor(.secondary)
                    Text("暂无该单词的学习记录")
                        .font(.headline)
                        .foregroundColor(.secondary)
                    Text("开始学习单词后，这里会显示历史记录")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxHeight: .infinity)
            } else {
                // 有数据状态
                VStack(spacing: 0) {
                    // 统计信息头部
                    StudyRecordsHeaderView(studyRecords: viewModel.studyRecords)
                    
                    // 记录列表
                    List {
                        ForEach(recordsWithInterval, id: \.id) { recordWithInterval in
                            StudyRecordItemView(recordWithInterval: recordWithInterval)
                        }
                    }
                    .listStyle(InsetGroupedListStyle())
                }
            }
        }
        .onDisappear {
            // 当视图消失时清理数据
            viewModel.clearStudyRecords()
        }
    }
}

// 学习记录头部统计信息
struct StudyRecordsHeaderView: View {
    let studyRecords: [StudyRecord]
    
    private var correctCount: Int {
        studyRecords.filter { $0.isCorrect }.count
    }
    
    private var totalCount: Int {
        studyRecords.count
    }
    
    private var accuracy: Double {
        guard totalCount > 0 else { return 0 }
        return Double(correctCount) / Double(totalCount) * 100
    }
    
    var body: some View {
        VStack(spacing: 12) {
            // 准确率显示
            HStack(spacing: 20) {
                VStack(spacing: 4) {
                    Text("\(correctCount)")
                        .font(.title2)
                        .fontWeight(.bold)
                        .foregroundColor(.green)
                    Text("正确")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                VStack(spacing: 4) {
                    Text("\(totalCount - correctCount)")
                        .font(.title2)
                        .fontWeight(.bold)
                        .foregroundColor(.red)
                    Text("错误")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                VStack(spacing: 4) {
                    Text(String(format: "%.1f%%", accuracy))
                        .font(.title2)
                        .fontWeight(.bold)
                        .foregroundColor(.blue)
                    Text("准确率")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .padding(.vertical, 12)
            
            // 图例
            HStack(spacing: 16) {
                LegendItem(color: .green, text: "正确")
                LegendItem(color: .red, text: "错误")
                Spacer()
                Text("共 \(totalCount) 次学习")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, 16)
        }
        .background(Color(UIColor.systemBackground))
        .cornerRadius(12)
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .padding(.bottom, 4)
    }
}

// 学习记录条目
struct StudyRecordItemView: View {
    let recordWithInterval: StudyRecordWithInterval
    
    var body: some View {
        HStack(spacing: 12) {
            // 结果图标
            Image(systemName: recordWithInterval.record.isCorrect ? "checkmark.circle.fill" : "xmark.circle.fill")
                .font(.system(size: 20))
                .foregroundColor(recordWithInterval.record.isCorrect ? .green : .red)
            
            // 日期和间隔信息
            VStack(alignment: .leading, spacing: 2) {
                Text(recordWithInterval.record.formattedDate)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(.primary)
                
                HStack(spacing: 8) {
                    // 结果文本
                    Text(recordWithInterval.record.isCorrect ? "回答正确" : "回答错误")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                    
                    // 间隔时间（如果有）
                    if let intervalText = recordWithInterval.intervalText {
                        Text("•")
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                        
                        Text("间隔 \(intervalText)")
                            .font(.system(size: 12))
                            .foregroundColor(.blue)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.blue.opacity(0.1))
                            .cornerRadius(4)
                    }
                }
            }
            
            Spacer()
            
            // 结果标签
            Text(recordWithInterval.record.isCorrect ? "✓" : "✗")
                .font(.system(size: 16, weight: .bold))
                .foregroundColor(.white)
                .frame(width: 28, height: 28)
                .background(recordWithInterval.record.isCorrect ? .green : .red)
                .cornerRadius(14)
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Intelligent Analysis Tab
/// 智能解析标签页内容
struct IntelligentAnalysisTabView: View {
    @ObservedObject var viewModel: SpeechPracticeViewModel
    let history: History
    
    var body: some View {
        VStack(spacing: 0) {
            switch viewModel.analysisState {
            case .notAnalyzed:
                NotAnalyzedView(word: history.word) {
                    viewModel.fetchWordAnalysis(for: history.word)
                }
                
            case .analyzing:
                AnalyzingView()
                
            case .analyzed(let analysis):
                AnalysisResultView(analysis: analysis) {
                    viewModel.fetchWordAnalysis(for: history.word, forceRefresh: true)
                }
                
            case .failed(let error):
                AnalysisErrorView(error: error) {
                    viewModel.fetchWordAnalysis(for: history.word)
                }
            }
        }
        .onDisappear {
            // 可选择是否清空状态
            // viewModel.clearAnalysisState()
        }
    }
}

// MARK: - Analysis States Views

/// 未解析状态视图
struct NotAnalyzedView: View {
    let word: String
    let onAnalyze: () -> Void
    
    var body: some View {
        VStack(spacing: 24) {
            Spacer()
            
            // 图标和说明
            VStack(spacing: 16) {
                Image(systemName: "brain.head.profile")
                    .font(.system(size: 56))
                    .foregroundColor(.blue)
                
                Text("智能解析")
                    .font(.title2)
                    .fontWeight(.semibold)
                    .foregroundColor(.primary)
                
                Text("通过AI分析单词的词根拆解、记忆方法\n场景例句和同义词辨析")
                    .font(.body)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .lineSpacing(2)
            }
            
            Spacer()
            
            // 解析按钮
            Button(action: onAnalyze) {
                HStack(spacing: 12) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 18, weight: .medium))
                    Text("开始解析 \"\(word)\"")
                        .font(.system(size: 18, weight: .semibold))
                }
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 56)
                .background(
                    LinearGradient(
                        colors: [Color.blue, Color.blue.opacity(0.8)],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .cornerRadius(16)
                .shadow(color: Color.blue.opacity(0.3), radius: 8, x: 0, y: 4)
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 32)
        }
    }
}

/// 解析中状态视图
struct AnalyzingView: View {
    @State private var dots = ""
    
    var body: some View {
        VStack(spacing: 24) {
            Spacer()
            
            // 加载动画
            VStack(spacing: 20) {
                ProgressView()
                    .scaleEffect(1.5)
                    .tint(.blue)
                
                Text("AI正在解析中")
                    .font(.headline)
                    .foregroundColor(.primary)
                
                Text("正在分析单词的词根结构、记忆方法和使用场景...")
                    .font(.body)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .lineSpacing(2)
            }
            
            Spacer()
        }
        .onAppear {
            startDotAnimation()
        }
    }
    
    private func startDotAnimation() {
        Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { timer in
            dots = dots.count >= 3 ? "" : dots + "."
        }
    }
}

/// 解析结果视图
struct AnalysisResultView: View {
    let analysis: WordAnalysis
    let onReanalyze: () -> Void
    
    var body: some View {
        ScrollView {
                         VStack(alignment: .leading, spacing: 16) {
                // 头部 - 单词和重新解析按钮
                HStack {
                                         VStack(alignment: .leading, spacing: 4) {
                         Text(analysis.word)
                             .font(.title2)
                             .fontWeight(.bold)
                             .foregroundColor(.primary)
                         
                         Text("智能解析结果")
                             .font(.caption)
                             .foregroundColor(.secondary)
                     }
                    
                    Spacer()
                    
                    Button(action: onReanalyze) {
                                                 HStack(spacing: 4) {
                             Image(systemName: "arrow.clockwise")
                                 .font(.system(size: 11))
                             Text("重新解析")
                                 .font(.system(size: 11, weight: .medium))
                         }
                        .foregroundColor(.blue)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Color.blue.opacity(0.1))
                        .cornerRadius(12)
                    }
                }
                .padding(.horizontal, 20)
                                 .padding(.top, 16)
                 
                 VStack(spacing: 14) {
                     // 基本信息卡片
                    AnalysisCardView(
                        title: "基本信息",
                        icon: "textformat.abc",
                        color: .blue
                    ) {
                                                 VStack(alignment: .leading, spacing: 10) {
                             // 音标
                             HStack(spacing: 16) {
                                                                 VStack(alignment: .leading, spacing: 4) {
                                     Text("英式")
                                         .font(.caption)
                                         .foregroundColor(.secondary)
                                     Text(analysis.basicInfo.phoneticNotation.british)
                                         .font(.system(size: 14).monospaced())
                                         .foregroundColor(.primary)
                                 }
                                 
                                 VStack(alignment: .leading, spacing: 4) {
                                     Text("美式")
                                         .font(.caption)
                                         .foregroundColor(.secondary)
                                     Text(analysis.basicInfo.phoneticNotation.american)
                                         .font(.system(size: 14).monospaced())
                                         .foregroundColor(.primary)
                                 }
                                
                                Spacer()
                            }
                            
                            Divider()
                            
                            // 释义
                                                         VStack(alignment: .leading, spacing: 4) {
                                 Text("释义")
                                     .font(.caption)
                                     .foregroundColor(.secondary)
                                 Text(analysis.basicInfo.annotation)
                                     .font(.subheadline)
                                     .foregroundColor(.primary)
                             }
                        }
                    }
                    
                    // 记忆方法卡片
                    AnalysisCardView(
                        title: "记忆方法",
                        icon: "brain.head.profile",
                        color: .green
                    ) {
                                                 Text(analysis.splitAssociationMethod)
                             .font(.subheadline)
                             .foregroundColor(.primary)
                             .lineSpacing(3)
                    }
                    
                    // 场景记忆卡片
                    AnalysisCardView(
                        title: "场景记忆",
                        icon: "bubble.left.and.bubble.right",
                        color: .orange
                    ) {
                                                 VStack(alignment: .leading, spacing: 10) {
                             ForEach(Array(analysis.sceneMemory.enumerated()), id: \.element.id) { index, scene in
                                VStack(alignment: .leading, spacing: 6) {
                                    HStack {
                                        Text("场景 \(index + 1)")
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                        Spacer()
                                    }
                                    
                                                                         Text(scene.scene)
                                         .font(.subheadline)
                                         .foregroundColor(.primary)
                                                                                  .lineSpacing(2)
                                         .padding(.vertical, 6)
                                         .padding(.horizontal, 10)
                                        .background(Color(UIColor.systemGray6).opacity(0.5))
                                        .cornerRadius(8)
                                }
                                
                                if index < analysis.sceneMemory.count - 1 {
                                    Divider()
                                }
                            }
                        }
                    }
                    
                    // 同义词辨析卡片
                    AnalysisCardView(
                        title: "同义词辨析",
                        icon: "arrow.left.arrow.right",
                        color: .purple
                    ) {
                                                 VStack(alignment: .leading, spacing: 10) {
                             ForEach(Array(analysis.synonymPreciseGuidance.enumerated()), id: \.element.id) { index, guidance in
                                VStack(alignment: .leading, spacing: 8) {
                                                                         HStack {
                                         Text(guidance.synonym)
                                             .font(.system(size: 15, weight: .semibold))
                                             .foregroundColor(.primary)
                                         Spacer()
                                     }
                                     
                                     Text(guidance.explanation)
                                         .font(.subheadline)
                                         .foregroundColor(.secondary)
                                         .lineSpacing(2)
                                }
                                                                 .padding(.vertical, 6)
                                 .padding(.horizontal, 10)
                                .background(Color(UIColor.systemGray6).opacity(0.3))
                                .cornerRadius(8)
                                
                                if index < analysis.synonymPreciseGuidance.count - 1 {
                                    Divider()
                                }
                            }
                        }
                    }
                }
                                 .padding(.horizontal, 16)
                 .padding(.bottom, 20)
            }
        }
    }
}

/// 解析错误视图
struct AnalysisErrorView: View {
    let error: String
    let onRetry: () -> Void
    
    var body: some View {
        VStack(spacing: 24) {
            Spacer()
            
            VStack(spacing: 16) {
                Image(systemName: "exclamationmark.triangle")
                    .font(.system(size: 48))
                    .foregroundColor(.red)
                
                Text("解析失败")
                    .font(.headline)
                    .foregroundColor(.primary)
                
                Text(error)
                    .font(.body)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .lineSpacing(2)
            }
            
            Spacer()
            
            Button(action: onRetry) {
                HStack(spacing: 8) {
                    Image(systemName: "arrow.clockwise")
                    Text("重试")
                }
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(.white)
                .frame(width: 120, height: 44)
                .background(Color.blue)
                .cornerRadius(12)
            }
            .padding(.bottom, 32)
        }
    }
}

/// 解析卡片视图
struct AnalysisCardView<Content: View>: View {
    let title: String
    let icon: String
    let color: Color
    let content: Content
    
    init(title: String, icon: String, color: Color, @ViewBuilder content: () -> Content) {
        self.title = title
        self.icon = icon
        self.color = color
        self.content = content()
    }
    
    var body: some View {
                 VStack(alignment: .leading, spacing: 10) {
             // 卡片标题
             HStack(spacing: 8) {
                 Image(systemName: icon)
                     .font(.system(size: 14, weight: .medium))
                     .foregroundColor(color)
                 
                 Text(title)
                     .font(.system(size: 15, weight: .semibold))
                     .foregroundColor(.primary)
                 
                 Spacer()
             }
             
             Divider()
             
             // 卡片内容
             content
         }
         .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(UIColor.systemBackground))
                .shadow(color: Color.black.opacity(0.05), radius: 2, x: 0, y: 1)
        )
    }
}
