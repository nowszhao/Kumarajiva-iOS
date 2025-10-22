import SwiftUI

/// 字幕跟读练习主视图
struct SubtitleShadowingPracticeView: View {
    @StateObject private var viewModel: SubtitleShadowingViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var showingSubtitleList = false
    @State private var showingHistory = false
    @State private var showingDeleteConfirmation = false
    
    init(video: YouTubeVideo, subtitles: [Subtitle], audioURL: String, startIndex: Int = 0) {
        _viewModel = StateObject(wrappedValue: SubtitleShadowingViewModel(
            video: video,
            subtitles: subtitles,
            audioURL: audioURL,
            startIndex: startIndex
        ))
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // 导航栏
            navigationBar
            
            // 主内容区
            ScrollView {
                VStack(spacing: 20) {
                    // 进度指示器
                    progressIndicator
                    
                    // 字幕显示区
                    subtitleDisplayArea
                    
                    // 评分结果显示
                    if let score = viewModel.lastScore {
                        scoreResultView(score: score)
                    }
                    
                    // 控制按钮区
                    controlButtons
                    
                    // 统计信息
                    if let stats = viewModel.currentStats, stats.practiceCount > 0 {
                        statsView(stats: stats)
                    }
                }
                .padding()
            }
        }
        .navigationBarHidden(true)
        .alert("错误", isPresented: $viewModel.showError) {
            Button("确定", role: .cancel) { }
        } message: {
            if let error = viewModel.errorMessage {
                Text(error)
            }
        }
        .sheet(isPresented: $showingSubtitleList) {
            SubtitleSelectionView(
                subtitles: Array(viewModel.subtitles.enumerated()),
                currentIndex: viewModel.currentSubtitleIndex,
                onSelect: { index in
                    viewModel.goToSubtitle(at: index)
                    showingSubtitleList = false
                }
            )
        }
        .sheet(isPresented: $showingHistory) {
            SubtitlePracticeHistoryView(
                records: viewModel.practiceRecords,
                onDelete: { id in
                    viewModel.deleteRecord(id: id)
                }
            )
        }
        .confirmationDialog("确认删除", isPresented: $showingDeleteConfirmation) {
            Button("删除所有记录", role: .destructive) {
                viewModel.clearAllRecords()
            }
            Button("取消", role: .cancel) { }
        } message: {
            Text("确定要删除当前字幕的所有练习记录吗？")
        }
    }
    
    // MARK: - Navigation Bar
    private var navigationBar: some View {
        HStack {
            Button(action: {
                viewModel.stopPlayback()
                viewModel.stopRecording()
                dismiss()
            }) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 16, weight: .semibold))
            }
            
            Spacer()
            
            Text("字幕跟读练习")
                .font(.headline)
            
            Spacer()
            
            Menu {
                Button(action: { showingSubtitleList = true }) {
                    Label("字幕列表", systemImage: "list.bullet")
                }
                
                Button(action: { showingHistory = true }) {
                    Label("练习历史", systemImage: "clock")
                }
                
                if !viewModel.practiceRecords.isEmpty {
                    Button(role: .destructive, action: { showingDeleteConfirmation = true }) {
                        Label("清空记录", systemImage: "trash")
                    }
                }
            } label: {
                Image(systemName: "ellipsis.circle")
                    .font(.system(size: 16, weight: .semibold))
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 12)
    }
    
    // MARK: - Progress Indicator
    private var progressIndicator: some View {
        VStack(spacing: 8) {
            HStack {
                Text("\(viewModel.currentSubtitleIndex + 1) / \(viewModel.totalSubtitles)")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                Spacer()
                
                Button(action: { showingSubtitleList = true }) {
                    HStack(spacing: 4) {
                        Image(systemName: "list.bullet")
                        Text("选择字幕")
                    }
                    .font(.caption)
                    .foregroundColor(.blue)
                }
            }
            
            ProgressView(value: Double(viewModel.currentSubtitleIndex + 1), total: Double(viewModel.totalSubtitles))
                .tint(.blue)
        }
        .padding()
        .background(Color(UIColor.systemGray6))
        .cornerRadius(12)
    }
    
    // MARK: - Subtitle Display Area
    private var subtitleDisplayArea: some View {
        VStack(spacing: 16) {
            if let subtitle = viewModel.currentSubtitle {
                // 原文
                VStack(alignment: .leading, spacing: 8) {
                    Text("原文")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    if !viewModel.lastWordMatches.isEmpty {
                        // 显示单词匹配结果
                        FlowLayout(spacing: 8) {
                            ForEach(viewModel.lastWordMatches.indices, id: \.self) { index in
                                let match = viewModel.lastWordMatches[index]
                                Text(match.originalWord)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(match.isMatch ? Color.green.opacity(0.2) : Color.red.opacity(0.2))
                                    .cornerRadius(6)
                                    .font(.system(size: 16))
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    } else {
                        Text(subtitle.text)
                            .font(.system(size: 18))
                            .lineSpacing(8)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
                .background(Color(UIColor.systemBackground))
                .cornerRadius(12)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.blue.opacity(0.3), lineWidth: 1)
                )
                
                // 识别结果
                if let recognizedText = viewModel.lastRecognizedText {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("识别结果")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        
                        Text(recognizedText)
                            .font(.system(size: 16))
                            .foregroundColor(.secondary)
                            .lineSpacing(6)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
                    .background(Color(UIColor.systemGray6))
                    .cornerRadius(12)
                }
                
                // 时间信息
                HStack {
                    Image(systemName: "clock")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text(formatTime(subtitle.startTime) + " - " + formatTime(subtitle.endTime))
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    Spacer()
                    
                    Text("时长: \(formatDuration(subtitle.endTime - subtitle.startTime))")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
    }
    
    // MARK: - Score Result View
    private func scoreResultView(score: Int) -> some View {
        VStack(spacing: 12) {
            HStack {
                Image(systemName: scoreIcon(for: score))
                    .font(.system(size: 32))
                    .foregroundColor(scoreColor(for: score))
                
                VStack(alignment: .leading, spacing: 4) {
                    Text("得分")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text("\(score)")
                        .font(.system(size: 28, weight: .bold))
                        .foregroundColor(scoreColor(for: score))
                }
                
                Spacer()
                
                Text(scoreDescription(for: score))
                    .font(.headline)
                    .foregroundColor(scoreColor(for: score))
            }
            .padding()
            .background(scoreColor(for: score).opacity(0.1))
            .cornerRadius(12)
        }
    }
    
    // MARK: - Control Buttons
    private var controlButtons: some View {
        VStack(spacing: 20) {
            // 主控制区：播放、导航、录音
            HStack(spacing: 0) {
                // 上一句按钮
                Button(action: {
                    viewModel.goToPrevious()
                }) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 24, weight: .semibold))
                        .foregroundColor(viewModel.hasPrevious ? .blue : .gray.opacity(0.3))
                        .frame(width: 60, height: 60)
                }
                .disabled(!viewModel.hasPrevious || viewModel.isRecording || viewModel.isProcessing)
                
                Spacer()
                
                // 播放按钮
                Button(action: {
                    viewModel.togglePlayback()
                }) {
                    ZStack {
                        Circle()
                            .fill(Color.blue)
                            .frame(width: 64, height: 64)
                        
                        Image(systemName: viewModel.isPlaying ? "pause.fill" : "play.fill")
                            .font(.system(size: 28))
                            .foregroundColor(.white)
                    }
                }
                .disabled(viewModel.isRecording || viewModel.isProcessing)
                
                Spacer()
                
                // 录音按钮
                Button(action: {
                    if viewModel.isRecording {
                        viewModel.stopRecording()
                    } else {
                        Task {
                            await viewModel.startRecording()
                        }
                    }
                }) {
                    ZStack {
                        Circle()
                            .fill(viewModel.isRecording ? Color.red : Color.red.opacity(0.15))
                            .frame(width: 64, height: 64)
                        
                        if viewModel.isProcessing {
                            ProgressView()
                                .tint(.red)
                        } else {
                            Image(systemName: viewModel.isRecording ? "stop.fill" : "mic.fill")
                                .font(.system(size: 28))
                                .foregroundColor(viewModel.isRecording ? .white : .red)
                        }
                    }
                }
                .disabled(viewModel.isPlaying || viewModel.isProcessing)
                
                Spacer()
                
                // 下一句按钮
                Button(action: {
                    viewModel.goToNext()
                }) {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 24, weight: .semibold))
                        .foregroundColor(viewModel.hasNext ? .blue : .gray.opacity(0.3))
                        .frame(width: 60, height: 60)
                }
                .disabled(!viewModel.hasNext || viewModel.isRecording || viewModel.isProcessing)
            }
            .padding(.horizontal, 20)
            
            // 按钮标签
            HStack(spacing: 0) {
                Text("上一句")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .frame(width: 60)
                
                Spacer()
                
                Text(viewModel.isPlaying ? "播放中" : "播放")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .frame(width: 64)
                
                Spacer()
                
                Text(viewModel.isRecording ? "录音中" : (viewModel.isProcessing ? "处理中" : "录音"))
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .frame(width: 64)
                
                Spacer()
                
                Text("下一句")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .frame(width: 60)
            }
            .padding(.horizontal, 20)
        }
    }
    
    // MARK: - Stats View
    private func statsView(stats: SubtitlePracticeStats) -> some View {
        VStack(spacing: 12) {
            Text("练习统计")
                .font(.headline)
                .frame(maxWidth: .infinity, alignment: .leading)
            
            HStack(spacing: 16) {
                statItem(title: "练习次数", value: "\(stats.practiceCount)", icon: "repeat")
                statItem(title: "最高分", value: "\(stats.highestScore)", icon: "star.fill")
                statItem(title: "平均分", value: String(format: "%.0f", stats.averageScore), icon: "chart.bar.fill")
            }
        }
        .padding()
        .background(Color(UIColor.systemGray6))
        .cornerRadius(12)
    }
    
    private func statItem(title: String, value: String, icon: String) -> some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 20))
                .foregroundColor(.blue)
            Text(value)
                .font(.system(size: 20, weight: .bold))
            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
    
    // MARK: - Helper Methods
    private func formatTime(_ time: TimeInterval) -> String {
        let minutes = Int(time) / 60
        let seconds = Int(time) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
    
    private func formatDuration(_ duration: TimeInterval) -> String {
        return String(format: "%.1fs", duration)
    }
    
    private func scoreIcon(for score: Int) -> String {
        switch score {
        case 90...100: return "star.fill"
        case 70..<90: return "hand.thumbsup.fill"
        case 50..<70: return "face.smiling"
        default: return "arrow.clockwise"
        }
    }
    
    private func scoreColor(for score: Int) -> Color {
        switch score {
        case 90...100: return .green
        case 70..<90: return .blue
        case 50..<70: return .orange
        default: return .red
        }
    }
    
    private func scoreDescription(for score: Int) -> String {
        switch score {
        case 90...100: return "优秀"
        case 70..<90: return "良好"
        case 50..<70: return "及格"
        default: return "继续努力"
        }
    }
}
