import SwiftUI
import AVFoundation

struct SpeechPracticeView: View {
    let history: History
    @StateObject private var viewModel = SpeechPracticeViewModel()
    @State private var selectedTab = 0
    @Environment(\.presentationMode) var presentationMode
    
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
                
                Text("口语练习室")
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
                TabButton(title: "口语练习", isSelected: selectedTab == 0) {
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

// Practice tab content
struct PracticeTabView: View {
    let history: History
    @ObservedObject var viewModel: SpeechPracticeViewModel
    @State private var isExamplePlaying = false
    @State private var showScoreAlert = false
    @State private var isLongPressing = false
    @State private var dragOffset = CGSize.zero
    @State private var isCompleting = false
    @State private var showCancelAlert = false
    
    private var exampleToShow: String {
        if let method = history.memoryMethod, !method.isEmpty {
            return method
        } else if !history.examples.isEmpty {
            return history.examples[0]
        }
        return "No example available."
    }
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Example section
                VStack(alignment: .leading, spacing: 10) {
                    HStack(alignment: .center) {
                        // Word with pronunciation
                        VStack(alignment: .leading, spacing: 2) {
                            Text(history.word)
                                .font(.system(size: 22, weight: .semibold))
                                .foregroundColor(.primary)
                            
                            if let pronunciation = getPronunciation(history.pronunciation) {
                                Text(pronunciation)
                                    .font(.system(size: 14))
                                    .foregroundColor(.secondary)
                            }
                        }
                        
                        Spacer()
                        
                        // Add part of speech badge
                        if let firstDef = history.definitions.first {
                            Text(firstDef.pos)
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(.secondary)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(
                                    RoundedRectangle(cornerRadius: 4)
                                        .fill(Color(.systemGray6))
                                )
                        }
                    }
                    
                    Divider()
                        .padding(.vertical, 2)
                    
                    // Definition section
                    ForEach(history.definitions.prefix(1), id: \.meaning) { definition in
                        HStack(alignment: .top, spacing: 8) {
                            Text("「解释」")
                                .font(.system(size: 14, weight: .medium))
                                .foregroundColor(.blue)
                            
                            Text("\(definition.meaning)")
                                .font(.system(size: 15))
                                .foregroundColor(.primary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    
                    // Example section
                    HStack(alignment: .top, spacing: 8) {
                        Text("「例句」")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(.blue)
                        
                        Text("\(exampleToShow)")
                            .font(.system(size: 15))
                            .foregroundColor(.primary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    
                    // Play example button
                    Button(action: {
                        isExamplePlaying.toggle()
                        if isExamplePlaying {
                            // Setup audio session properly before playing
                            let dispatchTime = DispatchTime.now() + 0.1
                            DispatchQueue.main.asyncAfter(deadline: dispatchTime) {
                                AudioService.shared.playPronunciation(word: exampleToShow, le: "en", onCompletion: {
                                    DispatchQueue.main.async {
                                        self.isExamplePlaying = false
                                    }
                                })
                            }
                        } else {
                            AudioService.shared.stopPlayback()
                        }
                    }) {
                        HStack {
                            Image(systemName: isExamplePlaying ? "stop.fill" : "play.fill")
                                .font(.system(size: 12, weight: .medium))
                            Text(isExamplePlaying ? "停止播放" : "播放例句")
                                .font(.system(size: 13, weight: .medium))
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 6)
                        .background(Color.blue.opacity(0.1))
                        .foregroundColor(.blue)
                        .cornerRadius(8)
                    }
                    .padding(.top, 4)
                }
                .padding(16)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color(.systemBackground))
                        .shadow(color: Color.black.opacity(0.08), radius: 4, x: 0, y: 1)
                )
                .padding(.horizontal)
                
                // Recording section
                VStack(spacing: 16) {
                    // Recognized text area
                    VStack(alignment: .leading, spacing: 8) {
                        Text("识别结果")
                            .font(.system(size: 15, weight: .medium))
                            .foregroundColor(.primary)
                        
                        if viewModel.wordResults.isEmpty && viewModel.recognizedText.isEmpty {
                            Text("点击录音按钮开始口语练习...")
                                .font(.system(size: 15))
                                .foregroundColor(.secondary)
                                .padding()
                                .frame(maxWidth: .infinity, minHeight: 70, alignment: .center)
                                .background(Color(.systemGray6).opacity(0.8))
                                .cornerRadius(8)
                        } else {
                            HighlightedTextView(results: viewModel.formattedRecognizedText(), viewModel: viewModel)
                                .padding()
                                .frame(maxWidth: .infinity, minHeight: 70, alignment: .leading)
                                .background(Color(.systemGray6).opacity(0.8))
                                .cornerRadius(8)
                        }
                    }
                    
                    // Recording indicator
                    if viewModel.isRecording {
                        HStack {
                            Text("录音中...")
                                .font(.system(size: 14))
                                .foregroundColor(.red)
                            
                            Spacer()
                            
                            if isLongPressing {
                                Text("向右滑动完成，其他方向放弃")
                                    .font(.system(size: 13))
                                    .foregroundColor(.secondary)
                                    .padding(.horizontal, 10)
                            }
                            
                            Spacer()
                            
                            Text(viewModel.formatRecordingTime(viewModel.recordingTime))
                                .font(.system(size: 14, weight: .medium))
                                .monospacedDigit()
                        }
                    }
                    
                    // Legend
                    VStack(alignment: .center, spacing: 6) {
                        Text("颜色说明")
                            .font(.system(size: 13))
                            .foregroundColor(.secondary)
                        
                        HStack(spacing: 16) {
                            LegendItem(color: .green, text: "匹配")
                            LegendItem(color: .red, text: "缺失")
                            LegendItem(color: .gray, text: "多余")
                        }
                    }
                    .padding(.top, 4)
                    
                    // Recording button with gesture
                    ZStack {
                        Circle()
                            .fill(isLongPressing ? (isCompleting ? Color.green : Color.red) : Color.blue)
                            .frame(width: 64, height: 64)
                            .shadow(color: Color.black.opacity(0.15), radius: 3, x: 0, y: 1)
                        
                        if isLongPressing {
                            if isCompleting {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 26))
                                    .foregroundColor(.white)
                            } else {
                                RoundedRectangle(cornerRadius: 4)
                                    .fill(Color.white)
                                    .frame(width: 20, height: 20)
                            }
                        } else {
                            Image(systemName: "mic.fill")
                                .font(.system(size: 26))
                                .foregroundColor(.white)
                        }
                        
                        // 添加向右滑动箭头指示(当录音开始时)
                        if isLongPressing && !isCompleting {
                            HStack {
                                Spacer()
                                Image(systemName: "arrow.right")
                                    .font(.system(size: 20))
                                    .foregroundColor(.white)
                                    .offset(x: 40)
                            }
                            .frame(width: 120)
                        }
                    }
                    .offset(dragOffset)
                    .gesture(
                        DragGesture()
                            .onChanged { gesture in
                                if isLongPressing {
                                    // 只允许水平方向的滑动
                                    let horizontalDrag = CGSize(width: gesture.translation.width, height: 0)
                                    dragOffset = horizontalDrag
                                    
                                    // 如果向右滑动超过50，则标记为完成状态
                                    isCompleting = gesture.translation.width > 50
                                }
                            }
                            .onEnded { _ in
                                if isLongPressing {
                                    if isCompleting {
                                        // 向右滑动完成录音并保存
                                        viewModel.stopRecording(word: history.word, example: exampleToShow, shouldSave: true)
                                        showScoreAlert = true
                                    } else {
                                        // 其他方向滑动或就地松手，取消录音
                                        viewModel.stopRecording(word: history.word, example: exampleToShow, shouldSave: false)
                                        showCancelAlert = true
                                    }
                                    
                                    // 重置状态
                                    isLongPressing = false
                                    dragOffset = .zero
                                    isCompleting = false
                                }
                            }
                    )
                    .simultaneousGesture(
                        LongPressGesture(minimumDuration: 0.3)
                            .onEnded { _ in
                                if !isLongPressing {
                                    isLongPressing = true
                                    dragOffset = .zero
                                    isCompleting = false
                                    viewModel.startRecording()
                                }
                            }
                    )
                    .padding(.vertical, 12)
                }
                .padding(16)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color(.systemBackground))
                        .shadow(color: Color.black.opacity(0.08), radius: 4, x: 0, y: 1)
                )
                .padding(.horizontal)
                .padding(.bottom, 30)
            }
            .padding(.vertical)
        }
        .alert(isPresented: $showScoreAlert) {
            Alert(
                title: Text("发音评分"),
                message: Text("您的发音得分: \(viewModel.currentScore)"),
                dismissButton: .default(Text("确定"))
            )
        }
//        .alert(isPresented: $showCancelAlert) {
//            Alert(
//                title: Text("已取消录音"),
//                message: Text("您已放弃本次录音"),
//                dismissButton: .default(Text("确定"))
//            )

//        }
        .onDisappear {
            // Stop playing example when tab disappears
            if isExamplePlaying {
                AudioService.shared.stopPlayback()
                isExamplePlaying = false
            }
        }
    }
    
    private func getPronunciation(_ pronunciation: History.Pronunciation?) -> String? {
        guard let pronunciation = pronunciation else { return nil }
        return pronunciation.American.isEmpty ? pronunciation.British : pronunciation.American
    }
}

// Records tab content
struct RecordsTabView: View {
    @ObservedObject var viewModel: SpeechPracticeViewModel
    @State private var playingRecordID: UUID? = nil
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
        .onDisappear {
            // Stop any playing recordings when tab disappears
            if playingRecordID != nil {
                viewModel.stopPlayback()
                playingRecordID = nil
            }
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
