import SwiftUI

struct ProfileView: View {
    @StateObject private var viewModel = ProfileViewModel()
    @StateObject private var authService = AuthService.shared
    @State private var showingLogoutAlert = false
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 20) {
                    // 用户信息卡片
                    UserInfoCardView()
                    
                    // 学习统计卡片
                    if let stats = viewModel.stats {
                        StatsCardView(stats: stats)
                    } else if viewModel.isLoading {
                        ProgressView()
                            .frame(height: 200)
                    }
                    
                    // 设置入口
                    SettingsEntryView()
                }
                                
            }
            // .navigationTitle("我的")
            .task {
                await viewModel.loadStats()
            }
        }
    }
}

// MARK: - 设置入口卡片
struct SettingsEntryView: View {
    var body: some View {
        NavigationLink(destination: SettingsDetailView()) {
            HStack {
                Image(systemName: "gearshape.fill")
                    .font(.title2)
                    .foregroundColor(.blue)
                    .frame(width: 30)
                
                Text("设置")
                    .font(.headline)
                    .foregroundColor(.primary)
                
                Spacer()
                
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding()
            .background(Color(.systemBackground))
            .cornerRadius(12)
            .shadow(color: Color.black.opacity(0.05), radius: 5, y: 2)
        }
        .buttonStyle(PlainButtonStyle())
        .padding(.horizontal)
    }
}

// MARK: - 用户信息卡片
struct UserInfoCardView: View {
    @StateObject private var authService = AuthService.shared
    @State private var showingLogoutAlert = false
    
    var body: some View {
        VStack(spacing: 16) {
            if let user = authService.currentUser {
                HStack(spacing: 16) {
                    // 用户头像
                    AsyncImage(url: user.avatarUrl.flatMap { URL(string: $0) }) { image in
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                    } placeholder: {
                        Image(systemName: "person.circle.fill")
                            .font(.system(size: 50))
                            .foregroundColor(.gray)
                    }
                    .frame(width: 60, height: 60)
                    .clipShape(Circle())
                    
                    // 用户信息
                    VStack(alignment: .leading, spacing: 4) {
                        Text(user.username)
                            .font(.title2)
                            .fontWeight(.semibold)
                        
                        if let email = user.email {
                            Text(email)
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }
                        
                        HStack(spacing: 4) {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.caption)
                                .foregroundColor(.green)
                            
                            Text("已通过 GitHub 认证")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    
                    Spacer()
                    
                    // 登出按钮
                    Button(action: {
                        showingLogoutAlert = true
                    }) {
                        Image(systemName: "rectangle.portrait.and.arrow.right")
                            .font(.title3)
                            .foregroundColor(.red)
                    }
                }
                .padding()
            } else {
                // 加载状态
                HStack(spacing: 16) {
                    ProgressView()
                        .frame(width: 60, height: 60)
                    
                    VStack(alignment: .leading, spacing: 4) {
                        Text("加载用户信息...")
                            .font(.title2)
                            .fontWeight(.semibold)
                        
                        Text("请稍候")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    
                    Spacer()
                }
                .padding()
            }
        }
        .background(Color(.systemBackground))
        .cornerRadius(12)
        .shadow(color: Color.black.opacity(0.05), radius: 5, y: 2)
        .padding(.horizontal)
        .alert("确认登出", isPresented: $showingLogoutAlert) {
            Button("取消", role: .cancel) { }
            Button("登出", role: .destructive) {
                authService.logout()
            }
        } message: {
            Text("您确定要登出吗？登出后需要重新登录才能访问您的数据。")
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

// MARK: - 设置详情页面
struct SettingsDetailView: View {
    @State private var playbackMode: PlaybackMode = UserSettings.shared.playbackMode
    @State private var ttsServiceType: TTSServiceType = UserSettings.shared.ttsServiceType
    @State private var speechRecognitionServiceType: SpeechRecognitionServiceType = UserSettings.shared.speechRecognitionServiceType
    @State private var whisperModelSize: WhisperModelSize = UserSettings.shared.whisperModelSize
    @State private var isModelInfoShowing = false
    @State private var isModelLoading = false
    @State private var playbackSpeed: Float = UserSettings.shared.playbackSpeed
    @State private var autoLoadWhisperModel: Bool = UserSettings.shared.autoLoadWhisperModel
    @State private var allowCellularDownload: Bool = UserSettings.shared.allowCellularDownload
    @StateObject private var networkMonitor = NetworkMonitor.shared
    
    var body: some View {
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
                    
                    // 自动加载设置
                    Toggle("自动加载模型", isOn: $autoLoadWhisperModel)
                        .onChange(of: autoLoadWhisperModel) { newValue in
                            UserSettings.shared.autoLoadWhisperModel = newValue
                            
                            // 如果启用自动加载且模型已下载但未加载，立即加载
                            if newValue && WhisperKitService.shared.modelDownloadState == .ready {
                                WhisperKitService.shared.preloadModelInBackground()
                            }
                        }
                    
                    Toggle("允许蜂窝网络下载", isOn: $allowCellularDownload)
                        .onChange(of: allowCellularDownload) { newValue in
                            UserSettings.shared.allowCellularDownload = newValue
                        }
                    
                    // 网络状态显示
                    HStack {
                        Text("当前网络")
                        Spacer()
                        HStack {
                            Circle()
                                .fill(networkMonitor.isConnected ? .green : .red)
                                .frame(width: 8, height: 8)
                            Text(networkMonitor.isConnected ? networkMonitor.connectionType.description : "未连接")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
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
                VStack(alignment: .leading, spacing: 4) {
                    Text("WhisperKit提供更高准确度的语音识别，但需要下载模型。模型越大，识别越精准但速度越慢。")
                    Text("• 自动加载：应用启动时自动加载已下载的模型")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text("• 蜂窝网络下载：允许在移动网络下下载模型（可能产生流量费用）")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            
            Section {
                NavigationLink(destination: SubtitleTaskManagerView()) {
                    HStack {
                        Image(systemName: "list.bullet.clipboard")
                            .foregroundColor(.green)
                        Text("字幕生成任务")
                    }
                }
                
                NavigationLink(destination: StorageSettingsView()) {
                    HStack {
                        Image(systemName: "internaldrive")
                            .foregroundColor(.blue)
                        Text("存储设置")
                    }
                }
                
                Button(action: {
                    EdgeTTSService.shared.clearCache()
                }) {
                    HStack {
                        Image(systemName: "trash")
                            .foregroundColor(.red)
                        Text("清除语音缓存")
                        Spacer()
                    }
                }
                .foregroundColor(.red)
            } header: {
                Text("数据管理")
            } footer: {
                Text("管理应用数据存储、缓存文件和字幕生成任务")
            }
        }
        .navigationTitle("设置")
        .navigationBarTitleDisplayMode(.large)
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
