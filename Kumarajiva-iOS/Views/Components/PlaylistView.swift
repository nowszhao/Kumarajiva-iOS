import SwiftUI

struct PlaylistView: View {
    @StateObject private var playerService = PodcastPlayerService.shared
    @Environment(\.dismiss) private var dismiss
    @State private var showingClearConfirmation = false
    
    // 计算属性：获取按播放时间倒序排列的播放记录
    private var sortedPlaybackRecords: [EpisodePlaybackRecord] {
        let records = Array(playerService.playbackRecords.values)
        return records.sorted { first, second in
            first.lastPlayedDate > second.lastPlayedDate
        }
    }
    
    var body: some View {
        NavigationView {
            contentView
                .navigationTitle("播放列表")
                .navigationBarTitleDisplayMode(.large)
                .toolbar {
                    ToolbarItem(placement: .navigationBarLeading) {
                        Button("关闭") {
                            dismiss()
                        }
                    }
                    
                    if !sortedPlaybackRecords.isEmpty {
                        ToolbarItem(placement: .navigationBarTrailing) {
                            HStack(spacing: 8) {
                                // 播放全部按钮
                                Button {
                                    playAll()
                                } label: {
                                    Image(systemName: "play.fill")
                                        .foregroundColor(.accentColor)
                                }
                                
                                // 清空按钮
                                Button("清空") {
                                    showingClearConfirmation = true
                                }
                                .foregroundColor(.red)
                            }
                        }
                    }
                }
        }
        .confirmationDialog("确认清空播放列表吗？", isPresented: $showingClearConfirmation) {
            Button("清空", role: .destructive) {
                clearPlaylist()
            }
        } message: {
            Text("清空播放列表后，所有播放记录将被删除。")
        }
    }
    
    @ViewBuilder
    private var contentView: some View {
        if sortedPlaybackRecords.isEmpty {
            emptyStateView
        } else {
            playlistView
        }
    }
    
    private var emptyStateView: some View {
        VStack(spacing: 20) {
            Image(systemName: "music.note.list")
                .font(.system(size: 48))
                .foregroundColor(.secondary)
            
            VStack(spacing: 8) {
                Text("播放列表为空")
                    .font(.title2)
                    .fontWeight(.medium)
                    .foregroundColor(.primary)
                
                Text("播放的播客和视频会自动添加到这里")
                    .font(.body)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                
                Text("💡 小贴士：播放记录会包含播放进度，方便你随时继续收听")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.top, 8)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, 32)
    }
    
    private var playlistView: some View {
        List {
            Section {
                ForEach(sortedPlaybackRecords) { record in
                    PlaylistItemView(record: record, onDismiss: { dismiss() })
                        .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                        .listRowBackground(Color(.systemBackground))
                }
                .onDelete(perform: deleteItems)
            } header: {
                HStack {
                    Text("最近播放")
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundColor(.secondary)
                    
                    Spacer()
                    
                    Text("\(sortedPlaybackRecords.count) 个项目")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 4)
            }
        }
        .listStyle(InsetGroupedListStyle())
        .refreshable {
            // 刷新播放列表
            // 这里可以重新加载数据，当前数据已经是响应式的
        }
    }
    
    // 删除单个项目
    private func deleteItems(offsets: IndexSet) {
        for index in offsets {
            let record = sortedPlaybackRecords[index]
            playerService.removePlaybackRecord(episodeId: record.episodeId)
        }
    }
    
    // 清空播放列表
    private func clearPlaylist() {
        playerService.clearAllPlaybackRecords()
    }
    
    // 播放全部（从第一个开始）
    private func playAll() {
        guard let firstRecord = sortedPlaybackRecords.first else { return }
        
        print("🎧 [Playlist] 播放全部，从第一个记录开始: \(firstRecord.episodeId)")
        playerService.playEpisodeFromRecord(firstRecord)
        
        // 关闭播放列表
        dismiss()
    }
}

// MARK: - 播放列表项视图
struct PlaylistItemView: View {
    let record: EpisodePlaybackRecord
    let onDismiss: () -> Void
    @StateObject private var playerService = PodcastPlayerService.shared
    @State private var isLoading = false
    
