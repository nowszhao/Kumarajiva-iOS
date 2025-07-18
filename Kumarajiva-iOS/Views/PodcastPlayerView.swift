import SwiftUI

struct PodcastPlayerView: View {
    let episode: PodcastEpisode
    @StateObject private var playerService = PodcastPlayerService.shared
    @StateObject private var taskManager = SubtitleGenerationTaskManager.shared
    @Environment(\.dismiss) private var dismiss
    
    // 状态变量
    @State private var showingErrorAlert = false
    @State private var errorMessage = ""
    @State private var errorAlertMessage = ""
    @State private var showingVocabularyAnalysis = false
    @State private var showingConfigPanel = false
    @State private var isSeeking = false
    @State private var seekDebounceTimer: Timer?
    @State private var showTranslation = false
    @State private var isTranslating = false
    
    var body: some View {
        VStack(spacing: 0) {
            // 字幕显示区域
            subtitleDisplayView
            
            // 播放控制面板
            playbackControlView
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .tabBar) // 隐藏底部TabBar
        .onAppear {
            // 检查是否是同一个episode，如果是则不清空状态
            let isSameEpisode = playerService.playbackState.currentEpisode?.id == episode.id
            
            if !isSameEpisode {
                // 只有切换到不同节目时才清空播放器状态
                playerService.clearCurrentPlaybackState()
                print("🎧 [PlayerView] 切换到新节目，清空播放状态: \(episode.title)")
            } else {
                print("🎧 [PlayerView] 打开当前播放节目，保持播放状态: \(episode.title)")
            }
            
            // 准备节目，但不自动播放
            playerService.prepareEpisode(episode)
        }
        .onDisappear {
            // 离开页面时不停止播放，让音频继续在后台播放
            // 用户可以通过底部的MiniPlayerView控制播放
            print("🎧 [PlayerView] 页面消失，音频继续播放")
            
            // 清理计时器
            seekDebounceTimer?.invalidate()
            seekDebounceTimer = nil
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
                Text(formatDate(episode.publishDate))
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                // 音频状态指示器
                if playerService.audioPreparationState != .audioReady {
                    HStack(spacing: 6) {
                        switch playerService.audioPreparationState {
                        case .preparing:
                            ProgressView()
                                .scaleEffect(0.7)
                        case .failed:
                            Image(systemName: "exclamationmark.triangle")
                                .foregroundColor(.red)
                        default:
                            Image(systemName: "waveform.badge.exclamationmark")
                                .foregroundColor(.secondary)
                        }
                        
                        Text(audioStatusText)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding(.top, 4)
                }
                
                // YouTube下载状态指示器
                if !YouTubeAudioExtractor.shared.downloadStatus.isEmpty {
                    HStack(spacing: 6) {
                        if YouTubeAudioExtractor.shared.isExtracting {
                            ProgressView()
                                .scaleEffect(0.7)
                        } else {
                            Image(systemName: "arrow.down.circle")
                                .foregroundColor(.blue)
                        }
                        
                        VStack(alignment: .leading, spacing: 2) {
                            Text(YouTubeAudioExtractor.shared.downloadStatus)
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .lineLimit(1)
                            
                            if YouTubeAudioExtractor.shared.isExtracting && YouTubeAudioExtractor.shared.extractionProgress > 0 {
                                ProgressView(value: YouTubeAudioExtractor.shared.extractionProgress)
                                    .progressViewStyle(LinearProgressViewStyle())
                                    .frame(height: 4)
                            }
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Color(.systemGray6))
                    .cornerRadius(8)
                    .padding(.top, 4)
                }
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
                        showTranslation: showTranslation,
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
                        // 只有在音频准备就绪时才显示真实进度
                        guard playerService.audioPreparationState == .audioReady,
                              playerService.playbackState.duration > 0 else { return 0 }
                        return playerService.playbackState.currentTime / playerService.playbackState.duration
                    },
                    set: { newValue in
                        guard playerService.audioPreparationState == .audioReady else { return }
                        
                        // 取消之前的防抖动计时器
                        seekDebounceTimer?.invalidate()
                        
                        // 设置 seeking 状态
                        isSeeking = true
                        
                        let newTime = newValue * playerService.playbackState.duration
                        
                        // 立即更新时间显示（无需等待真实 seek）
                        playerService.playbackState.currentTime = newTime
                        
                        // 设置新的防抖动计时器
                        seekDebounceTimer = Timer.scheduledTimer(withTimeInterval: 0.3, repeats: false) { _ in
                            playerService.seek(to: newTime)
                            
                            // 延迟清除 seeking 状态
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                                isSeeking = false
                            }
                        }
                    }
                ),
                in: 0...1,
                onEditingChanged: { editing in
                    if !editing {
                        // 用户结束拖动时，确保执行最后一次 seek
                        seekDebounceTimer?.fire()
                    }
                }
            )
            .accentColor(.accentColor)
            .frame(height: 10) // 减少触摸区域高度
            .disabled(playerService.audioPreparationState != .audioReady)
            
