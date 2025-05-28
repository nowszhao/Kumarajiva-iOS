import SwiftUI

struct PodcastDetailView: View {
    let podcast: Podcast
    @StateObject private var dataService = PodcastDataService.shared
    @StateObject private var playerService = PodcastPlayerService.shared
    @State private var isRefreshing = false
    
    // 使用稳定的episodes数组，避免频繁重新计算
    @State private var stableEpisodes: [PodcastEpisode] = []
    
    // 播放状态筛选
    @State private var selectedPlaybackStatus: EpisodePlaybackStatus? = nil
    @State private var showingStatusFilter = false
    
    // 计算筛选后的节目列表
    private var filteredEpisodes: [PodcastEpisode] {
        guard let status = selectedPlaybackStatus else {
            return stableEpisodes
        }
        
        return stableEpisodes.filter { episode in
            let episodeStatus = playerService.getPlaybackStatus(for: episode.id)
            return episodeStatus == status
        }
    }
    
    var body: some View {
        VStack(spacing: 0) {
        List {
            // 播客信息头部
            podcastHeaderView
                .listRowSeparator(.hidden)
                .listRowInsets(EdgeInsets())
            
            // 节目列表
            Section {
                    if stableEpisodes.isEmpty {
                    emptyEpisodesView
                } else {
                        ForEach(filteredEpisodes) { episode in
                        NavigationLink(destination: PodcastPlayerView(episode: episode)) {
                            EpisodeRowView(episode: episode)
                        }
                            .id("\(episode.id)_\(episode.subtitles.count)")  // 使用复合ID，但保持稳定性
                    }
                }
            } header: {
                VStack(spacing: 8) {
                    // 第一行：标题和总数
                    HStack {
                        Text("节目列表")
                            .font(.headline)
                        
                        Spacer()
                        
                        Text("\(filteredEpisodes.count) / \(stableEpisodes.count) 集")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    
                    // 第二行：播放状态筛选
                    HStack {
                        Text("播放状态:")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        
                        Spacer()
                        
                        // 播放状态筛选按钮
                        Menu {
                            Button {
                                selectedPlaybackStatus = nil
                            } label: {
                                HStack {
                                    Text("全部")
                                    if selectedPlaybackStatus == nil {
                                        Image(systemName: "checkmark")
                                    }
                                }
                            }
                            
                            ForEach(EpisodePlaybackStatus.allCases, id: \.self) { status in
                                Button {
                                    selectedPlaybackStatus = status
                                } label: {
                                    HStack {
                                        Image(systemName: status.icon)
                                        Text(status.displayName)
                                        if selectedPlaybackStatus == status {
                                            Image(systemName: "checkmark")
                                        }
                                    }
                                }
                            }
                        } label: {
                            HStack(spacing: 4) {
                                if let status = selectedPlaybackStatus {
                                    Image(systemName: status.icon)
                                        .foregroundColor(statusColor(for: status))
                                    Text(status.displayName)
                                        .foregroundColor(statusColor(for: status))
                                } else {
                                    Image(systemName: "line.3.horizontal.decrease.circle")
                                        .foregroundColor(.accentColor)
                                    Text("全部")
                                        .foregroundColor(.accentColor)
                                }
                                Image(systemName: "chevron.down")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            .font(.subheadline)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(Color(.systemGray6))
                            .cornerRadius(8)
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
            }
        }
        .listStyle(PlainListStyle())
            
            // 底部迷你播放器
            MiniPlayerView()
        }
        .navigationTitle(podcast.title)
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    refreshPodcast()
                } label: {
                    if isRefreshing {
                        ProgressView()
                            .scaleEffect(0.8)
                    } else {
                        Image(systemName: "arrow.clockwise")
                    }
                }
                .disabled(isRefreshing)
            }
        }
        .refreshable {
            await refreshPodcastAsync()
        }
        .onAppear {
            updateStableEpisodes()
        }
        .onReceive(dataService.$podcasts) { _ in
            // 只有在没有播放或者不在生成字幕时才更新
            if !playerService.playbackState.isPlaying && !playerService.isGeneratingSubtitles {
                DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                    updateStableEpisodes()
                }
            } else {
                print("🎧 [Detail] 跳过episodes更新，当前正在播放或生成字幕")
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("NavigateToPlayer"))) { notification in
            if let episode = notification.object as? PodcastEpisode {
                navigateToPlayer(episode: episode)
            }
        }
    }
    
    private func navigateToPlayer(episode: PodcastEpisode) {
        // 这里可以通过NavigationLink或其他方式导航到播放器
        // 暂时先打印，实际实现可能需要状态管理
        print("🎧 [PodcastDetail] 导航到播放器: \(episode.title)")
    }
    
    // MARK: - 子视图
    
    private var podcastHeaderView: some View {
        VStack(spacing: 16) {
            // 播客封面和基本信息
            HStack(alignment: .top, spacing: 16) {
                AsyncImage(url: URL(string: podcast.imageURL ?? "")) { image in
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } placeholder: {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.gray.opacity(0.3))
                        .overlay {
                            Image(systemName: "headphones")
                                .font(.title)
                                .foregroundColor(.gray)
                        }
                }
                .frame(width: 120, height: 120)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                
                VStack(alignment: .leading, spacing: 8) {
                    Text(podcast.title)
                        .font(.title2)
                        .fontWeight(.bold)
                        .lineLimit(3)
                    
                    if let author = podcast.author {
                        Text(author)
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .lineLimit(2)
                    }
                    
                    if let language = podcast.language {
                        Text("语言: \(language)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    
                    Text("更新时间: \(formatDate(podcast.updatedAt))")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
            }
            
            // 播客描述
            if !podcast.description.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("简介")
                        .font(.headline)
                    
                    Text(podcast.description)
                        .font(.body)
                        .foregroundColor(.secondary)
                        .lineLimit(nil)
                }
            }
        }
        .padding()
        .background(Color(.systemGroupedBackground))
    }
    
    private var emptyEpisodesView: some View {
        VStack(spacing: 16) {
            Image(systemName: "music.note.list")
                .font(.system(size: 40))
                .foregroundColor(.secondary)
            
            Text("暂无节目")
                .font(.headline)
                .foregroundColor(.secondary)
            
            Text("点击右上角刷新按钮获取最新节目")
                .font(.body)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
    }
    
    // MARK: - 方法
    
    private func statusColor(for status: EpisodePlaybackStatus) -> Color {
        switch status {
        case .notPlayed:
            return .gray
        case .playing:
            return .blue
        case .completed:
            return .green
        }
    }
    
    private func refreshPodcast() {
        isRefreshing = true
        
        Task {
            do {
                try await dataService.refreshPodcast(podcast)
                await MainActor.run {
                    isRefreshing = false
                }
            } catch {
                await MainActor.run {
                    isRefreshing = false
                }
                print("🎧 [Detail] 刷新失败: \(error)")
            }
        }
    }
    
    private func refreshPodcastAsync() async {
        do {
            try await dataService.refreshPodcast(podcast)
        } catch {
            print("🎧 [Detail] 刷新失败: \(error)")
        }
    }
    
    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter.string(from: date)
    }
    
    // MARK: - 私有方法
    
    private func updateStableEpisodes() {
        let newEpisodes = dataService.getEpisodes(for: podcast)
        
        // 只有当episodes真正发生变化时才更新
        if !areEpisodesEqual(stableEpisodes, newEpisodes) {
            stableEpisodes = newEpisodes
            print("🎧 [Detail] 更新稳定episodes列表，共 \(stableEpisodes.count) 集")
        }
    }
    
    private func areEpisodesEqual(_ episodes1: [PodcastEpisode], _ episodes2: [PodcastEpisode]) -> Bool {
        guard episodes1.count == episodes2.count else { return false }
        
        for (index, episode1) in episodes1.enumerated() {
            let episode2 = episodes2[index]
            if episode1.id != episode2.id || episode1.subtitles.count != episode2.subtitles.count {
                return false
            }
        }
        
        return true
    }
}

// MARK: - 节目行视图
struct EpisodeRowView: View {
    let episode: PodcastEpisode
    @StateObject private var taskManager = SubtitleGenerationTaskManager.shared
    @StateObject private var playerService = PodcastPlayerService.shared
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // 标题和时长
            HStack {
                // 播放状态指示器
                playbackStatusIndicator
                
                Text(episode.title)
                    .font(.headline)
                    .lineLimit(2)
                
                Spacer()
                
                Text(formatDuration(episode.duration))
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.gray.opacity(0.2))
                    .cornerRadius(8)
            }
            
