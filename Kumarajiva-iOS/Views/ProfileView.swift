import SwiftUI

struct ProfileView: View {
    @StateObject private var viewModel = ProfileViewModel()
    @State private var playbackMode: PlaybackMode = UserSettings.shared.playbackMode
    @State private var ttsServiceType: TTSServiceType = UserSettings.shared.ttsServiceType
    @State private var speechRecognitionServiceType: SpeechRecognitionServiceType = UserSettings.shared.speechRecognitionServiceType
    @State private var whisperModelSize: WhisperModelSize = UserSettings.shared.whisperModelSize
    
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
    @State private var speechRecognitionServiceType: SpeechRecognitionServiceType = UserSettings.shared.speechRecognitionServiceType
    @State private var whisperModelSize: WhisperModelSize = UserSettings.shared.whisperModelSize
    @State private var isModelInfoShowing = false
    @State private var isModelLoading = false
    @State private var playbackSpeed: Float = UserSettings.shared.playbackSpeed
    
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
                        
                        Picker("播放速度", selection: $playbackSpeed) {
                            Text("0.5x").tag(Float(0.5))
                            Text("0.6x").tag(Float(0.6))
                            Text("0.75x").tag(Float(0.75))
                            Text("1.0x").tag(Float(1.0))
                            Text("1.5x").tag(Float(1.5))
                            Text("1.7x").tag(Float(1.7))
                            Text("2.0x").tag(Float(2.0))
                        }
                        .pickerStyle(.menu)
                        .onChange(of: playbackSpeed) { newValue in
                            UserSettings.shared.playbackSpeed = newValue
                            AudioService.shared.setPlaybackRate(newValue)
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
                        Picker("语音识别服务", selection: $speechRecognitionServiceType) {
                            ForEach(SpeechRecognitionServiceType.allCases, id: \.self) { service in
                                Text(service.title).tag(service)
                            }
                        }
                        .pickerStyle(.menu)
                        .onChange(of: speechRecognitionServiceType) { newValue in
                            UserSettings.shared.speechRecognitionServiceType = newValue
                            
                            // If WhisperKit is selected, trigger model check/loading
                            if newValue == .whisperKit {
                                Task {
                                    // Always reload the model when WhisperKit is selected
                                    WhisperKitService.shared.reloadModel()
                                }
                            }
                        }
                        
                        if speechRecognitionServiceType == .whisperKit {
                            Picker("WhisperKit模型", selection: $whisperModelSize) {
                                ForEach(WhisperModelSize.allCases, id: \.self) { model in
                                    HStack {
                                        Text(model.title)
                                        Spacer()
                                        Text("(\(model.modelSize)MB)")
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                    }.tag(model)
                                }
                            }
                            .pickerStyle(.menu)
                            .onChange(of: whisperModelSize) { newValue in
                                UserSettings.shared.whisperModelSize = newValue
                                // Reload the model when changed - no need to manage local loading state
                                WhisperKitService.shared.reloadModel()
                            }
                            
                            // Add model download status view
                            if speechRecognitionServiceType == .whisperKit {
                                ModelStatusView()
                            }
                            
                            Button(action: {
                                isModelInfoShowing = true
                            }) {
                                HStack {
                                    Text("模型说明")
                                    Spacer()
                                    Image(systemName: "info.circle")
                                }
                            }
                            .foregroundColor(.blue)
                            .sheet(isPresented: $isModelInfoShowing) {
                                WhisperModelInfoView()
                            }
                        }
                    } header: {
                        Text("语音识别设置")
                    } footer: {
                        Text("WhisperKit提供更高准确度的语音识别，但需要下载模型。模型越大，识别越精准但速度越慢。")
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
            .onAppear {
                // When view appears, check if we're using WhisperKit and model status
                if speechRecognitionServiceType == .whisperKit {
                    // Check if model is in idle state but should be ready
                    if WhisperKitService.shared.modelDownloadState == .idle {
                        // Try to reload the model
                        WhisperKitService.shared.reloadModel()
                    }
                }
            }
        }.frame(height: 430)
    }
}

