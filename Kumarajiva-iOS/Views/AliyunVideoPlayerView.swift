import SwiftUI

// MARK: - 阿里云盘视频播放器视图（重构版）
struct AliyunVideoPlayerView: View {
    let file: AliyunMediaFile
    @StateObject private var playerService = PodcastPlayerService.shared
    @StateObject private var aliyunService = AliyunDriveService.shared
    
    // 状态变量
    @State private var showingVocabularyAnalysis = false
    @State private var showTranslation = false
    @State private var isTranslating = false
    @State private var showingErrorAlert = false
    @State private var errorMessage = ""
    @State private var isPreparingAudio = false
    @State private var availableSubtitles: [AliyunSubtitleFile] = []
    @State private var selectedSubtitle: AliyunSubtitleFile?
    @State private var isLoadingSubtitles = false
    @State private var showingSubtitlePicker = false
    @State private var manualSelectedSubtitle: AliyunSubtitleFile?
    @State private var showingShadowingPractice = false
    
    var body: some View {
        BasePlayerView(
            content: file,
            configuration: PlayerViewConfiguration(
                customStatusView: AnyView(aliyunStatusView),
                customEmptyStateView: AnyView(aliyunEmptyStateView),
                onPrepare: prepareAudio,
                onDisappear: onDisappear
            ),
            subtitleRowBuilder: { subtitle, isActive, currentTime, showTranslation, onTap in
                AliyunSubtitleRowView(
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
        .sheet(isPresented: $showingSubtitlePicker) {
            if let driveId = aliyunService.drives.first(where: { $0.driveId == file.driveId }) {
                AliyunSubtitlePickerView(
                    drive: driveId,
                    mediaFile: file,
                    selectedSubtitle: $manualSelectedSubtitle
                )
            }
        }
        .alert("提示", isPresented: $showingErrorAlert) {
            Button("确定", role: .cancel) { }
        } message: {
            Text(errorMessage)
        }
        .onChange(of: manualSelectedSubtitle) { newValue in
            if let subtitle = newValue {
                selectedSubtitle = subtitle
                loadSelectedSubtitle()
            }
        }
    }
    
    // MARK: - 阿里云盘特定的状态视图
    
    private var aliyunStatusView: some View {
        VStack(spacing: 8) {
            if isPreparingAudio {
                HStack(spacing: 8) {
                    ProgressView()
                        .scaleEffect(0.8)
                    Text("正在准备音频...")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            
            // 字幕选择器
            HStack(spacing: 12) {
                // 自动检测的字幕
                if !availableSubtitles.isEmpty {
                    Menu {
                        Button {
                            selectedSubtitle = nil
                            playerService.updateSubtitles([])
                        } label: {
                            HStack {
                                Text("无字幕")
                                if selectedSubtitle == nil {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                        
                        ForEach(availableSubtitles) { subtitle in
                            Button {
                                selectedSubtitle = subtitle
                                loadSelectedSubtitle()
                            } label: {
                                HStack {
                                    Image(systemName: subtitle.format.icon)
                                    Text(subtitle.name)
                                    if selectedSubtitle?.fileId == subtitle.fileId {
                                        Image(systemName: "checkmark")
                                    }
                                }
                            }
                        }
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "captions.bubble")
                                .font(.caption)
                            Text(selectedSubtitle?.name ?? "自动检测")
                                .font(.caption)
                            Image(systemName: "chevron.down")
                                .font(.caption2)
                        }
                        .foregroundColor(.blue)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Color.blue.opacity(0.1))
                        .cornerRadius(8)
                    }
                }
                
                // 从网盘选择字幕按钮
                Button {
                    showingSubtitlePicker = true
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "folder.badge.plus")
                            .font(.caption)
                        Text("从网盘选择")
                            .font(.caption)
                    }
                    .foregroundColor(.green)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Color.green.opacity(0.1))
                    .cornerRadius(8)
                }
            }
        }
    }
    
    private var aliyunEmptyStateView: some View {
        VStack(spacing: 16) {
            if isLoadingSubtitles {
                VStack(spacing: 12) {
                    ProgressView()
                        .scaleEffect(1.2)
                    Text("正在加载字幕...")
                        .font(.body)
                        .foregroundColor(.secondary)
                }
            } else if availableSubtitles.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "captions.bubble")
                        .font(.system(size: 40))
                        .foregroundColor(.secondary)
                    
                    Text("未找到字幕文件")
                        .font(.headline)
                        .foregroundColor(.secondary)
                    
                    Text("请在同一目录下放置同名字幕文件")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
            } else if selectedSubtitle == nil {
                VStack(spacing: 12) {
                    Image(systemName: "captions.bubble")
                        .font(.system(size: 40))
                        .foregroundColor(.secondary)
                    
                    Text("请选择字幕")
                        .font(.headline)
                        .foregroundColor(.secondary)
                    
                    Text("点击上方按钮选择字幕文件")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            } else {
                VStack(spacing: 12) {
                    ProgressView()
                        .scaleEffect(1.2)
                    Text("正在加载字幕内容...")
                        .font(.body)
                        .foregroundColor(.secondary)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
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
                        errorMessage = "请先加载字幕再进行生词解析"
                        showingErrorAlert = true
                    }
                }
            ),
            FunctionButton(
                icon: "arrow.clockwise",
                title: "重新加载",
                isActive: false,
                isDisabled: selectedSubtitle == nil,
                action: {
                    if let subtitle = selectedSubtitle {
                        loadSelectedSubtitle()
                    }
                }
            ),
            FunctionButton(
                icon: "headphones.circle",
                title: "听力模式",
                isActive: false,
                isDisabled: playerService.currentSubtitles.isEmpty,
                isNavigationLink: true,
                navigationDestination: AnyView(ListeningModeView(playerService: playerService))
            ),
            FunctionButton(
                icon: showTranslation ? "character.bubble.fill" : "character.bubble",
                title: "中文翻译",
                isActive: showTranslation,
                isDisabled: isTranslating,
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
                        errorMessage = "请先加载字幕再使用翻译功能"
                        showingErrorAlert = true
                    }
                }
            )
        ]
    }
    
    // MARK: - 辅助方法
    
    @ViewBuilder
    private func destinationForShadowingPractice() -> some View {
        if !playerService.currentSubtitles.isEmpty,
           let audioURL = playerService.playbackState.currentEpisode?.audioURL {
            SubtitleShadowingPracticeView(
                mediaFile: file,
                subtitles: playerService.currentSubtitles,
                audioURL: audioURL,
                startIndex: playerService.playbackState.currentSubtitleIndex ?? 0
            )
        } else {
            EmptyView()
        }
    }
    
    private func prepareAudio() {
        print("☁️ [AliyunVideoPlayer] 准备音频播放: \(file.name)")
        
        let isSameFile = playerService.playbackState.currentEpisode?.id == file.fileId
        
        if !isSameFile {
            playerService.clearCurrentPlaybackState()
            print("☁️ [AliyunVideoPlayer] 切换到新文件，清空播放状态")
        } else {
            print("☁️ [AliyunVideoPlayer] 打开当前播放文件，保持播放状态")
            if playerService.audioPreparationState == .audioReady {
                print("☁️ [AliyunVideoPlayer] 音频已准备完成，无需重新处理")
                return
            }
        }
        
        // 加载字幕列表
        loadSubtitleList()
        
        // 准备音频
        Task {
            await prepareAudioPlayback()
        }
    }
    
    private func prepareAudioPlayback() async {
        await MainActor.run {
            isPreparingAudio = true
        }
        
        do {
            let url = try await aliyunService.getPlayURL(for: file)
            
            await MainActor.run {
                let mockEpisode = createMockEpisodeFromFile(audioURL: url)
                playerService.prepareEpisode(mockEpisode)
                isPreparingAudio = false
                
                print("☁️ [AliyunVideoPlayer] ✅ 音频准备完成")
            }
        } catch {
            await MainActor.run {
                isPreparingAudio = false
                errorMessage = "音频加载失败: \(error.localizedDescription)"
                showingErrorAlert = true
                print("☁️ [AliyunVideoPlayer] ❌ 音频加载失败: \(error)")
            }
        }
    }
    
    private func loadSubtitleList() {
        isLoadingSubtitles = true
        
        Task {
            do {
                let subtitles = try await aliyunService.findSubtitleFiles(for: file)
                
                await MainActor.run {
                    self.availableSubtitles = subtitles
                    isLoadingSubtitles = false
                    
                    // 自动选择优先级最高的字幕
                    if let firstSubtitle = subtitles.first {
                        selectedSubtitle = firstSubtitle
                        loadSelectedSubtitle()
                    }
                    
                    print("☁️ [AliyunVideoPlayer] 找到 \(subtitles.count) 个字幕文件")
                }
            } catch {
                await MainActor.run {
                    isLoadingSubtitles = false
                    print("☁️ [AliyunVideoPlayer] 加载字幕列表失败: \(error)")
                }
            }
        }
    }
    
    private func loadSelectedSubtitle() {
        guard let subtitle = selectedSubtitle else { return }
        
        Task {
            do {
                let subtitles = try await aliyunService.loadSubtitle(file: subtitle)
                
                await MainActor.run {
                    playerService.updateSubtitles(subtitles)
                    print("☁️ [AliyunVideoPlayer] ✅ 字幕加载成功: \(subtitles.count) 条")
                }
            } catch {
                await MainActor.run {
                    errorMessage = "字幕加载失败: \(error.localizedDescription)"
                    showingErrorAlert = true
                    print("☁️ [AliyunVideoPlayer] ❌ 字幕加载失败: \(error)")
                }
            }
        }
    }
    
    private func onDisappear() {
        print("☁️ [AliyunVideoPlayer] 页面消失，音频继续播放")
    }
    
    private func createMockEpisodeFromFile(audioURL: String) -> PodcastEpisode {
        return PodcastEpisode(
            id: file.fileId,
            title: file.name,
            description: file.contentDescription,
            audioURL: audioURL,
            duration: file.duration,
            publishDate: file.createdAt,
            subtitles: [],
            subtitleGenerationDate: nil,
            subtitleVersion: nil
        )
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
            print("☁️ [AliyunVideoPlayer] ✅ 字幕翻译完成")
        }
    }
    
    // MARK: - 第二页按钮
    
    private var shadowingPracticeButton: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 0), count: 5), spacing: 8) {
            NavigationLink(destination: destinationForShadowingPractice()) {
                VStack(spacing: 2) {
                    Image(systemName: "mic.badge.plus")
                        .font(.system(size: 22, weight: .medium))
                        .foregroundColor(playerService.currentSubtitles.isEmpty ? .secondary : .primary)
                        .frame(height: 24)
                    
                    Text("跟读练习")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(playerService.currentSubtitles.isEmpty ? .secondary : .primary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
                .frame(maxWidth: .infinity)
                .frame(height: 40)
            }
            .disabled(playerService.currentSubtitles.isEmpty)
        }
        .padding(.horizontal, 8)
    }
}
// MARK: - 预览
#Preview {
    NavigationView {
        AliyunVideoPlayerView(file: AliyunMediaFile.example)
    }
}
