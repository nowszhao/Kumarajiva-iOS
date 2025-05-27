import SwiftUI

struct SubtitleTaskManagerView: View {
    @StateObject private var taskManager = SubtitleGenerationTaskManager.shared
    @State private var selectedTab = 0
    
    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // 顶部统计信息
                taskSummaryView
                
                // 分段控制器
                VStack(spacing: 0) {
                    Picker("任务类型", selection: $selectedTab) {
                        Text("活动中 (\(taskManager.activeTasks.count))").tag(0)
                        Text("已完成 (\(taskManager.completedTasks.count))").tag(1)
                        Text("失败 (\(taskManager.failedTasks.count))").tag(2)
                    }
                    .pickerStyle(SegmentedPickerStyle())
                    .padding()
                    
                    Divider()
                }
                .background(Color(.systemBackground))
                
                // 任务列表
                TabView(selection: $selectedTab) {
                    activeTasksView.tag(0)
                    completedTasksView.tag(1)
                    failedTasksView.tag(2)
                }
                .tabViewStyle(PageTabViewStyle(indexDisplayMode: .never))
                .background(Color(.systemGroupedBackground))
            }
            .navigationTitle("字幕生成任务")
            .navigationBarTitleDisplayMode(.large)
            .background(Color(.systemGroupedBackground))
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Menu {
                        Button("清除已完成任务") {
                            taskManager.clearCompletedTasks()
                        }
                        .disabled(taskManager.completedTasks.isEmpty)
                        
                        Button("清除失败任务") {
                            taskManager.clearFailedTasks()
                        }
                        .disabled(taskManager.failedTasks.isEmpty)
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
            }
        }
    }
    
    // MARK: - 任务摘要视图
    
    private var taskSummaryView: some View {
        VStack(spacing: 0) {
            HStack(spacing: 20) {
                VStack {
                    Text("\(taskManager.activeTasks.count)")
                        .font(.title2)
                        .fontWeight(.bold)
                        .foregroundColor(.blue)
                    Text("活动中")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                VStack {
                    Text("\(taskManager.completedTasks.count)")
                        .font(.title2)
                        .fontWeight(.bold)
                        .foregroundColor(.green)
                    Text("已完成")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                VStack {
                    Text("\(taskManager.failedTasks.count)")
                        .font(.title2)
                        .fontWeight(.bold)
                        .foregroundColor(.red)
                    Text("失败")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .padding()
            
            Divider()
        }
        .background(Color(.systemBackground))
    }
    
    // MARK: - 活动任务视图
    
    private var activeTasksView: some View {
        ScrollView {
            LazyVStack(spacing: 12) {
                if taskManager.activeTasks.isEmpty {
                    emptyStateView(
                        icon: "clock",
                        title: "暂无活动任务",
                        message: "当前没有正在进行的字幕生成任务"
                    )
                } else {
                    ForEach(taskManager.activeTasks) { task in
                        ActiveTaskRowView(task: task) {
                            taskManager.cancelTask(task)
                        }
                    }
                }
            }
            .padding()
        }
    }
    
    // MARK: - 已完成任务视图
    
    private var completedTasksView: some View {
        ScrollView {
            LazyVStack(spacing: 12) {
                if taskManager.completedTasks.isEmpty {
                    emptyStateView(
                        icon: "checkmark.circle",
                        title: "暂无已完成任务",
                        message: "完成的字幕生成任务将显示在这里"
                    )
                } else {
                    ForEach(taskManager.completedTasks) { task in
                        CompletedTaskRowView(task: task) {
                            taskManager.deleteTask(task)
                        }
                    }
                }
            }
            .padding()
        }
    }
    
    // MARK: - 失败任务视图
    
    private var failedTasksView: some View {
        ScrollView {
            LazyVStack(spacing: 12) {
                if taskManager.failedTasks.isEmpty {
                    emptyStateView(
                        icon: "exclamationmark.triangle",
                        title: "暂无失败任务",
                        message: "失败的字幕生成任务将显示在这里"
                    )
                } else {
                    ForEach(taskManager.failedTasks) { task in
                        FailedTaskRowView(task: task,
                                        onRetry: {
                                            // 重试任务
                                            retryTask(task)
                                        },
                                        onDelete: {
                                            taskManager.deleteTask(task)
                                        })
                    }
                }
            }
            .padding()
        }
    }
    
    // MARK: - 空状态视图
    
    private func emptyStateView(icon: String, title: String, message: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: icon)
                .font(.system(size: 50))
                .foregroundColor(.secondary)
            
            Text(title)
                .font(.headline)
                .foregroundColor(.secondary)
            
            Text(message)
                .font(.body)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }
    
    // MARK: - 辅助方法
    
    private func retryTask(_ task: SubtitleGenerationTask) {
        // 创建新的重试任务
        if let episode = PodcastDataService.shared.getEpisode(by: task.episodeId) {
            taskManager.deleteTask(task) // 删除失败的任务
            let _ = taskManager.createTask(for: episode, quality: task.quality) // 创建新任务
        }
    }
}

// MARK: - 活动任务行视图
struct ActiveTaskRowView: View {
    @ObservedObject var task: SubtitleGenerationTask
    let onCancel: () -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // 任务信息
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(task.episodeName)
                        .font(.headline)
                        .lineLimit(2)
                    
                    Text(task.statusMessage)
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    Text("开始时间: \(formatDate(task.createdAt))")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                // 状态图标
                statusIcon
            }
            
            // 进度条
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("进度")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    Spacer()
                    
                    Text("\(Int(task.progress * 100))%")
                        .font(.caption)
                        .fontWeight(.medium)
                }
                
                ProgressView(value: task.progress)
                    .progressViewStyle(LinearProgressViewStyle(tint: statusColor))
                    .scaleEffect(y: 1.5)
            }
            
            // 操作按钮
            HStack {
                Spacer()
                
                Button("取消任务") {
                    onCancel()
                }
                .font(.caption)
                .foregroundColor(.red)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Color.red.opacity(0.1))
                .cornerRadius(8)
            }
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(12)
        .shadow(color: .black.opacity(0.1), radius: 2, x: 0, y: 1)
    }
    
    private var statusIcon: some View {
        ZStack {
            Circle()
                .fill(statusColor.opacity(0.2))
                .frame(width: 40, height: 40)
            
            if case .transcribing = task.status {
                // 转录中显示动画
                Image(systemName: "waveform")
                    .font(.system(size: 16))
                    .foregroundColor(statusColor)
                    .scaleEffect(1.2)
                    .animation(.easeInOut(duration: 1).repeatForever(autoreverses: true), value: task.progress)
            } else {
                Image(systemName: statusIconName)
                    .font(.system(size: 16))
                    .foregroundColor(statusColor)
            }
        }
    }
    
    private var statusColor: Color {
        switch task.status {
        case .pending:
            return .orange
        case .downloading:
            return .blue
        case .processing:
            return .purple
        case .transcribing:
            return .green
        case .finalizing:
            return .indigo
        default:
            return .gray
        }
    }
    
    private var statusIconName: String {
        switch task.status {
        case .pending:
            return "clock"
        case .downloading:
            return "arrow.down.circle"
        case .processing:
            return "gearshape"
        case .transcribing:
            return "waveform"
        case .finalizing:
            return "checkmark.circle"
        default:
            return "questionmark"
        }
    }
    
    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}

