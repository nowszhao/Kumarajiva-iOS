import SwiftUI

// MARK: - 视频播放器视图（重构版）
struct VideoPlayerView_New: View {
    let video: YouTubeVideo
    @StateObject private var playerService = PodcastPlayerService.shared
    @StateObject private var taskManager = SubtitleGenerationTaskManager.shared
    @StateObject private var youtubeExtractor = YouTubeAudioExtractor.shared
    
    // 状态变量
    @State private var showingVocabularyAnalysis = false
    @State private var showTranslation = false
    @State private var isTranslating = false
    @State private var showingErrorAlert = false
    @State private var errorMessage = ""
    @State private var hasDownloaded = false
    @State private var isDownloading = false
    
    var body: some View {
        let _ = print("🎬 [VideoPlayerView] 开始渲染 - Video: \(video.title)")
        let _ = print("🎬 [VideoPlayerView] secondPageButtons 类型: \(type(of: AnyView(shadowingPracticeButton)))")
        
        return BasePlayerView(
            content: video,
            configuration: PlayerViewConfiguration(
                customStatusView: AnyView(YouTubeDownloadStatusView()),
                customEmptyStateView: AnyView(videoEmptyStateView),
                onPrepare: prepareVideo,
                onDisappear: onDisappear
            ),
            subtitleRowBuilder: { subtitle, isActive, currentTime, showTranslation, onTap in
                VideoSubtitleRowView(
                    subtitle: subtitle,
                    isActive: isActive,
                    currentTime: currentTime,
                    showTranslation: showTranslation,
                    onTap: onTap
                )
            },
            functionButtons: createFunctionButtons(),
            secondPageButtons: AnyView(shadowingPracticeButton)
        )
        .sheet(isPresented: $showingVocabularyAnalysis) {
            VocabularyAnalysisView(playerService: playerService)
        }
        .onReceive(youtubeExtractor.$downloadStatus) { status in
            print("📺 [VideoPlayer] 下载状态更新: '\(status)'")
            
            if status == "下载完成" {
                isDownloading = false
                hasDownloaded = true
            } else if status.contains("错误") || status.contains("失败") {
                isDownloading = false
                hasDownloaded = false
            }
        }
        .onReceive(youtubeExtractor.$isExtracting) { isExtracting in
            print("📺 [VideoPlayer] 提取状态更新: \(isExtracting)")
            
            if isExtracting {
                isDownloading = true
            }
        }
        .onReceive(youtubeExtractor.$extractionProgress) { progress in
            print("📺 [VideoPlayer] 下载进度更新: \(Int(progress * 100))%")
        }
        .alert("提示", isPresented: $showingErrorAlert) {
            Button("确定", role: .cancel) { }
        } message: {
            Text(errorMessage)
        }
    }
    
    // MARK: - 视频特定的空状态视图
    
