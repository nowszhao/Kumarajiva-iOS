import SwiftUI

struct HistoryView: View {
    @StateObject private var viewModel = HistoryViewModel()
    @State private var selectedFilter: HistoryFilter = .today
    @State private var isPlayingBatch = false
    @State private var selectedWordTypes: Set<WordTypeFilter> = [.all]
    @State private var currentPlayingWord: String? = nil
    @State private var showingFilterSheet = false
    @State private var selectedHistory: ReviewHistoryItem? = nil
    @State private var showingSpeechPractice = false
    @AppStorage("lastPlaybackIndex") private var lastPlaybackIndex: Int = 0
    
    private var filterTypeText: String {
        if selectedWordTypes.count == 1 && selectedWordTypes.contains(.all) {
            return "全部"
        }
        return "已选择\(selectedWordTypes.count)项"
    }
    
    private var filteredHistories: [ReviewHistoryItem] {
        viewModel.histories.filter { history in
            if selectedWordTypes.contains(.all) {
                return true
            }
            return selectedWordTypes.contains { filter in
                filter.matches(history)
            }
        }
    }
    
    var body: some View {
        VStack(spacing: 0) {
            filterToolbar
            contentView
        }
        .overlay(playbackControlPanel, alignment: .bottom)
        .task {
            await viewModel.loadHistory(filter: selectedFilter)
        }
        .sheet(isPresented: $showingSpeechPractice) {
            if let history = selectedHistory {
                SpeechPracticeView(reviewHistory: history)
                    .onAppear {
                        print("🔥 [HistoryView] Sheet 已显示，selectedHistory: \(history.word)")
                    }
            }
        }
    }
    
