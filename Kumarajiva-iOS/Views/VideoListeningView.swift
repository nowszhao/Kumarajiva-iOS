import SwiftUI

struct VideoListeningView: View {
    @StateObject private var dataService = YouTubeDataService.shared
    @State private var showingAddYouTuber = false
    @State private var showingAlert = false
    @State private var alertMessage = ""
    
    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                ZStack {
                    if dataService.youtubers.isEmpty && !dataService.isLoading {
                        emptyStateView
                    } else {
                        youtuberListView
                    }
                    
                    if dataService.isLoading {
                        loadingView
                    }
                }
                
                // 底部迷你播放器
                MiniPlayerView()
            }
            .navigationTitle("听视频")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        showingAddYouTuber = true
                    } label: {
                        Image(systemName: "plus")
                            .font(.title2)
                    }
                }
            }
            .sheet(isPresented: $showingAddYouTuber) {
                AddYouTuberView()
            }
            .alert("提示", isPresented: $showingAlert) {
                Button("确定", role: .cancel) { }
                
                // 根据错误类型提供不同的操作选项
                if alertMessage.contains("配额已用完") {
                    Button("了解详情") {
                        // 可以在这里添加解释YouTube API配额的信息
                        print("📺 [View] 用户查看配额详情")
                    }
                } else {
                    Button("重新加载数据") {
                        Task {
                            await dataService.forceReloadData()
                        }
                    }
                }
            } message: {
                if alertMessage.contains("配额已用完") {
                    Text(alertMessage + "\n\n💡 说明：每日API调用次数有限，建议:\n• 明天再试\n• 减少频繁刷新\n• 优先播放已缓存内容")
                } else {
                    Text(alertMessage)
                }
            }
            .onReceive(dataService.$errorMessage) { errorMessage in
                if let error = errorMessage {
                    alertMessage = error
                    showingAlert = true
                }
            }
            .onAppear {
                print("📺 [View] VideoListeningView 出现")
                print("📺 [View] 当前YouTuber数量: \(dataService.youtubers.count)")
                
                // 视图出现时验证数据
                Task {
                    if dataService.youtubers.isEmpty {
                        print("📺 [View] 视图出现时发现YouTuber列表为空")
                        await dataService.forceReloadData()
                        
                        if dataService.youtubers.isEmpty {
                            print("📺 [View] 重新加载后仍然为空，这可能是首次使用")
                        } else {
                            print("📺 [View] 数据恢复成功，现在有 \(dataService.youtubers.count) 个YouTuber")
                        }
                    } else {
                        print("📺 [View] YouTuber数据正常，共 \(dataService.youtubers.count) 个YouTuber")
                    }
                }
            }
        }
    }
    
    // MARK: - 子视图
    
    private var emptyStateView: some View {
        VStack(spacing: 20) {
            Image(systemName: "play.rectangle")
                .font(.system(size: 60))
                .foregroundColor(.secondary)
            
            Text("还没有订阅YouTuber")
                .font(.title2)
                .fontWeight(.medium)
            
            Text("点击右上角的 + 号订阅您喜欢的YouTuber")
                .font(.body)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
            
            Button {
                showingAddYouTuber = true
            } label: {
                Label("订阅YouTuber", systemImage: "plus")
                    .font(.headline)
                    .foregroundColor(.white)
                    .padding()
                    .background(Color.accentColor)
                    .cornerRadius(12)
            }
            
            // YouTube功能说明
            VStack(spacing: 8) {
                HStack {
                    Image(systemName: "play.circle")
                        .foregroundColor(.red)
                    Text("YouTube听力练习")
                        .font(.headline)
                        .foregroundColor(.red)
                }
                
                Text("订阅YouTuber后，可以收听他们的视频并生成字幕进行听力练习")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding()
            .background(Color.red.opacity(0.1))
            .cornerRadius(12)
        }
        .padding()
    }
    
    private var youtuberListView: some View {
        List {
            ForEach(dataService.youtubers) { youtuber in
                NavigationLink(destination: YouTuberDetailView(youtuber: youtuber)) {
                    YouTuberRowView(youtuber: youtuber)
                }
            }
            .onDelete(perform: deleteYouTuber)
        }
        .listStyle(PlainListStyle())
        .refreshable {
            await refreshAllYouTubers()
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
    
    private func deleteYouTuber(at offsets: IndexSet) {
        for index in offsets {
            let youtuber = dataService.youtubers[index]
            do {
                try dataService.unsubscribeFromYouTuber(youtuber)
            } catch {
                alertMessage = "取消订阅失败: \(error.localizedDescription)"
                showingAlert = true
            }
        }
    }
    
    private func refreshAllYouTubers() async {
        await dataService.refreshAllYouTubers()
    }
}

// MARK: - YouTuber行视图
struct YouTuberRowView: View {
    let youtuber: YouTuber
    
    var body: some View {
        HStack(spacing: 12) {
            // YouTuber头像
            AsyncImage(url: URL(string: youtuber.thumbnailURL ?? "")) { image in
                image
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } placeholder: {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.gray.opacity(0.3))
                    .overlay {
                        Image(systemName: "person.circle")
                            .font(.title2)
                            .foregroundColor(.gray)
                    }
            }
            .frame(width: 60, height: 60)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            
            // YouTuber信息
            VStack(alignment: .leading, spacing: 4) {
                Text(youtuber.title)
                    .font(.headline)
                    .lineLimit(2)
                
                if let description = youtuber.description {
                    Text(description)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
                
                HStack {
                    if let subscriberCount = youtuber.subscriberCount {
                        Text(subscriberCount)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    
                    Text("\(youtuber.videoCount) 个视频")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    Spacer()
                    
                    Text(formatDate(youtuber.updatedAt))
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding(.vertical, 4)
        .onAppear {
            print("📺 [YouTuberRow] 显示YouTuber: \(youtuber.title)")
            print("📺 [YouTuberRow] videoCount属性: \(youtuber.videoCount)")
            print("📺 [YouTuberRow] videos数组长度: \(youtuber.videos.count)")
        }
    }
    
    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        return formatter.string(from: date)
    }
}

// MARK: - 预览
#Preview {
    VideoListeningView()
} 
