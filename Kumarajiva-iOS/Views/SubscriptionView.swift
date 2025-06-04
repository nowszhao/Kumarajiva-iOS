import SwiftUI

// 统一的订阅项类型
enum SubscriptionItem: Identifiable {
    case podcast(Podcast)
    case youtuber(YouTuber)
    
    var id: String {
        switch self {
        case .podcast(let podcast): return "podcast-\(podcast.id)"
        case .youtuber(let youtuber): return "youtuber-\(youtuber.id)"
        }
    }
    
    // 用于排序的添加时间（Podcast: createdAt，YouTuber: subscribedAt）
    var addedAt: Date {
        switch self {
        case .podcast(let podcast): return podcast.createdAt
        case .youtuber(let youtuber): return youtuber.subscribedAt
        }
    }
}

// 用于 alert 的 Identifiable 包装类型
struct AlertMessage: Identifiable {
    let id = UUID()
    let message: String
}

struct SubscriptionView: View {
    @StateObject private var podcastService = PodcastDataService.shared
    @StateObject private var youtubeService = YouTubeDataService.shared
    @State private var showingAddSheet = false
    @State private var addType: AddType? = nil
    @State private var alertMessage: AlertMessage? = nil
    
    enum AddType: Identifiable {
        case podcast, youtuber
        var id: Int { hashValue }
    }
    
    // 聚合并排序
    private var allSubscriptions: [SubscriptionItem] {
        let podcasts = podcastService.podcasts.map { SubscriptionItem.podcast($0) }
        let youtubers = youtubeService.youtubers.map { SubscriptionItem.youtuber($0) }
        return (podcasts + youtubers).sorted { $0.addedAt > $1.addedAt }
    }
    
    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                ZStack {
                    if allSubscriptions.isEmpty && !podcastService.isLoading && !youtubeService.isLoading {
                        emptyStateView
                    } else {
                        subscriptionListView
                    }
                    if podcastService.isLoading || youtubeService.isLoading {
                        loadingView
                    }
                }
                MiniPlayerView()
            }
            .navigationTitle("订阅")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: { showingAddSheet = true }) {
                        Image(systemName: "plus")
                            .font(.title2)
                    }
                }
            }
            .actionSheet(isPresented: $showingAddSheet) {
                ActionSheet(
                    title: Text("添加订阅"),
                    buttons: [
                        .default(Text("添加播客")) { addType = .podcast },
                        .default(Text("添加YouTuber")) { addType = .youtuber },
                        .cancel()
                    ]
                )
            }
            .sheet(item: $addType) { type in
                switch type {
                case .podcast: AddPodcastView()
                case .youtuber: AddYouTuberView()
                }
            }
            .alert(item: $alertMessage) { msg in
                Alert(title: Text("提示"), message: Text(msg.message), dismissButton: .default(Text("确定")))
            }
            .onReceive(podcastService.$errorMessage) { error in
                if let error = error { alertMessage = AlertMessage(message: error) }
            }
            .onReceive(youtubeService.$errorMessage) { error in
                if let error = error { alertMessage = AlertMessage(message: error) }
            }
        }
    }
    
    // MARK: - 列表视图
    private var subscriptionListView: some View {
        List {
            ForEach(allSubscriptions) { item in
                NavigationLink(destination: destinationView(for: item)) {
                    SubscriptionRowView(item: item)
                }
            }
            .onDelete(perform: deleteSubscription)
        }
        .listStyle(PlainListStyle())
        .refreshable {
            await refreshAll()
        }
    }
    
    // MARK: - 空状态
    private var emptyStateView: some View {
        VStack(spacing: 20) {
            Image(systemName: "star")
                .font(.system(size: 60))
                .foregroundColor(.secondary)
            Text("还没有订阅内容")
                .font(.title2)
                .fontWeight(.medium)
            Text("点击右上角的 + 号添加播客或YouTuber")
                .font(.body)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding()
    }
    
    // MARK: - 加载视图
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
    
    // MARK: - 跳转
    @ViewBuilder
    private func destinationView(for item: SubscriptionItem) -> some View {
        switch item {
        case .podcast(let podcast): PodcastDetailView(podcast: podcast)
        case .youtuber(let youtuber): YouTuberDetailView(youtuber: youtuber)
        }
    }
    
    // MARK: - 删除
    private func deleteSubscription(at offsets: IndexSet) {
        let items = allSubscriptions
        for index in offsets {
            let item = items[index]
            switch item {
            case .podcast(let podcast):
                do { try podcastService.deletePodcast(podcast) }
                catch { alertMessage = AlertMessage(message: "删除播客失败: \(error.localizedDescription)") }
            case .youtuber(let youtuber):
                do { try youtubeService.unsubscribeFromYouTuber(youtuber) }
                catch { alertMessage = AlertMessage(message: "取消订阅失败: \(error.localizedDescription)") }
            }
        }
    }
    
    // MARK: - 刷新
    private func refreshAll() async {
        await podcastService.forceReloadData()
        await youtubeService.forceReloadData()
    }
}