    private var filterToolbar: some View {
        HStack(spacing: 16) {
            Menu {
                ForEach(WordTypeFilter.allCases) { filter in
                    Button(action: {
                        toggleWordTypeFilter(filter)
                    }) {
                        HStack {
                            Text(filter.title)
                            if selectedWordTypes.contains(filter) {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            } label: {
                FilterLabel(text: filterTypeText)
            }
            
            Menu {
                ForEach(HistoryFilter.allCases, id: \.self) { filter in
                    Button(action: {
                        selectedFilter = filter
                        Task {
                            await viewModel.loadHistory(filter: filter)
                        }
                    }) {
                        HStack {
                            Text(filter.title)
                            if selectedFilter == filter {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            } label: {
                FilterLabel(text: selectedFilter.title)
            }
            
            // 添加刷新按钮
            Button(action: {
                // 刷新数据，保持现有筛选条件
                viewModel.reset()
                Task {
                    let filterType = selectedWordTypes.first { $0 != .all } ?? .all
                    await viewModel.loadHistory(filter: selectedFilter, wordType: filterType)
                }
            }) {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.blue)
                    .padding(8)
                    .background(
                        Circle()
                            .fill(Color.blue.opacity(0.1))
                    )
            }
            
            Spacer()
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
    }
    
    private var contentView: some View {
        Group {
            if viewModel.isLoading && viewModel.histories.isEmpty {
                loadingView
            } else if viewModel.histories.isEmpty {
                EmptyStateView()
            } else {
                historyListView
            }
        }
    }
    
    private var loadingView: some View {
        ProgressView()
            .frame(maxHeight: .infinity)
    }
    
    private var historyListView: some View {
        ScrollViewReader { proxy in
            List {
                historySections
                loadMoreSection
            }
            .listStyle(InsetGroupedListStyle())
            .onChange(of: currentPlayingWord) { newWord in
                if let word = newWord {
                    withAnimation {
                        proxy.scrollTo(word, anchor: UnitPoint.center)
                    }
                }
            }
        }
    }
    
    private var historySections: some View {
        ForEach(sortedDates, id: \.self) { date in
            Section(header: sectionHeader(for: date)) {
                historyItems(for: date)
            }
        }
    }
    
    private var sortedDates: [Date] {
        groupedHistories.keys.sorted(by: >)
    }
    
    private func sectionHeader(for date: Date) -> some View {
        Text(formatSectionDate(date))
            .foregroundColor(.secondary)
    }
    
    private func historyItems(for date: Date) -> some View {
        ForEach(groupedHistories[date] ?? [], id: \.word) { history in
            historyItemButton(for: history)
                .listRowBackground(rowBackground(for: history))
        }
    }
    
    private func historyItemButton(for history: ReviewHistoryItem) -> some View {
        Button(action: {
            print("🔥 [HistoryView] 点击了单词: \(history.word)")
            selectedHistory = history
            showingSpeechPractice = true
            print("🔥 [HistoryView] showingSpeechPractice 设置为: \(showingSpeechPractice)")
        }) {
            HStack(spacing: 12) {
                historyItemContent(for: history)
                
                // 添加右侧箭头图标
                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.secondary)
                    .padding(.trailing, 8)
            }
        }
        .buttonStyle(.plain)
    }
    
    private func historyItemContent(for history: ReviewHistoryItem) -> some View {
        HistoryItemView(
            history: history,
            isPlaying: history.word == currentPlayingWord
        )
        .id(history.word)
    }
    
    private func rowBackground(for history: ReviewHistoryItem) -> Color {
        history.word == currentPlayingWord ? 
            Color.blue.opacity(0.1) : Color(.systemBackground)
    }
    
    @ViewBuilder
    private var loadMoreSection: some View {
        if shouldShowLoadMore {
            ProgressView()
                .frame(maxWidth: .infinity)
                .onAppear {
                    Task {
                        let filterType = selectedWordTypes.first { $0 != .all } ?? .all
                        await viewModel.loadHistory(
                            filter: selectedFilter, 
                            wordType: filterType, 
                            reset: false
                        )
                    }
                }
        }
    }
    
    private var shouldShowLoadMore: Bool {
        !viewModel.histories.isEmpty && viewModel.hasMoreData
    }
    
    private var playbackControlPanel: some View {
        Group {
            if !viewModel.histories.isEmpty {
                EnhancedPlaybackControlPanel(
                    isPlaying: $isPlayingBatch,
                    currentWord: $currentPlayingWord,
                    currentIndex: $lastPlaybackIndex,
                    histories: filteredHistories
                )
                .transition(.move(edge: .bottom))
            }
        }
    }
    
    private var groupedHistories: [Date: [ReviewHistoryItem]] {
        Dictionary(grouping: filteredHistories) { history in
            Calendar.current.startOfDay(for: history.reviewDateFormatted)
        }
    }
    
    private func formatSectionDate(_ date: Date) -> String {
        if Calendar.current.isDateInToday(date) {
            return "今天"
        } else if Calendar.current.isDateInYesterday(date) {
            return "昨天"
        } else {
            let formatter = DateFormatter()
            formatter.dateFormat = "MM月dd日"
            return formatter.string(from: date)
        }
    }
    
    private func toggleWordTypeFilter(_ filter: WordTypeFilter) {
        if filter == .all {
            selectedWordTypes = [.all]
        } else {
            selectedWordTypes.remove(.all)
            if selectedWordTypes.contains(filter) {
                selectedWordTypes.remove(filter)
                if selectedWordTypes.isEmpty {
                    selectedWordTypes = [.all]
                }
            } else {
                selectedWordTypes.insert(filter)
            }
        }
        
        isPlayingBatch = false
        currentPlayingWord = nil
        lastPlaybackIndex = 0
        
        // 重置 ViewModel 并重新加载数据
        viewModel.reset()
        Task {
            // 由于我们现在只支持单个类型过滤，取第一个非 .all 的类型
            let filterType = selectedWordTypes.first { $0 != .all } ?? .all
            await viewModel.loadHistory(filter: selectedFilter, wordType: filterType)
        }
    }
    
    private func startBatchPlayback() {
        isPlayingBatch = true
        AudioService.shared.startBatchPlayback(
            words: filteredHistories,
            startIndex: lastPlaybackIndex
        ) { word, index in
            currentPlayingWord = word
            lastPlaybackIndex = index
        }
    }
    
    private func stopBatchPlayback() {
        isPlayingBatch = false
        currentPlayingWord = nil
        AudioService.shared.stopPlayback()
    }
}

// 历史记录项组件
struct HistoryItemView: View {
    let history: ReviewHistoryItem
    let isPlaying: Bool
    @State private var isPlayingMemory = false
    
    private func getPronunciation() -> String? {
        guard let pronunciation = history.pronunciation else { return nil }
        return pronunciation.American.isEmpty == false ? pronunciation.American : pronunciation.British
    }
    
    // 获取该单词的口语练习记录数量
    private var speechPracticeCount: Int {
        return SpeechPracticeRecordService.shared.getRecordCount(forWord: history.word)
    }
    
    // 获取该单词的口语练习最高分
    private var highestScore: Int {
        return SpeechPracticeRecordService.shared.getHighestScore(forWord: history.word)
    }
    
    // 根据分数返回颜色
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
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // 单词行
            Text(history.word)
                .font(.system(size: 18, weight: .semibold))
                .lineLimit(1)
            
            // 音标独立行
            if let pronunciation = getPronunciation() {
                Text(pronunciation)
                    .font(.system(size: 14))
                    .foregroundColor(.secondary)
                    .padding(.bottom, 4)
            }
            
            // 释义
            VStack(alignment: .leading, spacing: 8) {
                ForEach(history.definitions, id: \.meaning) { definition in
                    HStack(alignment: .top, spacing: 8) {
                        // 词性标签固定宽度
                        Text(definition.pos)
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                            .frame(width: 24, alignment: .leading)
                            .lineLimit(1)
                        
                        Text(definition.meaning)
                            .font(.system(size: 15))
                            .foregroundColor(.secondary)
                    }
                }
            }
            
            // 记忆方法
            if let memoryMethod = history.memoryMethod, !memoryMethod.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("记忆方法")
                            .font(.system(size: 13))
                            .foregroundColor(.secondary)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(Color.orange.opacity(0.1))
                            .cornerRadius(6)
                        
                        Button(action: {
                            isPlayingMemory.toggle()
                            if isPlayingMemory {
                                AudioService.shared.playPronunciation(word: memoryMethod, le: "zh", onCompletion: {
                                    DispatchQueue.main.async {
                                        self.isPlayingMemory = false
                                    }
                                })
                            } else {
                                AudioService.shared.stopPlayback()
                            }
                        }) {
                            Image(systemName: isPlayingMemory ? "stop.circle.fill" : "play.circle.fill")
                                .font(.system(size: 18))
                                .foregroundColor(isPlayingMemory ? .red : .blue)
                        }
                        .buttonStyle(.borderless)
                        .contentShape(Circle())
                        
                        Spacer()
                        
                        // 口语练习信息
                        if speechPracticeCount > 0 {
                            HStack(spacing: 4) {
                                Image(systemName: "mic")
                                    .font(.system(size: 12))
                                Text("\(speechPracticeCount)次")
                                    .font(.system(size: 13))
                                if highestScore > 0 {
                                    // 添加彩色分数徽章
                                    HStack(spacing: 2) {
                                        
                                        Text("\(highestScore)")
                                            .font(.system(size: 13, weight: .bold))
                                            .foregroundColor(.white)
                                            .frame(width: 40, height: 20)
                                            .background(scoreColor(highestScore))
                                            .opacity(0.7)
                                            .cornerRadius(8)
                                    }
                                }
                            }
                            .foregroundColor(.blue.opacity(0.8))
                        }
                    }
                    
                    Text(memoryMethod)
                        .font(.system(size: 14))
                        .foregroundColor(.secondary)
                        .padding(10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(Color(.systemGray6))
                        )
                }
            }
            
            Divider()
                .padding(.vertical, 2)
            
            // 统计信息
            HStack {
                StatisticLabel(
                    icon: "arrow.counterclockwise",
                    text: "复习次数: \(history.reviewCount)"
                )
                
                Spacer()
                
                StatisticLabel(
                    icon: "checkmark.circle",
                    text: "正确率: \(calculateAccuracy(correct: history.correctCount, total: history.reviewCount))%"
                )
            }
            
            // 最后复习时间
            StatisticLabel(
                icon: "clock",
                text: "上次复习: \(formatTimestamp(history.lastReviewDate))"
            )
        }
        .padding(.vertical, 8)
    }
    
    private func calculateAccuracy(correct: Int, total: Int) -> Int {
        guard total > 0 else { return 0 }
        return Int((Double(correct) / Double(total)) * 100)
    }
    
    private func formatTimestamp(_ timestamp: Int64) -> String {
        let date = Date(timeIntervalSince1970: TimeInterval(timestamp / 1000))
        let formatter = DateFormatter()
        formatter.dateFormat = "MM-dd HH:mm"
        return formatter.string(from: date)
    }
}

// 统计标签组件
struct StatisticLabel: View {
    let icon: String
    let text: String
    
    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.caption)
                .foregroundColor(.secondary)
            Text(text)
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }
}