struct WhisperModelInfoView: View {
    var body: some View {
        NavigationView {
            List {
                ForEach(WhisperModelSize.allCases, id: \.self) { model in
                    VStack(alignment: .leading, spacing: 8) {
                        Text(model.title)
                            .font(.headline)
                        
                        Text("大小: 约\(model.modelSize)MB")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        
                        Text(model.description)
                            .font(.body)
                            .foregroundColor(.primary)
                            .padding(.top, 2)
                    }
                    .padding(.vertical, 8)
                }
            }
            .navigationTitle("WhisperKit模型说明")
            .navigationBarItems(trailing: Button("关闭") {
                // 关闭视图的逻辑
            })
        }
    }
}

// Add this new view after the WhisperModelInfoView
struct ModelStatusView: View {
    @ObservedObject private var whisperService = WhisperKitService.shared
    @State private var modelSize: Int = 0
    
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("模型状态:")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                
                Spacer()
                
                Text(whisperService.modelDownloadState.description)
                    .font(.subheadline)
                    .foregroundColor(statusColor)
            }
            
            if case .downloading(let progress) = whisperService.modelDownloadState {
                VStack(alignment: .leading, spacing: 2) {
                    ProgressView(value: progress)
                        .progressViewStyle(LinearProgressViewStyle())
                    
                    HStack {
                        Text("下载进度:")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        
                        Text("\(Int(progress * 100))%")
                            .font(.caption)
                            .foregroundColor(.blue)
                        
                        Spacer()
                        
                        let size = UserSettings.shared.whisperModelSize.modelSize
                        Text("模型大小: \(size)MB")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                .padding(.top, 2)
            } else if case .loading(let progress) = whisperService.modelDownloadState {
                VStack(alignment: .leading, spacing: 2) {
                    ProgressView(value: progress)
                        .progressViewStyle(LinearProgressViewStyle())
                    
                    Text("正在加载到内存...")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding(.top, 2)
            } else if case .failed(let error) = whisperService.modelDownloadState {
                Text("错误: \(error)")
                    .font(.caption)
                    .foregroundColor(.red)
                    .lineLimit(2)
                    .padding(.top, 2)
                
                Button(action: {
                    WhisperKitService.shared.reloadModel()
                }) {
                    Text("重试")
                        .font(.caption)
                        .foregroundColor(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 4)
                        .background(Color.blue)
                        .cornerRadius(4)
                }
                .padding(.top, 4)
            } else if case .ready = whisperService.modelDownloadState {
                let size = UserSettings.shared.whisperModelSize.modelSize
                HStack {
                    Text("已加载模型大小: \(size)MB")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    Spacer()
                    
                    Text("✅ 可用")
                        .font(.caption)
                        .foregroundColor(.green)
                }
            } else if case .idle = whisperService.modelDownloadState {
                let size = UserSettings.shared.whisperModelSize.modelSize
                HStack {
                    Text("需要下载模型大小: \(size)MB")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    Spacer()
                    
                    Button(action: {
                        WhisperKitService.shared.downloadModelManually()
                    }) {
                        Text("下载")
                            .font(.caption)
                            .foregroundColor(.white)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 4)
                            .background(Color.blue)
                            .cornerRadius(4)
                    }
                }
            }
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 4)
        .animation(.easeInOut, value: whisperService.modelDownloadState.description)
        .onAppear {
            // On appear, update the model size based on current selection
            self.modelSize = UserSettings.shared.whisperModelSize.modelSize
            
            // If the model state is idle but we should have a model, try to reload
            if whisperService.modelDownloadState == .idle {
                WhisperKitService.shared.reloadModel()
            }
        }
    }
    
    private var statusColor: Color {
        switch whisperService.modelDownloadState {
        case .idle:
            return .gray
        case .downloading:
            return .blue
        case .downloadComplete:
            return .green
        case .loading:
            return .orange
        case .ready:
            return .green
        case .failed:
            return .red
        }
    }
}
