import SwiftUI

/// 字幕选择视图
struct SubtitleSelectionView: View {
    let subtitles: [(offset: Int, element: Subtitle)]
    let currentIndex: Int
    let onSelect: (Int) -> Void
    
    @Environment(\.dismiss) private var dismiss
    @State private var searchText = ""
    
    private var filteredSubtitles: [(offset: Int, element: Subtitle)] {
        if searchText.isEmpty {
            return subtitles
        } else {
            return subtitles.filter { $0.element.text.localizedCaseInsensitiveContains(searchText) }
        }
    }
    
    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // 搜索框
                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(.secondary)
                    
                    TextField("搜索字幕内容...", text: $searchText)
                        .textFieldStyle(.plain)
                    
                    if !searchText.isEmpty {
                        Button(action: { searchText = "" }) {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(.secondary)
                        }
                    }
                }
                .padding()
                .background(Color(UIColor.systemGray6))
                .cornerRadius(10)
                .padding()
                
                // 字幕列表
                List {
                    ForEach(filteredSubtitles, id: \.offset) { item in
                        SubtitleSelectionRowView(
                            subtitle: item.element,
                            index: item.offset,
                            isSelected: item.offset == currentIndex,
                            onTap: {
                                onSelect(item.offset)
                            }
                        )
                    }
                }
                .listStyle(.plain)
            }
            .navigationTitle("选择字幕")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("关闭") {
                        dismiss()
                    }
                }
            }
        }
    }
}

/// 字幕选择行视图
struct SubtitleSelectionRowView: View {
    let subtitle: Subtitle
    let index: Int
    let isSelected: Bool
    let onTap: () -> Void
    
    var body: some View {
        Button(action: onTap) {
            HStack(alignment: .top, spacing: 12) {
                // 序号
                Text("\(index + 1)")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(isSelected ? .white : .secondary)
                    .frame(width: 40, height: 40)
                    .background(isSelected ? Color.blue : Color(UIColor.systemGray5))
                    .clipShape(Circle())
                
                // 内容
                VStack(alignment: .leading, spacing: 6) {
                    Text(subtitle.text)
                        .font(.system(size: 15))
                        .foregroundColor(.primary)
                        .lineLimit(3)
                    
                    HStack {
                        Image(systemName: "clock")
                            .font(.caption2)
                        Text(formatTime(subtitle.startTime))
                            .font(.caption)
                        
                        Image(systemName: "arrow.right")
                            .font(.caption2)
                        Text(formatTime(subtitle.endTime))
                            .font(.caption)
                        
                        Spacer()
                        
                        Text(formatDuration(subtitle.endTime - subtitle.startTime))
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .foregroundColor(.secondary)
                }
                
                // 选中标记
                if isSelected {
                    Spacer()
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.blue)
                        .font(.system(size: 20))
                }
            }
            .padding(.vertical, 8)
        }
        .buttonStyle(.plain)
    }
    
    private func formatTime(_ time: TimeInterval) -> String {
        let minutes = Int(time) / 60
        let seconds = Int(time) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
    
    private func formatDuration(_ duration: TimeInterval) -> String {
        return String(format: "%.1fs", duration)
    }
}
