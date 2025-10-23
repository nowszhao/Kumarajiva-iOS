import SwiftUI

struct YouTuberDetailView: View {
    let youtuber: YouTuber
    @StateObject private var dataService = YouTubeDataService.shared
    @State private var isRefreshing = false
    
    // 计算属性：从dataService获取最新的YouTuber数据
    private var currentYouTuber: YouTuber {
        return dataService.youtubers.first { $0.channelId == youtuber.channelId } ?? youtuber
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // 视频列表
            if currentYouTuber.videos.isEmpty && !isRefreshing {
                emptyVideosView
            } else {
                videoListView
            }
            
            // 底部迷你播放器
            MiniPlayerView()
        }
        .navigationTitle(currentYouTuber.title)
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    refreshVideos()
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.title2)
                }
                .disabled(isRefreshing)
            }
        }
        .onAppear {
            print("📺 [YouTuberDetail] 页面出现，YouTuber: \(currentYouTuber.title)")
            print("📺 [YouTuberDetail] 当前视频数量: \(currentYouTuber.videos.count)")
            
            // 如果视频列表为空，自动加载
            if currentYouTuber.videos.isEmpty {
                refreshVideos()
            }
        }
    }
    
    // MARK: - 子视图
    
    private var youtuberHeader: some View {
        VStack(spacing: 12) {
            // YouTuber头像和信息
            HStack(spacing: 16) {
                AsyncImage(url: URL(string: currentYouTuber.thumbnailURL ?? "")) { image in
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } placeholder: {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.gray.opacity(0.3))
                        .overlay {
                            Image(systemName: "person.circle")
                                .font(.title)
                                .foregroundColor(.gray)
                        }
                }
                .frame(width: 80, height: 80)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                
                VStack(alignment: .leading, spacing: 4) {
                    Text(currentYouTuber.title)
                        .font(.title2)
                        .fontWeight(.bold)
                    
                    if let description = currentYouTuber.description {
                        Text(description)
                            .font(.body)
                            .foregroundColor(.secondary)
                            .lineLimit(2)
                    }
                    
                    HStack {
                        if let subscriberCount = currentYouTuber.subscriberCount {
                            Label(subscriberCount, systemImage: "person.2")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        
                        Label("\(currentYouTuber.videoCount) 个视频", systemImage: "play.rectangle")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                
                Spacer()
            }
            .padding()
            .background(Color(.systemGray6))
            .cornerRadius(16)
        }
        .padding(.horizontal)
    }
    
    private var emptyVideosView: some View {
        VStack(spacing: 20) {
            youtuberHeader
            
            Spacer()
            
            VStack(spacing: 16) {
                Image(systemName: "play.rectangle")
                    .font(.system(size: 60))
                    .foregroundColor(.secondary)
                
                Text("暂无视频")
                    .font(.title2)
                    .fontWeight(.medium)
                
                Text("点击右上角刷新按钮获取最新视频")
                    .font(.body)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                
                Button {
                    refreshVideos()
                } label: {
                    Label("获取视频", systemImage: "arrow.clockwise")
                        .font(.headline)
                        .foregroundColor(.white)
                        .padding()
                        .background(Color.accentColor)
                        .cornerRadius(12)
                }
                .disabled(isRefreshing)
            }
            
            Spacer()
        }
    }
    
    private var videoListView: some View {
        VStack(spacing: 0) {
            youtuberHeader
                .padding(.bottom, 8)
            
            List {
                Section {
                    ForEach(currentYouTuber.videos) { video in
                        NavigationLink(destination: VideoPlayerView_New(video: video)) {
                            VideoRowView(video: video)
                        }
                    }
                } header: {
                    HStack {
                        Text("视频列表")
                            .font(.headline)
                        
                        Spacer()
                        
                        if isRefreshing {
                            ProgressView()
                                .scaleEffect(0.8)
                        }
                    }
                }
            }
            .listStyle(PlainListStyle())
            .refreshable {
                refreshVideos()
            }
        }
    }
    
    // MARK: - 方法
    
    private func refreshVideos() {
        guard !isRefreshing else { return }
        
        print("📺 [YouTuberDetail] 开始刷新视频，YouTuber: \(currentYouTuber.title)")
        isRefreshing = true
        
        Task {
            // 使用原始的youtuber对象来刷新，因为refreshYouTuberVideos会通过channelId查找
            await dataService.refreshYouTuberVideos(youtuber)
            
            await MainActor.run {
                print("📺 [YouTuberDetail] 刷新完成，最新视频数量: \(currentYouTuber.videos.count)")
                isRefreshing = false
            }
        }
    }
}

// MARK: - 视频行视图
struct VideoRowView: View {
    let video: YouTubeVideo
    
    var body: some View {
        HStack(spacing: 12) {
            // 视频缩略图
            AsyncImage(url: URL(string: video.thumbnailURL ?? "")) { image in
                image
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } placeholder: {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.gray.opacity(0.3))
                    .overlay {
                        Image(systemName: "play.rectangle")
                            .font(.title2)
                            .foregroundColor(.gray)
                    }
            }
            .frame(width: 120, height: 68)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(
                // 时长标签
                VStack {
                    Spacer()
                    HStack {
                        Spacer()
                        Text(formatDuration(video.duration))
                            .font(.caption)
                            .fontWeight(.semibold)
                            .foregroundColor(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.black.opacity(0.7))
                            .cornerRadius(4)
                            .padding(4)
                    }
                }
            )
            
            // 视频信息
            VStack(alignment: .leading, spacing: 4) {
                Text(video.title)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .lineLimit(2)
                
                HStack {
                    if let viewCount = video.viewCount {
                        Text(viewCount)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    
                    Text("•")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    Text(formatDate(video.publishDate))
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                // 字幕状态
                if video.hasSubtitles {
                    Label("有字幕", systemImage: "captions.bubble")
                        .font(.caption)
                        .foregroundColor(.green)
                }
                
                Spacer()
            }
            
            Spacer()
        }
        .padding(.vertical, 4)
    }
    
    private func formatDuration(_ duration: TimeInterval) -> String {
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
    
    private func formatDate(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}

// MARK: - 预览
#Preview {
    NavigationView {
        YouTuberDetailView(youtuber: YouTuber.example)
    }
} 