import SwiftUI

private enum ContributionColorPalette {
    static let levels: [Color] = [
        Color(.systemGray5),
        Color(red: 198.0 / 255.0, green: 228.0 / 255.0, blue: 139.0 / 255.0),
        Color(red: 123.0 / 255.0, green: 201.0 / 255.0, blue: 111.0 / 255.0),
        Color(red: 35.0 / 255.0, green: 154.0 / 255.0, blue: 59.0 / 255.0),
        Color(red: 25.0 / 255.0, green: 97.0 / 255.0, blue: 39.0 / 255.0)
    ]
    
    static func color(for level: Int) -> Color {
        guard level >= 0, level < levels.count else {
            return levels[0]
        }
        return levels[level]
    }
}

// 学习贡献图视图
struct ContributionGraphView: View {
    @ObservedObject var viewModel: ProfileViewModel
    @State private var hoveredItem: ContributionData?
    @State private var showTooltip = false
    
    // 动态计算格子大小和间距
    private var cellSize: CGFloat {
        let screenWidth = UIScreen.main.bounds.width
        let horizontalPadding: CGFloat = 32 // 左右padding
        let weekdayLabelWidth: CGFloat = 16 // 星期标签宽度
        let availableWidth = screenWidth - horizontalPadding - weekdayLabelWidth
        let totalSpacing = CGFloat(ContributionConfig.weeksToShow - 1) * cellSpacing
        let cellWidth = (availableWidth - totalSpacing) / CGFloat(ContributionConfig.weeksToShow)
        return max(8, min(12, cellWidth)) // 限制在8-12之间
    }
    
    private let cellSpacing: CGFloat = 1
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // 标题和说明
            HStack {
                Text("打卡记录")
                    .font(.headline)
                    .foregroundColor(.primary)
                
                Spacer()
                
                if viewModel.isLoadingContribution {
                    ProgressView()
                        .scaleEffect(0.8)
                }
            }
            
            if let error = viewModel.contributionError {
                // 错误状态
                VStack(spacing: 8) {
                    Text("加载失败")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    Text(error)
                        .font(.caption)
                        .foregroundColor(.red)
                        .multilineTextAlignment(.center)
                    
                    Button("重试") {
                        Task {
                            await viewModel.loadContributionData()
                        }
                    }
                    .font(.caption)
                    .buttonStyle(.borderedProminent)
                }
                .frame(height: 80)
            } else {
                VStack(spacing: 8) {
                    // 贡献图网格
                    ContributionGridView(
                        weeks: viewModel.getContributionGrid(),
                        cellSize: cellSize,
                        cellSpacing: cellSpacing,
                        hoveredItem: $hoveredItem,
                        showTooltip: $showTooltip
                    )
                    
                    // 图例
                    HStack {
                        Text("少")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        
                        HStack(spacing: 3) {
                            ForEach(0..<5) { level in
                                Rectangle()
                                    .fill(ContributionColorPalette.color(for: level))
                                    .frame(width: 10, height: 10)
                                    .cornerRadius(2)
                            }
                        }
                        
                        Text("多")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        
                        Spacer()
                        
                        Text("最近 180 天")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
        }
        .onAppear {
            if viewModel.contributionData.isEmpty && !viewModel.isLoadingContribution {
                Task {
                    await viewModel.loadContributionData()
                }
            }
        }
        .overlay(
            // 悬浮提示
            TooltipView(item: hoveredItem, show: showTooltip)
                .opacity(showTooltip && hoveredItem != nil ? 1 : 0)
                .animation(.easeInOut(duration: 0.2), value: showTooltip)
        )
    }
    
    private func colorForLevel(_ level: Int) -> Color {
        ContributionColorPalette.color(for: level)
    }
}

// 贡献图网格视图
struct ContributionGridView: View {
    let weeks: [[ContributionData?]]
    let cellSize: CGFloat
    let cellSpacing: CGFloat
    @Binding var hoveredItem: ContributionData?
    @Binding var showTooltip: Bool
    
    private let weekdays = ["一", "二", "三", "四", "五", "六", "日"]
    