            // 描述
            if !episode.description.isEmpty {
                Text(episode.description)
                    .font(.body)
                    .foregroundColor(.secondary)
                    .lineLimit(3)
            }
            
            // 发布日期和状态信息
            HStack {
                Text(formatDate(episode.publishDate))
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                // 播放进度（如果有）
                if playerService.getPlaybackProgress(for: episode.id) > 0 {
                    Text("进度: \(Int(playerService.getPlaybackProgress(for: episode.id) * 100))%")
                        .font(.caption)
                        .foregroundColor(.blue)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.blue.opacity(0.1))
                        .cornerRadius(4)
                }
                
                Spacer()
                
                // 字幕状态
                subtitleStatusView
            }
        }
        .padding(.vertical, 4)
    }
    
    // 播放状态指示器
    private var playbackStatusIndicator: some View {
        let status = playerService.getPlaybackStatus(for: episode.id)
        
        return Image(systemName: status.icon)
            .font(.caption)
            .foregroundColor(statusColor(for: status))
            .frame(width: 16, height: 16)
    }
    
    private func statusColor(for status: EpisodePlaybackStatus) -> Color {
        switch status {
        case .notPlayed:
            return .gray
        case .playing:
            return .blue
        case .completed:
            return .green
        }
    }
    
    // 字幕状态视图
    private var subtitleStatusView: some View {
        Group {
            if let task = taskManager.getTask(for: episode.id), task.isActive {
                // 有活动的字幕生成任务
                HStack(spacing: 4) {
                    ProgressView()
                        .scaleEffect(0.6)
                    Text("解析中")
                        .font(.caption)
                        .foregroundColor(.orange)
                }
            } else if !episode.subtitles.isEmpty {
                // 有字幕
                Label("有字幕", systemImage: "captions.bubble")
                    .font(.caption)
                    .foregroundColor(.green)
            }
        }
    }
    
    private func formatDuration(_ duration: TimeInterval) -> String {
        let hours = Int(duration) / 3600
        let minutes = Int(duration) % 3600 / 60
        let seconds = Int(duration) % 60
        
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        } else {
            return String(format: "%d:%02d", minutes, seconds)
        }
    }
    
    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        return formatter.string(from: date)
    }
}

// MARK: - 预览
#Preview {
    NavigationView {
        PodcastDetailView(podcast: Podcast(
            title: "示例播客",
            description: "这是一个示例播客的描述，用于展示播客详情页面的布局和功能。",
            rssURL: "https://example.com/rss",
            author: "示例作者",
            language: "中文",
            episodes: [
                PodcastEpisode(
                    title: "第一集：开始学习",
                    description: "这是第一集的描述内容。",
                    audioURL: "https://example.com/episode1.mp3",
                    duration: 1800,
                    publishDate: Date()
                )
            ]
        ))
    }
} 