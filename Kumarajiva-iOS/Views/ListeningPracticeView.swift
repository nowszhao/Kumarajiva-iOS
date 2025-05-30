import SwiftUI

struct ListeningPracticeView: View {
    @StateObject private var dataService = PodcastDataService.shared
    @State private var showingAddPodcast = false
    @State private var showingAlert = false
    @State private var alertMessage = ""
    
    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                ZStack {
                    if dataService.podcasts.isEmpty && !dataService.isLoading {
                        emptyStateView
                    } else {
                        podcastListView
                    }
                    
                    if dataService.isLoading {
                        loadingView
                    }
                }
                
                // 底部迷你播放器
                MiniPlayerView()
            }
            .navigationTitle("练听力")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        showingAddPodcast = true
                    } label: {
                        Image(systemName: "plus")
                            .font(.title2)
                    }
                }
                
                // 添加调试按钮（仅在DEBUG模式下显示）
                #if DEBUG
                ToolbarItem(placement: .navigationBarLeading) {
                    Menu {
                        Button("启动诊断") {
                            dataService.startupDiagnostics()
                        }
                        
                        Button("强制重新加载数据") {
                            Task {
                                await dataService.forceReloadData()
                            }
                        }
                        
                        Button("验证数据完整性") {
                            Task {
                                await dataService.validateAndRepairData()
                            }
                        }
                        
                        Button("检查存储状态") {
                            PersistentStorageManager.shared.checkStorageStatus()
                        }
                        
                        Button("调试字幕缓存") {
                            dataService.debugSubtitleCache()
                        }
                        
                        Button("清除所有数据") {
                            do {
                                try PersistentStorageManager.shared.clearAllData()
                                Task {
                                    await dataService.forceReloadData()
                                }
                            } catch {
                                print("清除数据失败: \(error)")
                            }
                        }
                    } label: {
                        Image(systemName: "gear")
                            .foregroundColor(.secondary)
                    }
                }
                #endif
            }
            .sheet(isPresented: $showingAddPodcast) {
                AddPodcastView()
            }
            .alert("提示", isPresented: $showingAlert) {
                Button("确定", role: .cancel) { }
                Button("重新加载数据") {
                    Task {
                        await dataService.forceReloadData()
                    }
                }
            } message: {
                Text(alertMessage)
            }
            .onReceive(dataService.$errorMessage) { errorMessage in
                if let error = errorMessage {
                    alertMessage = error
                    showingAlert = true
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("NavigateToPlayer"))) { notification in
                if let episode = notification.object as? PodcastEpisode {
                    navigateToPlayer(episode: episode)
                }
            }
            .onAppear {
                print("🎧 [View] ListeningPracticeView 出现")
                print("🎧 [View] 当前播客数量: \(dataService.podcasts.count)")
                
                // 视图出现时验证数据
                Task {
                    if dataService.podcasts.isEmpty {
                        print("🎧 [View] 视图出现时发现播客列表为空，执行诊断和恢复")
                        
                        // 先执行诊断
                        dataService.startupDiagnostics()
                        
                        // 尝试强制重新加载数据
                        await dataService.forceReloadData()
                        
                        // 如果还是空的，检查是否真的应该有数据
                        if dataService.podcasts.isEmpty {
                            print("🎧 [View] 重新加载后仍然为空，这可能是首次使用应用")
                        } else {
                            print("🎧 [View] 数据恢复成功，现在有 \(dataService.podcasts.count) 个播客")
                        }
                    } else {
                        print("🎧 [View] 播客数据正常，共 \(dataService.podcasts.count) 个播客")
                    }
                }
            }
        }
    }
    
    private func navigateToPlayer(episode: PodcastEpisode) {
        // 这里可以通过NavigationLink或其他方式导航到播放器
        // 暂时先打印，实际实现可能需要状态管理
        print("🎧 [ListeningPractice] 导航到播放器: \(episode.title)")
    }
    
    // MARK: - 子视图
    
    private var emptyStateView: some View {
        VStack(spacing: 20) {
            Image(systemName: "headphones")
                .font(.system(size: 60))
                .foregroundColor(.secondary)
            
            Text("还没有播客")
                .font(.title2)
                .fontWeight(.medium)
            
            Text("点击右上角的 + 号添加播客节目")
                .font(.body)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
            
            Button {
                showingAddPodcast = true
            } label: {
                Label("添加播客", systemImage: "plus")
                    .font(.headline)
                    .foregroundColor(.white)
                    .padding()
                    .background(Color.accentColor)
                    .cornerRadius(12)
            }
            
            // WhisperKit配置提示
            VStack(spacing: 8) {
                HStack {
                    Image(systemName: "waveform.and.mic")
                        .foregroundColor(.blue)
                    Text("自动字幕功能")
                        .font(.headline)
                        .foregroundColor(.blue)
                }
                
                Text("要启用播客自动字幕生成，请前往\"我的\"页面设置中配置WhisperKit语音识别服务")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding()
            .background(Color.blue.opacity(0.1))
            .cornerRadius(12)
        }
        .padding()
    }
    
    private var podcastListView: some View {
        List {
            ForEach(dataService.podcasts) { podcast in
                NavigationLink(destination: PodcastDetailView(podcast: podcast)) {
                    PodcastRowView(podcast: podcast)
                }
            }
            .onDelete(perform: deletePodcast)
        }
        .listStyle(PlainListStyle())
        .refreshable {
            await refreshAllPodcasts()
        }
    }
    
    private var loadingView: some View {
        VStack(spacing: 16) {
            ProgressView()
                .scaleEffect(1.2)
            
            Text("正在加载...")
                .font(.body)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black.opacity(0.1))
    }
    
    // MARK: - 方法
    
    private func deletePodcast(at offsets: IndexSet) {
        for index in offsets {
            let podcast = dataService.podcasts[index]
            do {
                try dataService.deletePodcast(podcast)
            } catch {
                alertMessage = "删除失败: \(error.localizedDescription)"
                showingAlert = true
            }
        }
    }
    
    private func refreshAllPodcasts() async {
        for podcast in dataService.podcasts {
            do {
                try await dataService.refreshPodcast(podcast)
            } catch {
                print("🎧 [View] 刷新播客失败: \(error)")
            }
        }
    }
}