    var body: some View {
        HStack(spacing: 12) {
            // 播放状态图标
            VStack {
                Image(systemName: record.status.icon)
                    .font(.system(size: 20))
                    .foregroundColor(statusColor)
                    .frame(width: 24, height: 24)
                
                Spacer()
            }
            
            // 播客信息
            VStack(alignment: .leading, spacing: 4) {
                // 显示episode标题或ID
                Text(episodeTitle)
                    .font(.headline)
                    .lineLimit(2)
                    .foregroundColor(.primary)
                
                // 播放进度和时间信息
                HStack(spacing: 8) {
                    Text(record.status.displayName)
                        .font(.caption)
                        .foregroundColor(statusColor)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(statusColor.opacity(0.1))
                        .cornerRadius(4)
                    
                    if record.duration > 0 {
                        Text(formatProgress())
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                
                // 最后播放时间
                Text("上次播放: \(formatDate(record.lastPlayedDate))")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                
                // 播放进度条
                if record.duration > 0 {
                    ProgressView(value: record.progress)
                        .tint(statusColor)
                        .scaleEffect(y: 0.5)
                }
            }
            
            Spacer()
            
            // 播放按钮
            Button {
                resumeEpisode()
            } label: {
                if isLoading {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: .accentColor))
                        .scaleEffect(0.8)
                        .frame(width: 28, height: 28)
                } else {
                    Image(systemName: playButtonIcon)
                        .font(.system(size: 28))
                        .foregroundColor(.accentColor)
                }
            }
            .disabled(isLoading)
        }
        .padding(.vertical, 4)
        .opacity(isLoading ? 0.7 : 1.0)
        .animation(.easeInOut(duration: 0.2), value: isLoading)
    }
    
    // 获取episode标题
    private var episodeTitle: String {
        // 首先尝试从playerService获取episode信息
        if let episode = playerService.getEpisodeFromRecord(record) {
            return episode.title
        }
        
        // 如果当前播放的就是这个episode
        if let currentEpisode = playerService.playbackState.currentEpisode,
           currentEpisode.id == record.episodeId {
            return currentEpisode.title
        }
        
        // 否则显示简化的ID
        return "Episode \(record.episodeId.prefix(8))..."
    }
    
    private var statusColor: Color {
        switch record.status {
        case .notPlayed:
            return .secondary
        case .playing:
            return .blue
        case .completed:
            return .green
        }
    }
    
    private var isCurrentlyPlaying: Bool {
        return playerService.playbackState.currentEpisode?.id == record.episodeId && 
               playerService.playbackState.isPlaying
    }
    
    private var playButtonIcon: String {
        if isCurrentlyPlaying {
            return "pause.circle.fill"
        } else if playerService.playbackState.currentEpisode?.id == record.episodeId {
            return "play.circle.fill"
        } else {
            return "play.circle"
        }
    }
    
    private func formatProgress() -> String {
        let currentMinutes = Int(record.currentTime) / 60
        let currentSeconds = Int(record.currentTime) % 60
        let totalMinutes = Int(record.duration) / 60
        let totalSeconds = Int(record.duration) % 60
        let progressPercent = Int(record.progress * 100)
        
        return String(format: "%d:%02d / %d:%02d (%d%%)", 
                     currentMinutes, currentSeconds, 
                     totalMinutes, totalSeconds, 
                     progressPercent)
    }
    
    private func formatDate(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }
    
    private func resumeEpisode() {
        // 防止重复点击
        guard !isLoading else { return }
        
        withAnimation {
            isLoading = true
        }
        
        // 使用新的播放记录恢复功能
        playerService.playEpisodeFromRecord(record)
        
        // 如果不是当前播放的节目，关闭播放列表
        if playerService.playbackState.currentEpisode?.id != record.episodeId {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                onDismiss()
            }
        }
        
        // 延迟重置加载状态
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            withAnimation {
                isLoading = false
            }
        }
    }
}

#Preview {
    struct PlaylistPreview: View {
        var body: some View {
            PlaylistView()
                .onAppear {
                    // 添加一些示例播放记录用于预览
                    let playerService = PodcastPlayerService.shared
                    
                    // 创建示例记录1
                    var record1 = EpisodePlaybackRecord(
                        episodeId: "episode-001", 
                        currentTime: 450, 
                        duration: 1800
                    )
                    record1.lastPlayedDate = Date().addingTimeInterval(-3600)
                    
                    // 创建示例记录2
                    var record2 = EpisodePlaybackRecord(
                        episodeId: "episode-002", 
                        currentTime: 1200, 
                        duration: 2400
                    )
                    record2.lastPlayedDate = Date().addingTimeInterval(-7200)
                    record2.isCompleted = true
                    
                    // 创建示例记录3
                    var record3 = EpisodePlaybackRecord(
                        episodeId: "episode-003", 
                        currentTime: 0, 
                        duration: 1500
                    )
                    record3.lastPlayedDate = Date().addingTimeInterval(-86400)
                    
                    // 添加到播放记录中（仅用于预览）
                    playerService.playbackRecords["episode-001"] = record1
                    playerService.playbackRecords["episode-002"] = record2
                    playerService.playbackRecords["episode-003"] = record3
                }
        }
    }
    
    return PlaylistPreview()
} 