            // 时间显示
            HStack {
                Text(playerService.formatTime(playerService.playbackState.currentTime))
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundColor(.secondary)
                
                Spacer()
                
                // 显示总时长或准备状态
                Group {
                    if isSeeking {
                        HStack(spacing: 4) {
                            ProgressView()
                                .scaleEffect(0.6)
                            Text("跳转中...")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundColor(.accentColor)
                        }
                    } else {
                        switch playerService.audioPreparationState {
                        case .preparing:
                            Text("准备中...")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundColor(.accentColor)
                        case .failed:
                            Text("加载失败")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundColor(.red)
                        default:
                            Text(playerService.formatTime(playerService.playbackState.duration))
                                .font(.system(size: 11, weight: .medium, design: .monospaced))
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }
        }
    }
    
    // MARK: - 功能按钮区域
    
    private var functionButtonsView: some View {
        VStack(spacing: 16) {
            // 第一行功能按钮
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
                
                
            
           
                // 听力模式
                NavigationLink(destination: ListeningModeView(playerService: playerService)) {
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
                .disabled(playerService.isGeneratingSubtitles || playerService.currentSubtitles.isEmpty)
                
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


                // 中文翻译
                Button {
                    if !playerService.currentSubtitles.isEmpty {
                        if !showTranslation {
                            // 如果当前没有翻译，开始翻译
                            if !hasTranslatedSubtitles() {
                                isTranslating = true
                                Task {
                                    await translateSubtitles()
                                    isTranslating = false
                                }
                            }
                        }
                        // 切换翻译显示状态
                        withAnimation {
                            showTranslation.toggle()
                        }
                    } else {
                        // 如果没有字幕，显示错误提示
                        errorMessage = "请先生成字幕"
                        showingErrorAlert = true
                    }
                } label: {
                    VStack(spacing: 2) {
                        ZStack {
                            Image(systemName: showTranslation ? "character.bubble.fill" : "character.bubble")
                                .font(.system(size: 22, weight: .medium))
                                .foregroundColor(showTranslation ? .accentColor : (playerService.currentSubtitles.isEmpty ? .secondary : .primary))
                            
                            // if isTranslating {
                            //     ProgressView()
                            //         .scaleEffect(0.5)
                            //         .padding(2)
                            // }
                            if isTranslating {
                                ProgressView()
                                    .scaleEffect(0.7)
                                    .offset(x: 12, y: 12)
                            }
                        }
                        Text("中文翻译")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(showTranslation ? .accentColor : (playerService.currentSubtitles.isEmpty ? .secondary : .primary))
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 50)
                }
                .disabled(playerService.currentSubtitles.isEmpty && isTranslating)
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
                .foregroundColor(isAudioReady && playerService.hasPreviousSubtitle ? .primary : .secondary)
                .frame(maxWidth: .infinity)
                .frame(height: 50)
            }
            .disabled(!isAudioReady || !playerService.hasPreviousSubtitle)
            
            // 播放/暂停
            Button {
                playerService.togglePlayPause()
            } label: {
                ZStack {
                    // 根据音频准备状态显示不同的图标
                    switch playerService.audioPreparationState {
                    case .idle, .failed:
                        Image(systemName: "play.circle.fill")
                            .font(.system(size: 45))
                            .foregroundColor(.secondary)
                    case .preparing:
                        // 显示准备进度
                        ZStack {
                            Circle()
                                .stroke(Color.gray.opacity(0.3), lineWidth: 4)
                                .frame(width: 45, height: 45)
                            
                            Circle()
                                .trim(from: 0, to: playerService.audioPreparationProgress)
                                .stroke(Color.accentColor, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                                .frame(width: 45, height: 45)
                                .rotationEffect(.degrees(-90))
                                .animation(.easeInOut(duration: 0.3), value: playerService.audioPreparationProgress)
                            
                            // 使用音频波形图标，更符合音频准备状态
                            Image(systemName: "waveform")
                                .font(.system(size: 18, weight: .medium))
                                .foregroundColor(.accentColor)
                                .rotationEffect(.degrees(playerService.audioPreparationProgress * 360))
                                .animation(.easeInOut(duration: 0.5), value: playerService.audioPreparationProgress)
                        }
                    case .audioReady:
                        Image(systemName: playerService.playbackState.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                            .font(.system(size: 45))
                            .foregroundColor(.accentColor)
                    }
                }
            }
            .frame(maxWidth: .infinity)
            .disabled(playerService.audioPreparationState == .preparing)
            
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
                .foregroundColor(isAudioReady && playerService.hasNextSubtitle ? .primary : .secondary)
                .frame(maxWidth: .infinity)
                .frame(height: 50)
            }
            .disabled(!isAudioReady || !playerService.hasNextSubtitle)
            
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
    
    // 新增：音频准备状态相关计算属性
    private var isAudioReady: Bool {
        return playerService.audioPreparationState == .audioReady
    }
    
    private var audioStatusText: String {
        switch playerService.audioPreparationState {
        case .idle:
            return "待准备"
        case .preparing:
            return "准备中 \(Int(playerService.audioPreparationProgress * 100))%"
        case .audioReady:
            return "已就绪"
        case .failed(let error):
            return "准备失败: \(error.localizedDescription)"
        }
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
    
    private func formatTime(_ time: TimeInterval) -> String {
        let minutes = Int(time) / 60
        let seconds = Int(time) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
    
    /// 检查是否已有翻译字幕
    private func hasTranslatedSubtitles() -> Bool {
        return playerService.currentSubtitles.contains { subtitle in
            return subtitle.translatedText != nil && !subtitle.translatedText!.isEmpty
        }
    }
    
    /// 翻译字幕
    private func translateSubtitles() async {
        guard !playerService.currentSubtitles.isEmpty else { return }
        
        // 使用EdgeTTSService单例
        let edgeTTSService = EdgeTTSService.shared
        
        // 创建一个任务组，以便并行翻译所有字幕
        await withTaskGroup(of: (Int, String?).self) { group in
            // 为每个字幕创建一个翻译任务
            for (index, subtitle) in playerService.currentSubtitles.enumerated() {
                // 如果字幕已经有翻译，跳过
                if subtitle.translatedText != nil && !subtitle.translatedText!.isEmpty {
                    continue
                }
                
                // 添加翻译任务
                group.addTask {
                    // 翻译字幕文本
                    let translatedText = await edgeTTSService.translate(text: subtitle.text, to: "zh-CN")
                    return (index, translatedText)
                }
            }
            
            // 收集翻译结果
            var updatedSubtitles = playerService.currentSubtitles
            for await (index, translatedText) in group {
                if let translatedText = translatedText {
                    // 更新字幕的翻译文本
                    updatedSubtitles[index].translatedText = translatedText
                }
            }
            
            // 更新播放服务中的字幕
            playerService.updateSubtitles(updatedSubtitles)
            
            // 保存翻译后的字幕到本地
            await PodcastDataService.shared.updateEpisodeSubtitlesWithMetadata(
                episode.id,
                subtitles: updatedSubtitles,
                generationDate: nil,
                version: nil
            )
        }
    }
}

// MARK: - 字幕行视图
struct SubtitleRowView: View {
    let subtitle: Subtitle
    let isActive: Bool
    let currentTime: TimeInterval?
    let showTranslation: Bool
    let onTap: () -> Void
    
    init(subtitle: Subtitle, isActive: Bool, currentTime: TimeInterval? = nil, showTranslation: Bool = false, onTap: @escaping () -> Void) {
        self.subtitle = subtitle
        self.isActive = isActive
        self.currentTime = currentTime
        self.showTranslation = showTranslation
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
                    // 始终显示高亮版本，不管是否有标注单词
                    if isActive && !subtitle.words.isEmpty, let time = currentTime {
                        // 当前活动字幕 - 显示播放进度和单词高亮
                        wordHighlightText(for: time)
                            .padding(.vertical, 12)
                            .padding(.horizontal, 16)
                    } else {
                        // 非活动字幕 - 显示标注单词高亮（如果有的话）
                        if hasMarkedWords() {
                            markedWordsHighlightText()
                                .padding(.vertical, isActive ? 12 : 10)
                                .padding(.horizontal, isActive ? 16 : 12)
                        } else {
                            // 没有标注单词时的普通文本
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
                    
                    // 显示翻译文本
                    if showTranslation, let translatedText = subtitle.translatedText, !translatedText.isEmpty {
                        Divider()
                            .padding(.horizontal, isActive ? 16 : 12)
                        
                        Text(translatedText)
                            .font(.system(size: 15, weight: .regular))
                            .foregroundColor(.blue)
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
            
            // 检查是否为标注单词
            let isMarkedWord = PodcastPlayerService.shared.isWordMarked(word.word)
            
            // 根据播放时间设置单词样式 - 仿iPhone播客效果
            if currentTime >= word.startTime && currentTime < word.endTime {
                // 当前正在播放的单词 - 黄色高亮
                wordString.foregroundColor = .black
                wordString.font = .system(size: 15, weight: .semibold)
                wordString.backgroundColor = Color.yellow.opacity(0.8)
            } else if currentTime >= word.endTime {
                // 已播放的单词
                if isMarkedWord {
                    // 标注的已播放单词 - 橙色
                    wordString.foregroundColor = .orange
                    wordString.font = .system(size: 15, weight: .bold)
                } else {
                    // 普通已播放单词 - 主色调
                    wordString.foregroundColor = .primary
                    wordString.font = .system(size: 15, weight: .medium)
                }
            } else {
                // 未播放的单词
                if isMarkedWord {
                    // 标注的未播放单词 - 蓝色
                    wordString.foregroundColor = .blue
                    wordString.font = .system(size: 15, weight: .bold)
                } else {
                    // 普通未播放单词 - 较淡颜色
                    wordString.foregroundColor = .secondary
                    wordString.font = .system(size: 15, weight: .regular)
                }
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
    
    private func hasMarkedWords() -> Bool {
        return !PodcastPlayerService.shared.markedWords.isEmpty
    }
    
    /// 标注单词高亮文本（用于非活动字幕）
    private func markedWordsHighlightText() -> some View {
        Text(buildMarkedWordsAttributedString())
            .font(.system(size: 15, weight: isActive ? .medium : .regular))
            .lineSpacing(3)
            .multilineTextAlignment(.leading)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
    
    /// 构建标注单词的属性字符串（用于非活动字幕）
    private func buildMarkedWordsAttributedString() -> AttributedString {
        var attributedString = AttributedString()
        
        // 使用正则表达式分割单词，保留空格和标点
        let pattern = #"(\w+|[^\w\s]+|\s+)"#
        let regex = try! NSRegularExpression(pattern: pattern, options: [])
        let range = NSRange(location: 0, length: subtitle.text.utf16.count)
        let matches = regex.matches(in: subtitle.text, options: [], range: range)
        
        for match in matches {
            guard let range = Range(match.range, in: subtitle.text) else { continue }
            let text = String(subtitle.text[range])
            
            var textString = AttributedString(text)
            
            // 检查是否为标注单词
            let cleanText = text.trimmingCharacters(in: .punctuationCharacters)
            let isMarkedWord = PodcastPlayerService.shared.isWordMarked(cleanText)
            
            if isMarkedWord && !cleanText.isEmpty && cleanText.rangeOfCharacter(from: .letters) != nil {
                // 标注单词：特殊颜色和粗体
                textString.foregroundColor = .orange
                textString.font = .system(size: 15, weight: .bold)
            } else {
                // 普通文本：使用默认样式
                textString.foregroundColor = isActive ? .primary : .secondary
                textString.font = .system(size: 15, weight: isActive ? .medium : .regular)
            }
            
            attributedString.append(textString)
        }
        
        return attributedString
    }
}


// MARK: - 预览
#Preview {
    PodcastPlayerView(episode: PodcastEpisode.example)
}
