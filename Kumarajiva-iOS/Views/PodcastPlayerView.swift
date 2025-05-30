import SwiftUI

struct PodcastPlayerView: View {
    let episode: PodcastEpisode
    @StateObject private var playerService = PodcastPlayerService.shared
    @StateObject private var taskManager = SubtitleGenerationTaskManager.shared
    @Environment(\.dismiss) private var dismiss
    
    // 添加状态变量来防止意外回退
    @State private var showingErrorAlert = false
    @State private var errorAlertMessage = ""
    @State private var showingVocabularyAnalysis = false
    // 新增：控制配置面板的显示状态
    @State private var showingConfigPanel = false
    // 新增：控制听力模式的状态
    @State private var isListeningMode = false
    
    var body: some View {
        ZStack {
            VStack(spacing: 0) {
                // 字幕显示区域
                subtitleDisplayView
                
                // 播放控制面板
                playbackControlView
            }
            
            // 听力模式浮层
            if isListeningMode {
                ListeningModeOverlay(
                    isListeningMode: $isListeningMode,
                    playerService: playerService
                )
                .transition(.opacity)
            }
        }
//        .navigationTitle("播放器")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .tabBar) // 隐藏底部TabBar
        .onAppear {
            // 只准备节目，不自动播放
            playerService.prepareEpisode(episode)
        }
        .onDisappear {
            // 离开页面时不停止播放，让音频继续在后台播放
            // 用户可以通过底部的MiniPlayerView控制播放
            print("🎧 [PlayerView] 页面消失，音频继续播放")
        }
        // 添加错误处理，但不自动回退页面
        .onReceive(playerService.$errorMessage) { errorMessage in
            if let error = errorMessage {
                errorAlertMessage = error
                showingErrorAlert = true
                // 清除错误消息，避免重复显示
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    playerService.errorMessage = nil
                }
            }
        }
        .alert("提示", isPresented: $showingErrorAlert) {
            Button("确定", role: .cancel) { }
        } message: {
            Text(errorAlertMessage)
        }
        .sheet(isPresented: $showingVocabularyAnalysis) {
            VocabularyAnalysisView(playerService: playerService)
        }
    }
    
    // MARK: - 字幕显示区域
    
    private var subtitleDisplayView: some View {
        VStack(spacing: 16) {
            // 节目信息
            VStack(spacing: 8) {
                Text(episode.title)
                    .font(.headline)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                
                Text(formatDate(episode.publishDate))
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal)
            
            Divider()
            
            // 字幕内容
                    if playerService.currentSubtitles.isEmpty {
                        emptySubtitleView
                    } else {
                ScrollView {
                        subtitleListView
                }
                .background(Color(.systemBackground))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemGroupedBackground))
    }
    
    private var emptySubtitleView: some View {
        VStack(spacing: 16) {
            if playerService.isGeneratingSubtitles {
                VStack(spacing: 12) {
                    // 圆形进度条
                    ZStack {
                        Circle()
                            .stroke(Color.gray.opacity(0.3), lineWidth: 8)
                            .frame(width: 80, height: 80)
                        
                        Circle()
                            .trim(from: 0, to: playerService.subtitleGenerationProgress)
                            .stroke(
                                playerService.errorMessage != nil ? Color.red : 
                                playerService.subtitleGenerationProgress >= 1.0 ? Color.green : Color.accentColor,
                                style: StrokeStyle(lineWidth: 8, lineCap: .round)
                            )
                            .frame(width: 80, height: 80)
                            .rotationEffect(.degrees(-90))
                            .animation(.easeInOut(duration: 0.3), value: playerService.subtitleGenerationProgress)
                        
                        if playerService.errorMessage != nil {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .font(.title2)
                                .foregroundColor(.red)
                        } else if playerService.subtitleGenerationProgress >= 1.0 {
                            Image(systemName: "checkmark")
                                .font(.title2)
                                .foregroundColor(.green)
                                .fontWeight(.bold)
                        } else {
                        Text("\(Int(playerService.subtitleGenerationProgress * 100))%")
                            .font(.headline)
                            .fontWeight(.semibold)
                        }
                    }
                    
                    Text("正在生成字幕...")
                        .font(.body)
                        .foregroundColor(.secondary)
                    
                    Text(subtitleGenerationStatusText)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
            } else {
                VStack(spacing: 12) {
                    Image(systemName: "captions.bubble")
                        .font(.system(size: 40))
                        .foregroundColor(.secondary)
                    
                    Text("暂无字幕")
                        .font(.headline)
                        .foregroundColor(.secondary)
                    
                    Text("点击下方按钮生成字幕")
                        .font(.body)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                    
                    Button {
                        generateSubtitlesManually()
                    } label: {
                        Label("生成字幕", systemImage: "waveform.and.mic")
                            .font(.headline)
                            .foregroundColor(.white)
                            .padding()
                            .background(isWhisperKitReady ? Color.accentColor : Color.gray)
                            .cornerRadius(12)
                    }
                    .disabled(!isWhisperKitReady)
                    .padding(.top, 8)
                    
                    if !isWhisperKitReady {
                        VStack(spacing: 8) {
                            if WhisperKitService.shared.shouldPromptForModelDownload() {
                                Button {
                                    Task {
                                        await WhisperKitService.shared.smartDownloadModel()
                                    }
                                } label: {
                                    HStack {
                                        Image(systemName: "icloud.and.arrow.down")
                                        Text("下载WhisperKit模型")
                                    }
                                    .font(.caption)
                                    .foregroundColor(.white)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 6)
                                    .background(Color.blue)
                                    .cornerRadius(8)
                                }
                            } else {
                            Text("请先在\"我的\"页面设置中配置WhisperKit")
                                .font(.caption)
                                .foregroundColor(.orange)
                                .multilineTextAlignment(.center)
                            }
                            
                            Text("当前状态: \(whisperStatusText)")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                                .multilineTextAlignment(.center)
                        }
                        .padding(.top, 4)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    private var subtitleListView: some View {
        ScrollViewReader { proxy in
            LazyVStack(spacing: 4) {
                ForEach(Array(playerService.currentSubtitles.enumerated()), id: \.element.id) { index, subtitle in
                    SubtitleRowView(
                        subtitle: subtitle,
                        isActive: playerService.playbackState.currentSubtitleIndex == index,
                        currentTime: playerService.playbackState.currentTime,
                        onTap: {
                            playerService.seek(to: subtitle.startTime)
                        }
                    )
                    .id(index) // 为每个字幕行添加ID
                }
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 16)
            .onChange(of: playerService.playbackState.currentSubtitleIndex) { oldIndex, newIndex in
                // 当当前字幕索引改变时，自动滚动到可见区域
                if let index = newIndex {
                    // 使用更平滑的动画，确保字幕在屏幕中央
                    withAnimation(.easeInOut(duration: 0.3)) {
                        proxy.scrollTo(index, anchor: .center)
                    }
                    print("🎧 [PlayerView] 字幕滚动：滚动到索引 \(index)")
                } else if oldIndex != nil {
                    // 如果从有字幕变为无字幕，保持当前位置
                    print("🎧 [PlayerView] 字幕滚动：当前无活动字幕")
                }
            }
            .onAppear {
                // 页面出现时，如果有当前字幕，滚动到该位置
                if let currentIndex = playerService.playbackState.currentSubtitleIndex {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        withAnimation(.easeInOut(duration: 0.5)) {
                            proxy.scrollTo(currentIndex, anchor: .center)
                        }
                    }
                }
            }
        }
    }
    
    // MARK: - 播放控制面板
    
    private var playbackControlView: some View {
        VStack(spacing: 0) {
            // 进度条
            progressView
                .padding(.bottom, 12)
            
            // 主要播放控制按钮
            mainControlsView
            
            // 功能按钮区域（可展开/收起）
            if showingConfigPanel {
                Divider()
                    .padding(.horizontal, 20)
                    .padding(.vertical, 8)
                
                functionButtonsView
                    .transition(.asymmetric(
                        insertion: .push(from: .bottom).combined(with: .opacity),
                        removal: .push(from: .top).combined(with: .opacity)
                    ))
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Color(.systemBackground))
        .shadow(color: .black.opacity(0.05), radius: 8, x: 0, y: -3)
    }
    
    private var progressView: some View {
        VStack(spacing: 4) {
            // 可拖动的进度条
            Slider(
                value: Binding(
                    get: { 
                        guard playerService.playbackState.duration > 0 else { return 0 }
                        return playerService.playbackState.currentTime / playerService.playbackState.duration
                    },
                    set: { newValue in
                        let newTime = newValue * playerService.playbackState.duration
                        playerService.seek(to: newTime)
                    }
                ),
                in: 0...1
            )
            .accentColor(.accentColor)
            .frame(height: 10) // 减少触摸区域高度
            
            // 时间显示
            HStack {
                Text(playerService.formatTime(playerService.playbackState.currentTime))
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundColor(.secondary)
                
                Spacer()
                
                Text(playerService.formatTime(playerService.playbackState.duration))
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundColor(.secondary)
            }
        }
    }
    
    // MARK: - 功能按钮区域
    
    private var functionButtonsView: some View {
        HStack(spacing: 0) {
            // 循环播放
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    playerService.toggleLoop()
                }
            } label: {
                VStack(spacing: 2) {
                    Image(systemName: playerService.playbackState.isLooping ? "repeat.1" : "repeat")
                        .font(.system(size: 22, weight: .medium))
                        .foregroundColor(playerService.playbackState.isLooping ? .accentColor : .primary)
                    Text("循环")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(playerService.playbackState.isLooping ? .accentColor : .primary)
                }
                .frame(maxWidth: .infinity)
                .frame(height: 50)
            }
            
            // 生词解析
            Button {
                if !playerService.currentSubtitles.isEmpty {
                    showingVocabularyAnalysis = true
                }
            } label: {
                VStack(spacing: 2) {
                    Image(systemName: "text.magnifyingglass")
                        .font(.system(size: 22, weight: .medium))
                    Text("生词解析")
                        .font(.system(size: 10, weight: .medium))
                }
                .foregroundColor(playerService.currentSubtitles.isEmpty ? .secondary : .primary)
                .frame(maxWidth: .infinity)
                .frame(height: 50)
            }
            .disabled(playerService.currentSubtitles.isEmpty)
            
            // 重新转录字幕
            Button {
                if !playerService.isGeneratingSubtitles {
                    Task {
                        await playerService.generateSubtitlesForCurrentEpisode()
                    }
                }
            } label: {
                VStack(spacing: 2) {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 22, weight: .medium))
                    Text("重新转录")
                        .font(.system(size: 10, weight: .medium))
                }
                .foregroundColor(playerService.isGeneratingSubtitles ? .secondary : .primary)
                .frame(maxWidth: .infinity)
                .frame(height: 50)
            }
            .disabled(playerService.isGeneratingSubtitles)
            
            // 听力模式
            Button {
                withAnimation(.easeInOut(duration: 0.3)) {
                    isListeningMode = true
                    showingConfigPanel = false
                }
            } label: {
                VStack(spacing: 2) {
                    Image(systemName: "headphones.circle")
                        .font(.system(size: 22, weight: .medium))
                    Text("听力模式")
                        .font(.system(size: 10, weight: .medium))
                }
                .foregroundColor(.primary)
                .frame(maxWidth: .infinity)
                .frame(height: 50)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 8)
    }
    
    private var mainControlsView: some View {
        HStack(spacing: 0) {
            // 播放速度
            Menu {
                ForEach([0.5, 0.6, 0.65,0.7, 0.75, 1.0, 1.25, 1.5, 2.0], id: \.self) { rate in
                    Button {
                        playerService.setPlaybackRate(Float(rate))
                    } label: {
                        HStack {
                            Text("\(rate, specifier: "%.2g")x")
                            if playerService.playbackState.playbackRate == Float(rate) {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            } label: {
                VStack(spacing: 2) {
                    Image(systemName: "speedometer")
                        .font(.system(size: 22, weight: .medium))
                    Text("\(playerService.playbackState.playbackRate, specifier: "%.2g")x")
                        .font(.system(size: 10, weight: .medium))
                }
                .foregroundColor(.primary)
                .frame(maxWidth: .infinity)
                .frame(height: 50)
            }
            
            // 上一句
            Button {
                playerService.previousSubtitle()
            } label: {
                VStack(spacing: 2) {
                    Image(systemName: "backward.end.fill")
                        .font(.system(size: 22, weight: .medium))
                    Text("上一句")
                        .font(.system(size: 10, weight: .medium))
                }
                .foregroundColor(playerService.hasPreviousSubtitle ? .primary : .secondary)
                .frame(maxWidth: .infinity)
                .frame(height: 50)
            }
            .disabled(!playerService.hasPreviousSubtitle)
            
            // 播放/暂停
            Button {
                playerService.togglePlayPause()
            } label: {
                Image(systemName: playerService.playbackState.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                    .font(.system(size: 55))
                    .foregroundColor(.accentColor)
            }
            .frame(maxWidth: .infinity)
            
            // 下一句
            Button {
                playerService.nextSubtitle()
            } label: {
                VStack(spacing: 2) {
                    Image(systemName: "forward.end.fill")
                        .font(.system(size: 22, weight: .medium))
                    Text("下一句")
                        .font(.system(size: 10, weight: .medium))
                }
                .foregroundColor(playerService.hasNextSubtitle ? .primary : .secondary)
                .frame(maxWidth: .infinity)
                .frame(height: 50)
            }
            .disabled(!playerService.hasNextSubtitle)
            
            // 更多设置按钮
            Button {
                withAnimation(.easeInOut(duration: 0.25)) {
                    showingConfigPanel.toggle()
                }
            } label: {
                VStack(spacing: 2) {
                    Image(systemName: showingConfigPanel ? "chevron.up" : "ellipsis")
                        .font(.system(size: 22, weight: .medium))
                    Text("更多")
                        .font(.system(size: 10, weight: .medium))
                }
                .foregroundColor(showingConfigPanel ? .accentColor : .primary)
                .frame(maxWidth: .infinity)
                .frame(height: 50)
            }
        }
        .padding(.horizontal, 20)
    }
    
    // MARK: - 计算属性
    
    private var currentTask: SubtitleGenerationTask? {
        return taskManager.getTask(for: episode.id)
    }
    
    private var isWhisperKitReady: Bool {
        return UserSettings.shared.speechRecognitionServiceType == .whisperKit &&
               WhisperKitService.shared.modelDownloadState == .ready
    }
    
    private var whisperStatusText: String {
        if UserSettings.shared.speechRecognitionServiceType != .whisperKit {
            return "未选择WhisperKit"
        }
        
        switch WhisperKitService.shared.modelDownloadState {
        case .idle:
            return "需要下载模型"
        case .downloading(let progress):
            return "下载中 \(Int(progress * 100))%"
        case .downloadComplete:
            return "下载完成"
        case .loading(let progress):
            return "加载中 \(Int(progress * 100))%"
        case .ready:
            return "已就绪"
        case .failed(let error):
            return "失败: \(error)"
        }
    }
    
    private var subtitleGenerationStatusText: String {
        return playerService.subtitleGenerationStatusText
    }
    
    // MARK: - 辅助方法
    
    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        return formatter.string(from: date)
    }
    
    private func generateSubtitlesManually() {
        // 手动触发字幕生成
        Task {
            await playerService.generateSubtitlesForCurrentEpisode()
        }
    }
}

// MARK: - 字幕行视图
struct SubtitleRowView: View {
    let subtitle: Subtitle
    let isActive: Bool
    let currentTime: TimeInterval?
    let onTap: () -> Void
    
    init(subtitle: Subtitle, isActive: Bool, currentTime: TimeInterval? = nil, onTap: @escaping () -> Void) {
        self.subtitle = subtitle
        self.isActive = isActive
        self.currentTime = currentTime
        self.onTap = onTap
    }
    
    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 8) {
                // 时间和单词统计信息 - 移到上方
                HStack {
                    Text(formatTime(subtitle.startTime))
                        .font(.system(size: 12, weight: .medium, design: .monospaced))
                        .foregroundColor(isActive ? .accentColor : .secondary)
                    
                    Spacer()
                    
                        Text("\(subtitle.words.count)词")
                        .font(.system(size: 11))
                            .foregroundColor(.secondary)
                }
                .padding(.horizontal, isActive ? 16 : 12)
                .padding(.top, 8)
                
                // 字幕文本区域
                VStack(alignment: .leading, spacing: 0) {
                    if isActive && !subtitle.words.isEmpty, let time = currentTime {
                        // 当前活动字幕 - 显示单词高亮
                        wordHighlightText(for: time)
                            .padding(.vertical, 12)
                            .padding(.horizontal, 16)
                    } else {
                        // 普通字幕文本
                        Text(subtitle.text)
                            .font(.system(size: 15, weight: isActive ? .medium : .regular))
                            .foregroundColor(isActive ? .primary : .secondary)
                            .lineSpacing(3)
                            .multilineTextAlignment(.leading)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.vertical, isActive ? 12 : 10)
                            .padding(.horizontal, isActive ? 16 : 12)
                    }
                }
                .padding(.bottom, 8)
            }
            .background(
                RoundedRectangle(cornerRadius: isActive ? 14 : 10)
                    .fill(isActive ? Color.accentColor.opacity(0.08) : Color(.systemGray6).opacity(0.5))
                    .overlay(
                        RoundedRectangle(cornerRadius: isActive ? 14 : 10)
                            .stroke(isActive ? Color.accentColor.opacity(0.3) : Color.clear, lineWidth: isActive ? 2 : 0)
                    )
            )
            .animation(.easeInOut(duration: 0.2), value: isActive)
            .padding(.horizontal, 2)
            .padding(.vertical, 3)
        }
        .buttonStyle(PlainButtonStyle())
    }
    
    /// 单词高亮文本 - 仿iPhone播客效果
    private func wordHighlightText(for currentTime: TimeInterval) -> some View {
        Text(buildAttributedString(for: currentTime))
            .font(.system(size: 15, weight: .medium))
            .lineSpacing(3)
            .multilineTextAlignment(.leading)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
    
    /// 构建带高亮的属性字符串 - 优化颜色和效果
    private func buildAttributedString(for currentTime: TimeInterval) -> AttributedString {
        var attributedString = AttributedString()
        
        for (index, word) in subtitle.words.enumerated() {
            var wordString = AttributedString(word.word)
            
            // 根据播放时间设置单词样式 - 仿iPhone播客效果
            if currentTime >= word.startTime && currentTime < word.endTime {
                // 当前正在播放的单词 - 黄色高亮
                wordString.foregroundColor = .black
                wordString.font = .system(size: 15, weight: .semibold)
                wordString.backgroundColor = Color.yellow.opacity(0.8)
            } else if currentTime >= word.endTime {
                // 已播放的单词 - 主色调
                wordString.foregroundColor = .primary
                wordString.font = .system(size: 15, weight: .medium)
            } else {
                // 未播放的单词 - 较淡颜色
                wordString.foregroundColor = .secondary
                wordString.font = .system(size: 15, weight: .regular)
            }
            
            attributedString.append(wordString)
            
            // 添加空格（除了最后一个单词）
            if index < subtitle.words.count - 1 {
                attributedString.append(AttributedString(" "))
            }
        }
        
        return attributedString
    }
    
    private func formatTime(_ time: TimeInterval) -> String {
        let minutes = Int(time) / 60
        let seconds = Int(time) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}

// MARK: - 听力模式浮层
struct ListeningModeOverlay: View {
    @Binding var isListeningMode: Bool
    let playerService: PodcastPlayerService
    
    @State private var showingFeedback = false
    @State private var feedbackText = ""
    @State private var feedbackIcon = ""
    
    var body: some View {
        ZStack {
            // 半透明背景
            Color.black.opacity(0.85)
                .ignoresSafeArea()
            
            VStack(spacing: 0) {
                // 上半部分 - 上一句
                Button {
                    handlePreviousSubtitle()
                } label: {
                    VStack(spacing: 12) {
                        Spacer()
                        
                        Image(systemName: "chevron.up.circle.fill")
                            .font(.system(size: 60, weight: .medium))
                            .foregroundColor(.white.opacity(0.8))
                        
                        Text("上一句")
                            .font(.system(size: 18, weight: .medium))
                            .foregroundColor(.white.opacity(0.9))
                        
                        Spacer()
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .contentShape(Rectangle())
                }
                .buttonStyle(PlainButtonStyle())
                .simultaneousGesture(
                    TapGesture(count: 2).onEnded {
                        handlePlayPause()
                    }
                )
                .disabled(!playerService.hasPreviousSubtitle)
                .opacity(playerService.hasPreviousSubtitle ? 1.0 : 0.5)
                
                // 中间分隔线
                Rectangle()
                    .fill(Color.white.opacity(0.3))
                    .frame(height: 1)
                    .padding(.horizontal, 40)
                
                // 下半部分 - 下一句
                Button {
                    handleNextSubtitle()
                } label: {
                    VStack(spacing: 12) {
                        Spacer()
                        
                        Image(systemName: "chevron.down.circle.fill")
                            .font(.system(size: 60, weight: .medium))
                            .foregroundColor(.white.opacity(0.8))
                        
                        Text("下一句")
                            .font(.system(size: 18, weight: .medium))
                            .foregroundColor(.white.opacity(0.9))
                        
                        Spacer()
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .contentShape(Rectangle())
                }
                .buttonStyle(PlainButtonStyle())
                .simultaneousGesture(
                    TapGesture(count: 2).onEnded {
                        handlePlayPause()
                    }
                )
                .disabled(!playerService.hasNextSubtitle)
                .opacity(playerService.hasNextSubtitle ? 1.0 : 0.5)
            }
            
            // 顶部信息栏
            VStack {
                HStack {
                    // 退出按钮
                    Button {
                        withAnimation(.easeInOut(duration: 0.3)) {
                            isListeningMode = false
                        }
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 30))
                            .foregroundColor(.white.opacity(0.8))
                            .background(Circle().fill(Color.black.opacity(0.3)))
                    }
                    
                    Spacer()
                    
                    // 播放状态指示器
                    HStack(spacing: 8) {
                        Image(systemName: playerService.playbackState.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                            .font(.system(size: 24))
                            .foregroundColor(.white.opacity(0.8))
                        
                        Text("听力模式")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundColor(.white.opacity(0.9))
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(
                        Capsule()
                            .fill(Color.black.opacity(0.3))
                    )
                    
                    Spacer()
                    
                    // 占位，保持对称
                    Color.clear
                        .frame(width: 30, height: 30)
                }
                .padding(.horizontal, 20)
                .padding(.top, 20)
                
                Spacer()
            }
            
            // 操作反馈
            if showingFeedback {
                VStack(spacing: 8) {
                    Image(systemName: feedbackIcon)
                        .font(.system(size: 40, weight: .medium))
                        .foregroundColor(.white)
                    
                    Text(feedbackText)
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(.white)
                }
                .padding(20)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.black.opacity(0.7))
                )
                .transition(.scale.combined(with: .opacity))
            }
        }
    }
    
    private func handlePreviousSubtitle() {
        guard playerService.hasPreviousSubtitle else { return }
        
        playerService.previousSubtitle()
        showFeedback(text: "上一句", icon: "backward.end.fill")
    }
    
    private func handleNextSubtitle() {
        guard playerService.hasNextSubtitle else { return }
        
        playerService.nextSubtitle()
        showFeedback(text: "下一句", icon: "forward.end.fill")
    }
    
    private func handlePlayPause() {
        playerService.togglePlayPause()
        let isPlaying = playerService.playbackState.isPlaying
        showFeedback(
            text: isPlaying ? "播放" : "暂停",
            icon: isPlaying ? "play.circle.fill" : "pause.circle.fill"
        )
    }
    
    private func showFeedback(text: String, icon: String) {
        feedbackText = text
        feedbackIcon = icon
        
        withAnimation(.easeInOut(duration: 0.2)) {
            showingFeedback = true
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            withAnimation(.easeInOut(duration: 0.2)) {
                showingFeedback = false
            }
        }
    }
}

// MARK: - 预览
#Preview {
    NavigationView {
        PodcastPlayerView(episode: PodcastEpisode(
            title: "示例播客节目",
            description: "这是一个示例播客节目的描述。",
            audioURL: "https://example.com/episode.mp3",
            duration: 1800,
            publishDate: Date(),
            subtitles: [
                Subtitle(
                    startTime: 0,
                    endTime: 5,
                    text: "欢迎收听本期播客节目。",
                    confidence: 0.95
                ),
                Subtitle(
                    startTime: 5,
                    endTime: 12,
                    text: "今天我们将讨论一个非常有趣的话题。",
                    confidence: 0.88
                )
            ]
        ))
    }
} 
