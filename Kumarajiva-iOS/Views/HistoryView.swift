import SwiftUI

struct HistoryView: View {
    @StateObject private var viewModel = HistoryViewModel()
    @State private var selectedFilter: HistoryFilter = .today
    
    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // 筛选器
                FilterSegmentView(selectedFilter: $selectedFilter) {
                    Task {
                        await viewModel.loadHistory(filter: selectedFilter)
                    }
                }
                .padding(.horizontal)
                .padding(.vertical, 12)
                
                if viewModel.isLoading {
                    ProgressView()
                        .frame(maxHeight: .infinity)
                } else if viewModel.histories.isEmpty {
                    EmptyStateView()
                } else {
                    List {
                        ForEach(groupedHistories.keys.sorted(by: >), id: \.self) { date in
                            Section(header: Text(formatSectionDate(date)).foregroundColor(.secondary)) {
                                ForEach(groupedHistories[date] ?? [], id: \.word) { history in
                                    HistoryItemView(history: history)
                                }
                            }
                        }
                    }
                    .listStyle(InsetGroupedListStyle())
                }
            }
            .navigationTitle("历史记录")
        }
        .task {
            await viewModel.loadHistory(filter: selectedFilter)
        }
    }
    
    private var groupedHistories: [Date: [History]] {
        Dictionary(grouping: viewModel.histories) { history in
            Calendar.current.startOfDay(for: Date(timeIntervalSince1970: TimeInterval(history.timestamp / 1000)))
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
}

// 筛选器组件
struct FilterSegmentView: View {
    @Binding var selectedFilter: HistoryFilter
    let onFilterChange: () -> Void
    
    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                ForEach(HistoryFilter.allCases, id: \.self) { filter in
                    FilterButton(
                        title: filter.title,
                        isSelected: selectedFilter == filter
                    ) {
                        selectedFilter = filter
                        onFilterChange()
                    }
                }
            }
            .padding(.horizontal)
        }
    }
}

struct FilterButton: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 15))
                .foregroundColor(isSelected ? .white : .primary)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 16)
                        .fill(isSelected ? Color.blue : Color(.systemGray6))
                )
        }
    }
}

// 历史记录项组件
struct HistoryItemView: View {
    let history: History
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // 单词和音标
            HStack(alignment: .center, spacing: 12) {
                Text(history.word)
                    .font(.headline)
                
                if let pronunciationStr = history.pronunciation,
                   let pronunciation = parsePronunciation(pronunciationStr) {
                    HStack(spacing: 4) {
                        Image(systemName: "speaker.wave.2")
                            .font(.caption)
                            .foregroundColor(.blue)
                        Text(pronunciation)
                            .font(.system(size: 14))
                            .foregroundColor(.secondary)
                    }
                }
            }
            
            // 释义
            ForEach(history.definitions, id: \.meaning) { definition in
                Text("\(definition.meaning) (\(definition.pos))")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            
            // 记忆方法
            if let method = history.memoryMethod {
                Text(method)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .padding(.vertical, 4)
            }
            
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
            if let lastReviewDate = history.lastReviewDate {
                StatisticLabel(
                    icon: "clock",
                    text: "上次复习: \(formatTimestamp(lastReviewDate))"
                )
            }
        }
        .padding(.vertical, 8)
    }
    
    private func parsePronunciation(_ jsonString: String) -> String? {
        guard let data = jsonString.data(using: .utf8),
              let dict = try? JSONDecoder().decode([String: String].self, from: data),
              let american = dict["American"] else {
            return nil
        }
        return american
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