// MARK: - 播客行视图
struct PodcastRowView: View {
    let podcast: Podcast
    @StateObject private var taskManager = SubtitleGenerationTaskManager.shared
    
    var body: some View {
        HStack(spacing: 12) {
            // 播客封面
            AsyncImage(url: URL(string: podcast.imageURL ?? "")) { image in
                image
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } placeholder: {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.gray.opacity(0.3))
                    .overlay {
                        Image(systemName: "headphones")
                            .font(.title2)
                            .foregroundColor(.gray)
                    }
            }
            .frame(width: 60, height: 60)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            
            // 播客信息
            VStack(alignment: .leading, spacing: 4) {
                Text(podcast.title)
                    .font(.headline)
                    .lineLimit(2)
                
                if let author = podcast.author {
                    Text(author)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
                
                HStack {
                    Text("\(podcast.episodes.count) 集")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    Spacer()
                    
                    // 字幕生成状态
                    subtitleStatusView
                    
                    Text(formatDate(podcast.updatedAt))
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            
        }
        .padding(.vertical, 4)
    }
    
    // 字幕状态视图
    private var subtitleStatusView: some View {
        Group {
            if let activeTask = getActiveSubtitleTask() {
                // 有活动的字幕生成任务
                HStack(spacing: 4) {
                    ProgressView()
                        .scaleEffect(0.6)
                    Text("解析中")
                        .font(.caption)
                        .foregroundColor(.orange)
                }
            } else if hasSubtitles {
                // 有字幕
                Label("有字幕", systemImage: "captions.bubble")
                    .font(.caption)
                    .foregroundColor(.green)
            }
        }
    }
    
    // 获取活动的字幕生成任务
    private func getActiveSubtitleTask() -> SubtitleGenerationTask? {
        for episode in podcast.episodes {
            if let task = taskManager.getTask(for: episode.id), task.isActive {
                return task
            }
        }
        return nil
    }
    
    // 检查是否有字幕
    private var hasSubtitles: Bool {
        return podcast.episodes.contains { !$0.subtitles.isEmpty }
    }
    
    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        return formatter.string(from: date)
    }
}

// MARK: - 预览
#Preview {
    ListeningPracticeView()
} 