// 小类型图标组件
struct SubscriptionTypeIcon: View {
    enum Kind { case podcast, youtuber }
    let kind: Kind
    
    var body: some View {
        Image(systemName: kind == .podcast ? "headphones" : "play.rectangle.fill")
            .font(.caption2)
            .foregroundColor(kind == .podcast ? .blue : .red)
    }
}

// SubscriptionItem 类型判断扩展
extension SubscriptionItem {
    var isPodcast: Bool {
        if case .podcast = self { return true }
        return false
    }
}

// 自定义订阅行视图
struct SubscriptionRowView: View {
    let item: SubscriptionItem
    
    var body: some View {
        HStack(spacing: 12) {
            // 封面图
            coverImage
                .frame(width: 60, height: 60)
                .clipShape(RoundedRectangle(cornerRadius: 8))
            
            // 内容信息
            VStack(alignment: .leading, spacing: 4) {
                // 标题
                Text(title)
                    .font(.headline)
                    .lineLimit(2)
                
                // 描述/作者
                if let subtitle = subtitle {
                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
                
                // 底部状态行（带类型图标）
                HStack(spacing: 6) {
                    SubscriptionTypeIcon(kind: item.isPodcast ? .podcast : .youtuber)
                    
                    Text(statusText)
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    Spacer()
                    
                    // 额外状态（如字幕生成状态）
                    extraStatusView
                    
                    Text(formattedDate)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding(.vertical, 4)
    }
    
    // MARK: - 计算属性
    
    @ViewBuilder
    private var coverImage: some View {
        switch item {
        case .podcast(let podcast):
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
        case .youtuber(let youtuber):
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
        }
    }
    
    private var title: String {
        switch item {
        case .podcast(let podcast): return podcast.title
        case .youtuber(let youtuber): return youtuber.title
        }
    }
    
    private var subtitle: String? {
        switch item {
        case .podcast(let podcast): return podcast.author
        case .youtuber(let youtuber): return youtuber.description
        }
    }
    
    private var statusText: String {
        switch item {
        case .podcast(let podcast): return "\(podcast.episodes.count) 集"
        case .youtuber(let youtuber): return "未知  \(youtuber.videoCount) 个视频"
        }
    }
    
    @ViewBuilder
    private var extraStatusView: some View {
        switch item {
        case .podcast(let podcast):
            // 播客的字幕状态
            if hasSubtitles(podcast) {
                Label("有字幕", systemImage: "captions.bubble")
                    .font(.caption)
                    .foregroundColor(.green)
            }
        case .youtuber:
            EmptyView()
        }
    }
    
    private var formattedDate: String {
        let date: Date
        switch item {
        case .podcast(let podcast): date = podcast.updatedAt
        case .youtuber(let youtuber): date = youtuber.updatedAt
        }
        
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        return formatter.string(from: date)
    }
    
    // 检查播客是否有字幕
    private func hasSubtitles(_ podcast: Podcast) -> Bool {
        return podcast.episodes.contains { !$0.subtitles.isEmpty }
    }
}

// MARK: - 预览
#Preview {
    SubscriptionView()
} 