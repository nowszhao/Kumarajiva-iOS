import SwiftUI

struct MiniPlayerView: View {
    @StateObject private var playerService = PodcastPlayerService.shared
    @State private var showingPlayer = false
    @State private var showingPlaylist = false
    
    var body: some View {
        if playerService.isPlaying, let episodeTitle = playerService.currentEpisodeTitle {
            VStack(spacing: 0) {
                Divider()
                
                HStack(spacing: 12) {
                    // 播客信息
                    VStack(alignment: .leading, spacing: 2) {
                        Text(episodeTitle)
                            .font(.subheadline)
                            .fontWeight(.medium)
                            .lineLimit(1)
                            .foregroundColor(.primary)
                        
                        Text("正在播放")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    
                    Spacer()
                    
                    // 播放控制按钮
                    HStack(spacing: 16) {
                        // 播放列表按钮
                        Button {
                            showingPlaylist = true
                        } label: {
                            Image(systemName: "list.bullet")
                                .font(.title3)
                                .foregroundColor(.accentColor)
                        }
                        
                        // 播放/暂停按钮
                        Button {
                            playerService.togglePlayPause()
                        } label: {
                            Image(systemName: playerService.playbackState.isPlaying ? "pause.fill" : "play.fill")
                                .font(.title2)
                                .foregroundColor(.accentColor)
                        }
                        
                        // 停止按钮
                        Button {
                            playerService.stopPlayback()
                        } label: {
                            Image(systemName: "stop.fill")
                                .font(.title3)
                                .foregroundColor(.red)
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(Color(.systemBackground))
                .onTapGesture {
                    // 点击区域跳转到播放器页面
                    if playerService.playbackState.currentEpisode != nil {
                        showingPlayer = true
                    }
                }
            }
            .shadow(color: .black.opacity(0.1), radius: 5, x: 0, y: -2)
            .sheet(isPresented: $showingPlayer) {
                if let episode = playerService.playbackState.currentEpisode {
                    NavigationView {
                        PodcastPlayerView_New(episode: episode)
                    }
                }
            }
            .sheet(isPresented: $showingPlaylist) {
                PlaylistView()
            }
        }
    }
}

#Preview {
    VStack {
        Spacer()
        Text("主要内容区域")
        Spacer()
        MiniPlayerView()
    }
} 