// 空状态视图
struct EmptyStateView: View {
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "doc.text.magnifyingglass")
                .font(.system(size: 48))
                .foregroundColor(.secondary)
            Text("暂无学习记录")
                .font(.headline)
                .foregroundColor(.secondary)
        }
        .frame(maxHeight: .infinity)
    }
}

// 新增筛选标签组件
struct FilterLabel: View {
    let text: String
    
    var body: some View {
        HStack {
            Text(text)
                .foregroundColor(.primary)
            Image(systemName: "chevron.down")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(.systemGray6))
        )
    }
}

// 增强版播放控制面板
struct EnhancedPlaybackControlPanel: View {
    @Binding var isPlaying: Bool
    @Binding var currentWord: String?
    @Binding var currentIndex: Int
    let histories: [ReviewHistoryItem]
    
    var body: some View {
        VStack(spacing: 0) {
            Divider()
            
            HStack(spacing: 32) {
                // 上一条按钮
                Button(action: {
                    playPrevious()
                }) {
                    Image(systemName: "backward.fill")
                        .font(.system(size: 24))
                        .foregroundColor(.blue)
                }
                .disabled(currentIndex <= 0 || histories.isEmpty)
                
                // 播放/停止按钮
                Button(action: togglePlayback) {
                    Image(systemName: isPlaying ? "stop.circle.fill" : "play.circle.fill")
                        .font(.system(size: 44))
                        .foregroundColor(isPlaying ? .red : .blue)
                }
                .disabled(histories.isEmpty)
                
                // 下一条按钮
                Button(action: {
                    playNext()
                }) {
                    Image(systemName: "forward.fill")
                        .font(.system(size: 24))
                        .foregroundColor(.blue)
                }
                .disabled(currentIndex >= histories.count - 1 || histories.isEmpty)
            }
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity)
            .background(
                Color(.systemBackground)
                    .shadow(color: .black.opacity(0.1), radius: 8, y: -4)
                    .edgesIgnoringSafeArea(.bottom)
            )
        }
        .onAppear {
            if currentWord == nil, let firstHistory = histories.first {
                currentWord = firstHistory.word
                currentIndex = 0
            }
        }
    }
    
    private func togglePlayback() {
        isPlaying.toggle()
        if isPlaying {
            AudioService.shared.startBatchPlayback(
                words: histories,
                startIndex: currentIndex,
                onWordChange: { word, index in
                    currentWord = word
                    currentIndex = index
                }
            )
        } else {
            AudioService.shared.stopPlayback()
            currentWord = nil
        }
    }
    
    private func playPrevious() {
        if currentIndex > 0 {
            currentIndex -= 1
            if isPlaying {
                AudioService.shared.startBatchPlayback(
                    words: histories,
                    startIndex: currentIndex,
                    onWordChange: { word, index in
                        currentWord = word
                        currentIndex = index
                    }
                )
            } else {
                currentWord = histories[currentIndex].word
            }
        }
    }
    
    private func playNext() {
        if currentIndex < histories.count - 1 {
            currentIndex += 1
            if isPlaying {
                AudioService.shared.startBatchPlayback(
                    words: histories,
                    startIndex: currentIndex,
                    onWordChange: { word, index in
                        currentWord = word
                        currentIndex = index
                    }
                )
            } else {
                currentWord = histories[currentIndex].word
            }
        }
    }
}