    var body: some View {
        HStack(alignment: .top, spacing: 4) {
            // 星期标签
            VStack(spacing: cellSpacing) {
                // 空白区域对齐月份标签
                Rectangle()
                    .fill(Color.clear)
                    .frame(height: 12)
                
                ForEach(Array(weekdays.enumerated()), id: \.offset) { index, day in
                    if index % 2 == 1 { // 只显示奇数行的标签以避免拥挤
                        Text(day)
                            .font(.system(size: 8))
                            .foregroundColor(.secondary)
                            .frame(width: 12, height: cellSize)
                    } else {
                        Rectangle()
                            .fill(Color.clear)
                            .frame(width: 12, height: cellSize)
                    }
                }
            }
            
            // 贡献图主体 - 移除 ScrollView，直接显示
            VStack(alignment: .leading, spacing: 0) {
                // 月份标签
                MonthLabelsView(weeks: weeks, cellSize: cellSize, cellSpacing: cellSpacing)
                
                // 贡献图主体
                HStack(spacing: cellSpacing) {
                    ForEach(Array(weeks.enumerated()), id: \.offset) { weekIndex, week in
                        VStack(spacing: cellSpacing) {
                            ForEach(Array(week.enumerated()), id: \.offset) { dayIndex, dayData in
                                ContributionCellView(
                                    data: dayData,
                                    cellSize: cellSize,
                                    hoveredItem: $hoveredItem,
                                    showTooltip: $showTooltip
                                )
                            }
                        }
                    }
                }
            }
        }
    }
}

// 月份标签视图
struct MonthLabelsView: View {
    let weeks: [[ContributionData?]]
    let cellSize: CGFloat
    let cellSpacing: CGFloat
    
    var body: some View {
        HStack(spacing: cellSpacing) {
            ForEach(Array(weeks.enumerated()), id: \.offset) { weekIndex, week in
                VStack {
                    if let firstDay = week.first??.dateObject,
                       let monthLabel = getMonthLabel(for: firstDay, weekIndex: weekIndex) {
                        Text(monthLabel)
                            .font(.system(size: 9))
                            .foregroundColor(.secondary)
                            .frame(width: cellSize, height: 20)
                    } else {
                        Rectangle()
                            .fill(Color.clear)
                            .frame(width: cellSize, height: 20)
                    }
                }
            }
        }
    }
    
    private func getMonthLabel(for date: Date, weekIndex: Int) -> String? {
        let calendar = Calendar.current
        let day = calendar.component(.day, from: date)
        
        // 只在每月的第一周显示月份标签
        if day <= 7 {
            let formatter = DateFormatter()
            formatter.dateFormat = "M月"
            return formatter.string(from: date)
        }
        
        return nil
    }
}

// 单个贡献格子视图
struct ContributionCellView: View {
    let data: ContributionData?
    let cellSize: CGFloat
    @Binding var hoveredItem: ContributionData?
    @Binding var showTooltip: Bool
    
    var body: some View {
        Rectangle()
            .fill(cellColor)
            .frame(width: cellSize, height: cellSize)
            .cornerRadius(2)
            .overlay(
                RoundedRectangle(cornerRadius: 2)
                    .stroke(Color.white.opacity(data == nil ? 0 : 0.15), lineWidth: 0.6)
            )
            .shadow(color: Color.black.opacity(data == nil ? 0 : 0.08), radius: data == nil ? 0 : 1, x: 0, y: 0.4)
            .onTapGesture {
                if let data = data {
                    hoveredItem = data
                    showTooltip.toggle()
                }
            }
    }
    
    private var cellColor: Color {
        guard let data = data else {
            // 没有数据（真正的空数据）显示为浅灰色
            return ContributionColorPalette.color(for: 0)
        }
        
        return ContributionColorPalette.color(for: data.contributionLevel)
    }
}

// 悬浮提示视图
struct TooltipView: View {
    let item: ContributionData?
    let show: Bool
    
    var body: some View {
        if let item = item, show {
            VStack(alignment: .leading, spacing: 4) {
                Text(item.formattedDate)
                    .font(.caption)
                    .fontWeight(.semibold)
                
                if item.completed > 0 {
                    Text("学习 \(item.completed) 个单词")
                        .font(.caption)
                    Text("正确率 \(String(format: "%.1f", item.accuracy * 100))%")
                        .font(.caption)
                } else {
                    Text("无学习记录")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .padding(8)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color(.systemBackground))
                    .shadow(color: Color.black.opacity(0.15), radius: 6, x: 0, y: 4)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.white.opacity(0.4), lineWidth: 0.5)
            )
            .position(x: UIScreen.main.bounds.width / 2, y: 50)
        }
    }
}

// 预览
struct ContributionGraphView_Previews: PreviewProvider {
    static var previews: some View {
        let viewModel = ProfileViewModel()
        ContributionGraphView(viewModel: viewModel)
            .padding()
    }
} 