// MARK: - 已完成任务行视图
struct CompletedTaskRowView: View {
    @ObservedObject var task: SubtitleGenerationTask
    let onDelete: () -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(task.episodeName)
                        .font(.headline)
                        .lineLimit(2)
                    
                    Text("生成了 \(task.generatedSubtitles.count) 条字幕")
                        .font(.caption)
                        .foregroundColor(.green)
                    
                    Text("完成时间: \(formatDate(task.createdAt))")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                // 成功图标
                ZStack {
                    Circle()
                        .fill(Color.green.opacity(0.2))
                        .frame(width: 40, height: 40)
                    
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 20))
                        .foregroundColor(.green)
                }
            }
            
            // 操作按钮
            HStack {
                Spacer()
                
                Button("删除记录") {
                    onDelete()
                }
                .font(.caption)
                .foregroundColor(.red)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Color.red.opacity(0.1))
                .cornerRadius(8)
            }
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(12)
        .shadow(color: .black.opacity(0.1), radius: 2, x: 0, y: 1)
    }
    
    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}

// MARK: - 失败任务行视图
struct FailedTaskRowView: View {
    @ObservedObject var task: SubtitleGenerationTask
    let onRetry: () -> Void
    let onDelete: () -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(task.episodeName)
                        .font(.headline)
                        .lineLimit(2)
                    
                    if let errorMessage = task.errorMessage {
                        Text("错误: \(errorMessage)")
                            .font(.caption)
                            .foregroundColor(.red)
                            .lineLimit(2)
                    }
                    
                    Text("失败时间: \(formatDate(task.createdAt))")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                // 失败图标
                ZStack {
                    Circle()
                        .fill(Color.red.opacity(0.2))
                        .frame(width: 40, height: 40)
                    
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 16))
                        .foregroundColor(.red)
                }
            }
            
            // 操作按钮
            HStack {
                Button("重试") {
                    onRetry()
                }
                .font(.caption)
                .foregroundColor(.blue)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Color.blue.opacity(0.1))
                .cornerRadius(8)
                
                Spacer()
                
                Button("删除") {
                    onDelete()
                }
                .font(.caption)
                .foregroundColor(.red)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Color.red.opacity(0.1))
                .cornerRadius(8)
            }
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(12)
        .shadow(color: .black.opacity(0.1), radius: 2, x: 0, y: 1)
    }
    
    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}

// MARK: - 预览
#Preview {
    SubtitleTaskManagerView()
} 