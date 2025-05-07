import SwiftUI

struct ProfileView: View {
    @StateObject private var viewModel = ProfileViewModel()
    @State private var playbackMode: PlaybackMode = UserSettings.shared.playbackMode
    @State private var ttsServiceType: TTSServiceType = UserSettings.shared.ttsServiceType
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 20) {
                    // 学习统计卡片
                    if let stats = viewModel.stats {
                        StatsCardView(stats: stats)
                    } else if viewModel.isLoading {
                        ProgressView()
                            .frame(height: 200)
                    }
                    
                    SettingsView()
                }
                                
            }
            .navigationTitle("我的")
            .task {
                await viewModel.loadStats()
            }
        }
    }
}

struct StatsCardView: View {
    let stats: Stats
    
    var body: some View {
        VStack(spacing: 20) {
            Text("学习进度")
                .font(.headline)
                .frame(maxWidth: .infinity, alignment: .leading)
            
            HStack(spacing: 20) {
                StatItemView(
                    title: "新词",
                    value: "\(stats.newWordsCount)",
                    icon: "doc.text.fill",
                    color: .blue
                )
                
                StatItemView(
                    title: "复习中",
                    value: "\(stats.reviewWordsCount)",
                    icon: "arrow.clockwise",
                    color: .orange
                )
                
                StatItemView(
                    title: "已掌握",
                    value: "\(stats.masteredWordsCount)",
                    icon: "checkmark.circle.fill",
                    color: .green
                )
                StatItemView(
                    title: "总单词数",
                    value: "\(stats.totalWordsCount)",
                    icon: "books.vertical.fill",
                    color: .purple
                )
            }
 
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(10)
        .shadow(color: Color.black.opacity(0.05), radius: 5, y: 2)
        .padding(.horizontal)
    }
}

struct StatItemView: View {
    let title: String
    let value: String
    let icon: String
    let color: Color
    
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 24))
                .foregroundColor(color)
            
            Text(value)
                .font(.title2.bold())
                .foregroundColor(.primary)
            
            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(color.opacity(0.1))
        .cornerRadius(8)
    }
} 


struct SettingsView: View {
    @State private var playbackMode: PlaybackMode = UserSettings.shared.playbackMode
    @State private var ttsServiceType: TTSServiceType = UserSettings.shared.ttsServiceType
    
    var body: some View {
        NavigationView {
                VStack(spacing: 0) {
                    Text("设置")
                        .font(.headline)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding()
                        .background(Color(.systemGroupedBackground))

                    Form {
                        Section {
                            Picker("播放模式", selection: $playbackMode) {
                                ForEach(PlaybackMode.allCases, id: \.self) { mode in
                                    Text(mode.title).tag(mode)
                                }
                            }
                            .pickerStyle(.menu)
                            .onChange(of: playbackMode) { newValue in
                                UserSettings.shared.playbackMode = newValue
                            }
                            
                            Picker("语音服务", selection: $ttsServiceType) {
                                ForEach(TTSServiceType.allCases, id: \.self) { service in
                                    Text(service.title).tag(service)
                                }
                            }
                            .pickerStyle(.menu)
                            .onChange(of: ttsServiceType) { newValue in
                                UserSettings.shared.ttsServiceType = newValue
                            }
                        } header: {
                            Text("播放设置")
                        } footer: {
                            Text("Edge TTS提供更自然的语音效果。高分录音模式将继续使用原有语音服务。")
                        }
                        
                        Section {
                            Button(action: {
                                EdgeTTSService.shared.clearCache()
                            }) {
                                HStack {
                                    Text("清除语音缓存")
                                    Spacer()
                                    Image(systemName: "trash")
                                }
                            }
                            .foregroundColor(.red)
                        } header: {
                            Text("缓存管理")
                        } footer: {
                            Text("清除已缓存的语音文件以释放存储空间")
                        }
                    }
                }
                .background(Color(.systemBackground))
                .cornerRadius(10)
                .padding(.horizontal)
        }.frame(height: 350)
    }
}
