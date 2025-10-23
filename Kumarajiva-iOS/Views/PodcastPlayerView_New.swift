import SwiftUI

// MARK: - 播客播放器视图（重构版）
struct PodcastPlayerView_New: View {
    let episode: PodcastEpisode
    @StateObject private var playerService = PodcastPlayerService.shared
    @StateObject private var taskManager = SubtitleGenerationTaskManager.shared
    
    // 状态变量
    @State private var showingVocabularyAnalysis = false
    @State private var showTranslation = false
    @State private var isTranslating = false
    @State private var showingErrorAlert = false
    @State private var errorMessage = ""
    
    var body: some View {
        let _ = print("🎯 [PodcastPlayerView] 开始渲染 - Episode: \(episode.title)")
        let _ = print("🎯 [PodcastPlayerView] secondPageButtons 类型: \(type(of: AnyView(shadowingPracticeButton)))")
        
        return BasePlayerView(
            content: episode,
            configuration: PlayerViewConfiguration(
                customEmptyStateView: AnyView(podcastEmptyStateView),
                onPrepare: prepareEpisode,
                onDisappear: onDisappear
            ),
            subtitleRowBuilder: { subtitle, isActive, currentTime, showTranslation, onTap in
                PodcastSubtitleRowView(
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
    }
    
    // MARK: - 播客特定的空状态视图
    
    private var podcastEmptyStateView: some View {
        VStack(spacing: 16) {
            if playerService.isGeneratingSubtitles {
                generatingSubtitlesView
            } else {
                noSubtitlesView
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    private var generatingSubtitlesView: some View {
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
            
            Text(playerService.subtitleGenerationStatusText)
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
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
                icon: "arrow.clockwise",
                title: "重新转录",
                isActive: false,
                isDisabled: playerService.isGeneratingSubtitles,
                action: {
                    if !playerService.isGeneratingSubtitles {
                        Task {
                            await playerService.generateSubtitlesForCurrentEpisode()
                        }
                    }
                }
            ),
            FunctionButton(
                icon: showTranslation ? "character.bubble.fill" : "character.bubble",
                title: "中文翻译",
                isActive: showTranslation,
                isDisabled: playerService.currentSubtitles.isEmpty && isTranslating,
                showProgress: isTranslating,
                action: {
                    if !playerService.currentSubtitles.isEmpty {
                        if !showTranslation {
                            if !hasTranslatedSubtitles() {
                                isTranslating = true
                                Task {
                                    await translateSubtitles()
                                    isTranslating = false
                                }
                            }
                        }
                        withAnimation {
                            showTranslation.toggle()
                        }
                    } else {
                        errorMessage = "请先生成字幕"
                        showingErrorAlert = true
                    }
                }
            )
        ]
    }
    
    // MARK: - 第二页按钮（跟读练习）
    
    private var shadowingPracticeButton: some View {
        let _ = print("🟣 [PodcastPlayerView] shadowingPracticeButton 正在构建")
        let _ = print("🟣 [PodcastPlayerView] - isGeneratingSubtitles: \(playerService.isGeneratingSubtitles)")
        let _ = print("🟣 [PodcastPlayerView] - currentSubtitles.isEmpty: \(playerService.currentSubtitles.isEmpty)")
        let _ = print("🟣 [PodcastPlayerView] - isAudioReady: \(isAudioReady)")
        
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
                print("🟣 [PodcastPlayerView] 跟读练习按钮已显示")
            }
        }
        .padding(.horizontal, 8)
        .onAppear {
            print("🟣 [PodcastPlayerView] shadowingPracticeButton Grid 已显示")
        }
    }
    
    @ViewBuilder
    private func destinationForShadowingPractice() -> some View {
        if !playerService.currentSubtitles.isEmpty,
           let audioURL = playerService.playbackState.currentEpisode?.audioURL {
            SubtitleShadowingPracticeView(
                episode: episode,
                subtitles: playerService.currentSubtitles,
                audioURL: audioURL,
                startIndex: playerService.playbackState.currentSubtitleIndex ?? 0
            )
        } else {
            EmptyView()
        }
    }
    
    // MARK: - 辅助方法
    
    private func prepareEpisode() {
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
    
    private func onDisappear() {
        // 离开页面时不停止播放，让音频继续在后台播放
        print("🎧 [PlayerView] 页面消失，音频继续播放")
    }
    
    private func generateSubtitlesManually() {
        Task {
            await playerService.generateSubtitlesForCurrentEpisode()
        }
    }
    
    private func hasTranslatedSubtitles() -> Bool {
        return playerService.currentSubtitles.contains { subtitle in
            return subtitle.translatedText != nil && !subtitle.translatedText!.isEmpty
        }
    }
    
    private func translateSubtitles() async {
        guard !playerService.currentSubtitles.isEmpty else { return }
        
        let edgeTTSService = EdgeTTSService.shared
        
        await withTaskGroup(of: (Int, String?).self) { group in
            for (index, subtitle) in playerService.currentSubtitles.enumerated() {
                if subtitle.translatedText != nil && !subtitle.translatedText!.isEmpty {
                    continue
                }
                
                group.addTask {
                    let translatedText = await edgeTTSService.translate(text: subtitle.text, to: "zh-CN")
                    return (index, translatedText)
                }
            }
            
            var updatedSubtitles = playerService.currentSubtitles
            for await (index, translatedText) in group {
                if let translatedText = translatedText {
                    updatedSubtitles[index].translatedText = translatedText
                }
            }
            
            playerService.updateSubtitles(updatedSubtitles)
            
            await PodcastDataService.shared.updateEpisodeSubtitlesWithMetadata(
                episode.id,
                subtitles: updatedSubtitles,
                generationDate: nil,
                version: nil
            )
        }
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
    
    private var isAudioReady: Bool {
        return playerService.audioPreparationState == .audioReady
    }
}

// MARK: - 预览
#Preview {
    PodcastPlayerView_New(episode: PodcastEpisode.example)
}
