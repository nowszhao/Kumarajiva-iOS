import SwiftUI

struct VideoPlayerView: View {
    let video: YouTubeVideo
    @StateObject private var playerService = PodcastPlayerService.shared
    @StateObject private var taskManager = SubtitleGenerationTaskManager.shared
    @StateObject private var youtubeExtractor = YouTubeAudioExtractor.shared
    @Environment(\.dismiss) private var dismiss
    
    // 状态变量
    @State private var showingErrorAlert = false
    @State private var errorMessage = ""
    @State private var showingVocabularyAnalysis = false
    @State private var showingConfigPanel = false
    @State private var showDownloadProgress = false
    
    var body: some View {
        VStack(spacing: 0) {
            // YouTube下载进度顶部栏
            if showDownloadProgress {
                downloadProgressTopBar
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
            
            // 字幕显示区域
            subtitleDisplayView
            
            // 播放控制面板
            playbackControlView
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .tabBar) // 隐藏底部TabBar
        .onAppear {
            // 准备视频播放（需要适配YouTube视频）
            prepareVideoForPlayback()
            
            
        }
        .onDisappear {
            // 离开页面时音频继续播放
            print("📺 [VideoPlayer] 页面消失，音频继续播放")
        }
        .onReceive(youtubeExtractor.$downloadStatus) { status in
            print("📺 [VideoPlayer] 下载状态更新: '\(status)'")
            withAnimation(.easeInOut(duration: 0.3)) {
                showDownloadProgress = !status.isEmpty
            }
        }
        .onReceive(youtubeExtractor.$isExtracting) { isExtracting in
            print("📺 [VideoPlayer] 提取状态更新: \(isExtracting)")
            if isExtracting {
                withAnimation(.easeInOut(duration: 0.3)) {
                    showDownloadProgress = true
                }
            } else {
                // 下载完成后延迟3秒隐藏进度条
                DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
                    withAnimation(.easeInOut(duration: 0.3)) {
                        print("📺 [VideoPlayer] 隐藏下载进度条")
                        showDownloadProgress = false
                    }
                }
            }
        }
        .onReceive(youtubeExtractor.$extractionProgress) { progress in
            print("📺 [VideoPlayer] 下载进度更新: \(Int(progress * 100))%")
        }
        .onReceive(playerService.$errorMessage) { errorMessage in
            if let error = errorMessage {
                self.errorMessage = error
                showingErrorAlert = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    playerService.errorMessage = nil
                }
            }
        }
        .alert("提示", isPresented: $showingErrorAlert) {
            Button("确定", role: .cancel) { }
        } message: {
            Text(errorMessage)
        }
        .sheet(isPresented: $showingVocabularyAnalysis) {
            VocabularyAnalysisView(playerService: playerService)
        }
    }
    
    // MARK: - YouTube下载进度顶部栏
    
    private var downloadProgressTopBar: some View {
        VStack(spacing: 8) {
            HStack(spacing: 12) {
                // 下载图标
                ZStack {
                    if youtubeExtractor.isExtracting {
                        Circle()
                            .stroke(Color.blue.opacity(0.3), lineWidth: 3)
                            .frame(width: 24, height: 24)
                        
                        Circle()
                            .trim(from: 0, to: youtubeExtractor.extractionProgress)
                            .stroke(Color.blue, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                            .frame(width: 24, height: 24)
                            .rotationEffect(.degrees(-90))
                            .animation(.easeInOut(duration: 0.3), value: youtubeExtractor.extractionProgress)
                        
                        Image(systemName: "arrow.down")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundColor(.blue)
                    } else {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 24, weight: .medium))
                            .foregroundColor(.green)
                    }
                }
                
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(youtubeExtractor.downloadStatus)
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(.primary)
                            .lineLimit(1)
                        
                        Spacer()
                        
                        if youtubeExtractor.isExtracting {
                            Text("\(Int(youtubeExtractor.extractionProgress * 100))%")
                                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                                .foregroundColor(.blue)
                        }
                    }
                    
                    // 下载进度条
                    if youtubeExtractor.isExtracting && youtubeExtractor.extractionProgress > 0 {
                        ProgressView(value: youtubeExtractor.extractionProgress)
                            .progressViewStyle(LinearProgressViewStyle(tint: .blue))
                            .frame(height: 6)
                            .background(Color.blue.opacity(0.1))
                            .cornerRadius(3)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 0)
                    .fill(youtubeExtractor.isExtracting ? 
                          Color.blue.opacity(0.05) : Color.green.opacity(0.05))
                    .overlay(
                        Rectangle()
                            .fill(youtubeExtractor.isExtracting ? 
                                  Color.blue.opacity(0.2) : Color.green.opacity(0.2))
                            .frame(height: 1),
                        alignment: .bottom
                    )
            )
        }
        .animation(.easeInOut(duration: 0.3), value: youtubeExtractor.isExtracting)
    }
    
    // MARK: - 字幕显示区域
    
    private var subtitleDisplayView: some View {
        VStack(spacing: 16) {
            // 视频信息
            VStack(spacing: 8) {
                Text(video.title)
                    .font(.headline)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                
                Text(formatDate(video.publishDate))
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                // 视频时长和观看次数
                HStack {
                    Label(formatDuration(video.duration), systemImage: "clock")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    if let viewCount = video.viewCount {
                        Text("•")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        
                        Label(viewCount, systemImage: "eye")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                
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
                    
                    // Text("点击下方按钮生成字幕")
                    //     .font(.body)
                    //     .foregroundColor(.secondary)
                    //     .multilineTextAlignment(.center)
                    
                    // Button {
                    //     generateSubtitlesManually()
                    // } label: {
                    //     Label("生成字幕", systemImage: "waveform.and.mic")
                    //         .font(.headline)
                    //         .foregroundColor(.white)
                    //         .padding()
                    //         .background(isWhisperKitReady ? Color.accentColor : Color.gray)
                    //         .cornerRadius(12)
                    // }
                    // .disabled(!isWhisperKitReady)
                    // .padding(.top, 8)
                    
                    // if !isWhisperKitReady {
                    //     VStack(spacing: 8) {
                    //         if WhisperKitService.shared.shouldPromptForModelDownload() {
                    //             Button {
                    //                 Task {
                    //                     await WhisperKitService.shared.smartDownloadModel()
                    //                 }
                    //             } label: {
                    //                 HStack {
                    //                     Image(systemName: "icloud.and.arrow.down")
                    //                     Text("下载WhisperKit模型")
                    //                 }
                    //                 .font(.caption)
                    //                 .foregroundColor(.white)
                    //                 .padding(.horizontal, 12)
                    //                 .padding(.vertical, 6)
                    //                 .background(Color.blue)
                    //                 .cornerRadius(8)
                    //             }
                    //         } else {
                    //             Text("请先在\"我的\"页面设置中配置WhisperKit")
                    //                 .font(.caption)
                    //                 .foregroundColor(.orange)
                    //                 .multilineTextAlignment(.center)
                    //         }
                            
                    //         Text("当前状态: \(whisperStatusText)")
                    //             .font(.caption2)
                    //             .foregroundColor(.secondary)
                    //             .multilineTextAlignment(.center)
                    //     }
                    //     .padding(.top, 4)
                    // }
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
                    .id(index)
                }
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 16)
            .onChange(of: playerService.playbackState.currentSubtitleIndex) { oldIndex, newIndex in
                if let index = newIndex {
                    withAnimation(.easeInOut(duration: 0.3)) {
                        proxy.scrollTo(index, anchor: .center)
                    }
                    print("📺 [VideoPlayer] 字幕滚动：滚动到索引 \(index)")
                }
            }
            .onAppear {
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
                        guard playerService.audioPreparationState == .audioReady,
                              playerService.playbackState.duration > 0 else { return 0 }
                        return playerService.playbackState.currentTime / playerService.playbackState.duration
                    },
                    set: { newValue in
                        guard playerService.audioPreparationState == .audioReady else { return }
                        let newTime = newValue * playerService.playbackState.duration
                        playerService.seek(to: newTime)
                    }
                ),
                in: 0...1
            )
            .accentColor(.accentColor)
            .frame(height: 10)
            .disabled(playerService.audioPreparationState != .audioReady)
            
            // 时间显示
            HStack {
                Text(playerService.formatTime(playerService.playbackState.currentTime))
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundColor(.secondary)
                
                Spacer()
                
                Group {
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
    
    // 功能按钮和主控制区域代码与PodcastPlayerView相同
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
                // 如果当前已有字幕（包括SRT字幕），直接显示分析
                if !playerService.currentSubtitles.isEmpty {
                    showingVocabularyAnalysis = true
                } else {
                    // 如果没有字幕，提示用户先生成字幕
                    errorMessage = "请先生成字幕再进行生词解析"
                    showingErrorAlert = true
                }
            } label: {
                VStack(spacing: 2) {
                    ZStack {
                        Image(systemName: "text.magnifyingglass")
                            .font(.system(size: 22, weight: .medium))
                        
                        // 如果有标注单词，显示小红点
                        if playerService.markedWordCount > 0 {
                            Circle()
                                .fill(Color.red)
                                .frame(width: 8, height: 8)
                                .offset(x: 8, y: -8)
                        }
                    }
                    
                    Text("生词解析")
                        .font(.system(size: 10, weight: .medium))
                    
                    // 显示标注数量
                    if playerService.markedWordCount > 0 {
                        Text("(\(playerService.markedWordCount))")
                            .font(.system(size: 8, weight: .medium))
                            .foregroundColor(.red)
                    }
                }
                .foregroundColor(!playerService.currentSubtitles.isEmpty ? .primary : .secondary)
                .frame(maxWidth: .infinity)
                .frame(height: 50)
            }
            
            // 重新转录字幕
            Button {
                if !playerService.isGeneratingSubtitles {
                    Task {
                        await generateSubtitlesForVideo()
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
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 8)
    }
    
    private var mainControlsView: some View {
        HStack(spacing: 0) {
            // 播放速度
            Menu {
                ForEach([0.5, 0.6, 0.65, 0.7, 0.75, 1.0, 1.25, 1.5, 2.0], id: \.self) { rate in
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
                    switch playerService.audioPreparationState {
                    case .idle, .failed:
                        Image(systemName: "play.circle.fill")
                            .font(.system(size: 45))
                            .foregroundColor(.secondary)
                    case .preparing:
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
    
    private func formatDuration(_ duration: TimeInterval) -> String {
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
    
    private func prepareVideoForPlayback() {
        print("📺 [VideoPlayer] 准备视频播放: \(video.title)")
        
        // 检查是否是同一个视频，如果是则不清空状态
        let isSameVideo = playerService.playbackState.currentEpisode?.id == video.videoId
        
        if !isSameVideo {
            // 只有切换到不同视频时才清空播放器状态
            playerService.clearCurrentPlaybackState()
            print("📺 [VideoPlayer] 切换到新视频，清空播放状态: \(video.title)")
        } else {
            print("📺 [VideoPlayer] 打开当前播放视频，保持播放状态: \(video.title)")
            // 如果是同一个视频且已经准备好，直接返回
            if playerService.audioPreparationState == .audioReady {
                print("📺 [VideoPlayer] 视频已准备完成，无需重新处理")
                return
            }
        }
        
        // 使用YouTube音频提取器v2.0获取音频和字幕
        Task {
            do {
                // 从YouTube URL中提取视频ID
                guard let videoId = YouTubeAudioExtractor.shared.extractVideoId(from: video.youtubeURL) else {
                    await MainActor.run {
                        errorMessage = "无法从URL中提取视频ID"
                        showingErrorAlert = true
                    }
                    return
                }
                
                print("📺 [VideoPlayer] 提取到视频ID: \(videoId)")
                
                // 使用新的下载模式API提取音频流和字幕
                let downloadResult = try await YouTubeAudioExtractor.shared.extractAudioAndSubtitles(from: videoId)
                
                print("📺 [VideoPlayer] ✅ 音频和字幕提取成功")
                print("📺 [VideoPlayer] 音频URL: \(downloadResult.audioURL.prefix(100))...")
                print("📺 [VideoPlayer] 字幕数量: \(downloadResult.subtitles.count)")
                // 使用音频流URL和字幕创建Episode并开始播放
                await MainActor.run {
                    // 创建包含SRT字幕的模拟Episode对象
                    let mockEpisode = createMockEpisodeFromVideo(
                        audioURL: downloadResult.audioURL,
                        subtitles: downloadResult.subtitles,
                        videoInfo: downloadResult.videoInfo
                    )
                    // 开始播放
                    playerService.prepareEpisode(mockEpisode)
                    
                    print("📺 [VideoPlayer] ✅ 开始播放YouTube音频，包含 \(downloadResult.subtitles.count) 条SRT字幕")
                }
                
            } catch {
                await MainActor.run {
                    print("📺 [VideoPlayer] 音频流提取失败: \(error)")
                    
                    // 根据错误类型提供不同的用户友好信息
                    if let youtubeError = error as? YouTubeExtractionError {
                        switch youtubeError {
                        case .networkError:
                            errorMessage = "网络连接失败，请检查网络设置"
                        case .videoNotFound:
                            errorMessage = "视频不存在或无法访问"
                        case .serverError(let message):
                            if message.contains("无法连接到服务器") {
                                errorMessage = "无法连接到下载服务器，请稍后重试"
                            } else {
                                errorMessage = "服务器错误: \(message)"
                            }
                        case .downloadFailed(let message):
                            errorMessage = "下载失败: \(message)"
                        case .timeout:
                            errorMessage = "下载超时，请检查网络连接或稍后重试"
                        case .taskCancelled:
                            errorMessage = "下载已取消"
                        case .invalidURL, .invalidVideoId:
                            errorMessage = "视频链接无效"
                        case .parseError:
                            errorMessage = "数据解析失败，请稍后重试"
                        case .audioNotAvailable:
                            errorMessage = "该视频没有可用的音频流"
                        }
                    } else if let urlError = error as? URLError {
                        switch urlError.code {
                        case .timedOut:
                            errorMessage = "网络请求超时，请检查网络连接后重试"
                        case .notConnectedToInternet:
                            errorMessage = "设备未连接到互联网"
                        case .networkConnectionLost:
                            errorMessage = "网络连接中断，请重新连接后重试"
                        case .cannotFindHost, .cannotConnectToHost:
                            errorMessage = "无法连接到下载服务器"
                        default:
                            errorMessage = "网络错误: \(urlError.localizedDescription)"
                        }
                    } else {
                        errorMessage = "播放失败，请稍后重试或检查网络连接"
                    }
                    
                    showingErrorAlert = true
                }
            }
        }
    }
    
    /// 检查URL是否为YouTube URL
    private func isYouTubeURL(_ url: String) -> Bool {
        return YouTubeAudioExtractor.shared.isYouTubeURL(url)
    }
    
    /// 创建模拟Episode对象从视频信息（更新版本，支持SRT字幕）
    private func createMockEpisodeFromVideo(audioURL: String, subtitles: [Subtitle] = [], videoInfo: VideoInfo? = nil) -> PodcastEpisode {
        // 将YouTube视频转换为PodcastEpisode格式以复用现有播放器
        // 如果有来自后端的视频信息，使用更准确的数据
        if let info = videoInfo {
            return PodcastEpisode(
                id: video.videoId,
                title: info.title,
                description: info.description,
                audioURL: audioURL,
                duration: info.duration,
                publishDate: video.publishDate,
                subtitles: subtitles,
                subtitleGenerationDate: Date(), // VTT字幕是预生成的
                subtitleVersion: "vtt_1.0"  // 更新为VTT版本
            )
        } else {
            // 回退到原始视频信息
            return PodcastEpisode(
                id: video.videoId,
                title: video.title,
                description: video.description ?? "",
                audioURL: audioURL,
                duration: video.duration,
                publishDate: video.publishDate,
                subtitles: subtitles,
                subtitleGenerationDate: Date(),
                subtitleVersion: "vtt_1.0"  // 更新为VTT版本
            )
        }
    }
    
    private func generateSubtitlesManually() {
        Task { @MainActor in
            await generateSubtitlesForVideo()
        }
    }
    
    private func generateSubtitlesForVideo() async {
        // 确保在主线程执行
        await MainActor.run {
            print("📺 [VideoPlayer] 开始为视频生成字幕: \(video.title)")
        }
        
        // 调用播放器服务生成字幕
        await playerService.generateSubtitlesForCurrentEpisode()
    }
}

// MARK: - 预览
#Preview {
    VideoPlayerView(video: YouTubeVideo.example)
} 
