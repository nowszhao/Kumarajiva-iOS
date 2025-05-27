import SwiftUI
import AVFoundation

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
                
                Text("句子跟读")
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
                
                TabButton(title: "练习记录", isSelected: selectedTab == 1) {
                    // Stop any audio when switching tabs
                    AudioService.shared.stopPlayback()
                    viewModel.stopPlayback()
                    selectedTab = 1
                }
            }
            .padding(.top, 8)
            
            // Content based on selected tab
            if selectedTab == 0 {
                PracticeTabView(history: history, viewModel: viewModel)
            } else {
                RecordsTabView(viewModel: viewModel, history: history)
            }
        }
        .navigationBarHidden(true)
        .onDisappear {
            // Clean up when view disappears
            AudioService.shared.stopPlayback()
            viewModel.stopPlayback()
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
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(isSelected ? .blue : .primary)
                    .padding(.horizontal, 16)
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
                            .padding(.vertical, 8)
                            .padding(.horizontal, 12)
                            .background(Color(.systemGray6))
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
                    .background(Color(.systemGray6).opacity(0.8))
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