    private var videoEmptyStateView: some View {
        VStack(spacing: 16) {
            if isDownloading {
                downloadingView
            } else if playerService.isGeneratingSubtitles {
                generatingSubtitlesView
            } else if !hasDownloaded {
                needsDownloadView
            } else {
                noSubtitlesView
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    private var downloadingView: some View {
        VStack(spacing: 12) {
            ZStack {
                Circle()
                    .stroke(Color.blue.opacity(0.3), lineWidth: 8)
                    .frame(width: 80, height: 80)
                
                Circle()
                    .trim(from: 0, to: youtubeExtractor.extractionProgress)
                    .stroke(Color.blue, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                    .frame(width: 80, height: 80)
                    .rotationEffect(.degrees(-90))
                    .animation(.easeInOut(duration: 0.3), value: youtubeExtractor.extractionProgress)
                
                if youtubeExtractor.extractionProgress > 0 {
                    Text("\(Int(youtubeExtractor.extractionProgress * 100))%")
                        .font(.headline)
                        .fontWeight(.semibold)
                        .foregroundColor(.blue)
                } else {
                    Image(systemName: "arrow.down")
                        .font(.title2)
                        .foregroundColor(.blue)
                }
            }
            
            Text("正在下载视频...")
                .font(.body)
                .foregroundColor(.secondary)
            
            if !youtubeExtractor.downloadStatus.isEmpty {
                Text(youtubeExtractor.downloadStatus)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
    }
    
    private var generatingSubtitlesView: some View {
        VStack(spacing: 12) {
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
            
            Text(playerService.subtitleGenerationStatusText)
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
    }
    
    private var needsDownloadView: some View {
        VStack(spacing: 16) {
            Image(systemName: "play.rectangle")
                .font(.system(size: 50))
                .foregroundColor(.secondary)
            
            VStack(spacing: 8) {
                Text("准备播放视频")
                    .font(.title2)
                    .fontWeight(.semibold)
                    .foregroundColor(.primary)
                
                Text("点击下载按钮开始播放")
                    .font(.body)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }
            
            Button {
                downloadVideoManually()
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "icloud.and.arrow.down")
                        .font(.system(size: 18, weight: .medium))
                    Text("下载并播放")
                        .font(.system(size: 16, weight: .medium))
                }
                .foregroundColor(.white)
                .padding(.horizontal, 24)
                .padding(.vertical, 12)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.accentColor)
                )
            }
            .disabled(isDownloading)
            .padding(.top, 8)
        }
    }
    
    private var noSubtitlesView: some View {
        VStack(spacing: 12) {
            Image(systemName: "captions.bubble")
                .font(.system(size: 40))
                .foregroundColor(.secondary)
            
            Text("暂无字幕")
                .font(.headline)
                .foregroundColor(.secondary)
        }
    }
    
    // MARK: - 功能按钮配置
    
    private func createFunctionButtons() -> [FunctionButton] {
        return [
            FunctionButton(
                icon: playerService.playbackState.isLooping ? "repeat.1" : "repeat",
                title: "循环",
                isActive: playerService.playbackState.isLooping,
                isDisabled: false,
                action: {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        playerService.toggleLoop()
                    }
                }
            ),
            FunctionButton(
                icon: "text.magnifyingglass",
                title: "生词解析",
                isActive: false,
                isDisabled: playerService.currentSubtitles.isEmpty,
                action: {
                    if !playerService.currentSubtitles.isEmpty {
                        showingVocabularyAnalysis = true
                    } else {
                        errorMessage = "请先生成字幕再进行生词解析"
                        showingErrorAlert = true
                    }
                }
            ),
            FunctionButton(
                icon: "arrow.clockwise",
                title: "重新转录",
                isActive: false,
                isDisabled: playerService.isGeneratingSubtitles,
                action: {
                    if !playerService.isGeneratingSubtitles {
                        Task {
                            await generateSubtitlesForVideo()
                        }
                    }
                }
            ),
            FunctionButton(
                icon: "headphones.circle",
                title: "听力模式",
                isActive: false,
                isDisabled: playerService.isGeneratingSubtitles || playerService.currentSubtitles.isEmpty,
                isNavigationLink: true,
                navigationDestination: AnyView(ListeningModeView(playerService: playerService))
            ),
            FunctionButton(
                icon: showTranslation ? "character.bubble.fill" : "character.bubble",
                title: "中文翻译",
                isActive: showTranslation,
                isDisabled: playerService.isGeneratingSubtitles || isTranslating,
                showProgress: isTranslating,
                action: {
                    if !playerService.currentSubtitles.isEmpty {
                        if !showTranslation {
                            withAnimation {
                                showTranslation = true
                            }
                            Task {
                                await translateSubtitles()
                            }
                        } else {
                            withAnimation {
                                showTranslation = false
                            }
                        }
                    } else {
                        errorMessage = "请先生成字幕再使用翻译功能"
                        showingErrorAlert = true
                    }
                }
            )
        ]
    }
    
    // MARK: - 第二页按钮
    
    private var shadowingPracticeButton: some View {
        let _ = print("🎬 [VideoPlayerView] shadowingPracticeButton 正在构建")
        let _ = print("🎬 [VideoPlayerView] - isGeneratingSubtitles: \(playerService.isGeneratingSubtitles)")
        let _ = print("🎬 [VideoPlayerView] - currentSubtitles.isEmpty: \(playerService.currentSubtitles.isEmpty)")
        let _ = print("🎬 [VideoPlayerView] - isAudioReady: \(isAudioReady)")
        
        return LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 0), count: 5), spacing: 8) {
            NavigationLink(destination: destinationForShadowingPractice()) {
                VStack(spacing: 2) {
                    Image(systemName: "mic.badge.plus")
                        .font(.system(size: 22, weight: .medium))
                        .foregroundColor((playerService.isGeneratingSubtitles || playerService.currentSubtitles.isEmpty || !isAudioReady) ? .secondary : .primary)
                        .frame(height: 24)
                    
                    Text("跟读练习")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor((playerService.isGeneratingSubtitles || playerService.currentSubtitles.isEmpty || !isAudioReady) ? .secondary : .primary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
                .frame(maxWidth: .infinity)
                .frame(height: 40)
            }
            .disabled(playerService.isGeneratingSubtitles || playerService.currentSubtitles.isEmpty || !isAudioReady)
            .onAppear {
                print("🎬 [VideoPlayerView] 跟读练习按钮已显示")
            }
        }
        .padding(.horizontal, 8)
        .onAppear {
            print("🎬 [VideoPlayerView] shadowingPracticeButton Grid 已显示")
        }
    }
    
    // MARK: - 辅助方法
    
    @ViewBuilder
    private func destinationForShadowingPractice() -> some View {
        if !playerService.currentSubtitles.isEmpty,
           let audioURL = playerService.playbackState.currentEpisode?.audioURL {
            SubtitleShadowingPracticeView(
                video: video,
                subtitles: playerService.currentSubtitles,
                audioURL: audioURL,
                startIndex: playerService.playbackState.currentSubtitleIndex ?? 0
            )
        } else {
            EmptyView()
        }
    }
    
    private func prepareVideo() {
        print("📺 [VideoPlayer] 准备视频播放: \(video.title)")
        
        let isSameVideo = playerService.playbackState.currentEpisode?.id == video.videoId
        
        if !isSameVideo {
            playerService.clearCurrentPlaybackState()
            hasDownloaded = false
            print("📺 [VideoPlayer] 切换到新视频，清空播放状态: \(video.title)")
        } else {
            print("📺 [VideoPlayer] 打开当前播放视频，保持播放状态: \(video.title)")
            if playerService.audioPreparationState == .audioReady {
                hasDownloaded = true
                print("📺 [VideoPlayer] 视频已准备完成，无需重新处理")
                return
            }
        }
        
        print("📺 [VideoPlayer] 视频准备完成，等待用户手动下载")
    }
    
    private func onDisappear() {
        print("📺 [VideoPlayer] 页面消失，音频继续播放")
    }
    
    private func downloadVideoManually() {
        guard !isDownloading else { return }
        
        Task {
            await MainActor.run {
                isDownloading = true
            }
            
            do {
                guard let videoId = YouTubeAudioExtractor.shared.extractVideoId(from: video.youtubeURL) else {
                    await MainActor.run {
                        errorMessage = "无法从URL中提取视频ID"
                        showingErrorAlert = true
                        isDownloading = false
                    }
                    return
                }
                
                print("📺 [VideoPlayer] 提取到视频ID: \(videoId)")
                
                let downloadResult = try await YouTubeAudioExtractor.shared.extractAudioAndSubtitles(from: videoId)
                
                print("📺 [VideoPlayer] ✅ 音频和字幕提取成功")
                print("📺 [VideoPlayer] 音频URL: \(downloadResult.audioURL.prefix(100))...")
                print("📺 [VideoPlayer] 字幕数量: \(downloadResult.subtitles.count)")
                
                await MainActor.run {
                    let mockEpisode = createMockEpisodeFromVideo(
                        audioURL: downloadResult.audioURL,
                        subtitles: downloadResult.subtitles,
                        videoInfo: downloadResult.videoInfo
                    )
                    playerService.prepareEpisode(mockEpisode)
                    hasDownloaded = true
                    isDownloading = false
                    
                    print("📺 [VideoPlayer] ✅ 开始播放YouTube音频，包含 \(downloadResult.subtitles.count) 条SRT字幕")
                }
                
            } catch {
                await MainActor.run {
                    print("📺 [VideoPlayer] 音频流提取失败: \(error)")
                    isDownloading = false
                    
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
    
    private func createMockEpisodeFromVideo(audioURL: String, subtitles: [Subtitle] = [], videoInfo: VideoInfo? = nil) -> PodcastEpisode {
        if let info = videoInfo {
            return PodcastEpisode(
                id: video.videoId,
                title: info.title,
                description: info.description,
                audioURL: audioURL,
                duration: info.duration,
                publishDate: video.publishDate,
                subtitles: subtitles,
                subtitleGenerationDate: Date(),
                subtitleVersion: "vtt_1.0"
            )
        } else {
            return PodcastEpisode(
                id: video.videoId,
                title: video.title,
                description: video.description ?? "",
                audioURL: audioURL,
                duration: video.duration,
                publishDate: video.publishDate,
                subtitles: subtitles,
                subtitleGenerationDate: Date(),
                subtitleVersion: "vtt_1.0"
            )
        }
    }
    
    private func generateSubtitlesForVideo() async {
        await playerService.generateSubtitlesForCurrentEpisode()
    }
    
    private func translateSubtitles() async {
        guard !playerService.currentSubtitles.isEmpty else { return }
        
        await MainActor.run {
            isTranslating = true
        }
        
        await withTaskGroup(of: (Int, String?).self) { group in
            for (index, subtitle) in playerService.currentSubtitles.enumerated() {
                if subtitle.translatedText != nil {
                    continue
                }
                
                group.addTask {
                    let translatedText = await EdgeTTSService.shared.translate(text: subtitle.text, to: "zh-CN")
                    return (index, translatedText)
                }
            }
            
            var updatedSubtitles = playerService.currentSubtitles
            for await (index, translatedText) in group {
                if let translatedText = translatedText {
                    updatedSubtitles[index].translatedText = translatedText
                }
            }
            
            await MainActor.run {
                playerService.updateSubtitles(updatedSubtitles)
            }
        }
        
        await MainActor.run {
            isTranslating = false
        }
    }
    
    // MARK: - 计算属性
    
    private var isAudioReady: Bool {
        return playerService.audioPreparationState == .audioReady
    }
}

// MARK: - YouTube下载状态视图
struct YouTubeDownloadStatusView: View {
    @StateObject private var youtubeExtractor = YouTubeAudioExtractor.shared
    
    var body: some View {
        if !youtubeExtractor.downloadStatus.isEmpty {
            HStack(spacing: 6) {
                if youtubeExtractor.isExtracting {
                    ProgressView()
                        .scaleEffect(0.7)
                } else {
                    Image(systemName: "arrow.down.circle")
                        .foregroundColor(.blue)
                }
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(youtubeExtractor.downloadStatus)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                    
                    if youtubeExtractor.isExtracting && youtubeExtractor.extractionProgress > 0 {
                        ProgressView(value: youtubeExtractor.extractionProgress)
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
}

// MARK: - 预览
#Preview {
    VideoPlayerView_New(video: YouTubeVideo.example)
}
