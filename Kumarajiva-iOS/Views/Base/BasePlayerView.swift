import SwiftUI

// MARK: - 基础播放器视图配置
struct PlayerViewConfiguration {
    let showYouTubeDownloadProgress: Bool
    let enableManualDownload: Bool
    let customStatusView: AnyView?
    let customEmptyStateView: AnyView?
    let onPrepare: () -> Void
    let onDisappear: () -> Void
    
    init(
        showYouTubeDownloadProgress: Bool = false,
        enableManualDownload: Bool = false,
        customStatusView: AnyView? = nil,
        customEmptyStateView: AnyView? = nil,
        onPrepare: @escaping () -> Void = {},
        onDisappear: @escaping () -> Void = {}
    ) {
        self.showYouTubeDownloadProgress = showYouTubeDownloadProgress
        self.enableManualDownload = enableManualDownload
        self.customStatusView = customStatusView
        self.customEmptyStateView = customEmptyStateView
        self.onPrepare = onPrepare
        self.onDisappear = onDisappear
    }
}

// MARK: - 基础播放器视图
/// 泛型播放器视图，支持播客和YouTube视频
struct BasePlayerView<Content: PlayableContent, SubtitleRow: View>: View {
    let content: Content
    let configuration: PlayerViewConfiguration
    let subtitleRowBuilder: (Subtitle, Bool, TimeInterval, Bool, @escaping () -> Void) -> SubtitleRow
    let functionButtons: [FunctionButton]
    let secondPageButtons: AnyView?
    
    @StateObject private var playerService = PodcastPlayerService.shared
    @StateObject private var taskManager = SubtitleGenerationTaskManager.shared
    @Environment(\.dismiss) private var dismiss
    
    // 状态变量
    @State private var showingErrorAlert = false
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
        .toolbar(.hidden, for: .tabBar)
        .onAppear {
            configuration.onPrepare()
        }
        .onDisappear {
            configuration.onDisappear()
            
            // 清理计时器
            seekDebounceTimer?.invalidate()
            seekDebounceTimer = nil
        }
        .onReceive(playerService.$errorMessage) { errorMessage in
            if let error = errorMessage {
                errorAlertMessage = error
                showingErrorAlert = true
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
            // 内容信息
            VStack(spacing: 8) {
                Text(formatDate(content.publishDate))
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                // 音频状态指示器
                AudioStatusIndicator(playerService: playerService)
                
                // 自定义状态视图（由子类提供）
                if let customStatus = configuration.customStatusView {
                    customStatus
                }
            }
            .padding(.horizontal)
            
            Divider()
            
            // 字幕内容
            if playerService.currentSubtitles.isEmpty {
                if let customView = configuration.customEmptyStateView {
                    customView
                } else {
                    defaultEmptySubtitleView
                }
            } else {
                ScrollView {
                    PlayerSubtitleListView(
                        playerService: playerService,
                        subtitles: playerService.currentSubtitles
                    ) { subtitle, index, isActive in
                        subtitleRowBuilder(
                            subtitle,
                            isActive,
                            playerService.playbackState.currentTime,
                            showTranslation
                        ) {
                            playerService.seek(to: subtitle.startTime)
                        }
                    }
                }
                .background(Color(.systemBackground))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemGroupedBackground))
    }
    
    // MARK: - 默认空字幕视图
    
    private var defaultEmptySubtitleView: some View {
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
                    
                    Text(playerService.subtitleGenerationStatusText)
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
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    // MARK: - 播放控制面板
    
    private var playbackControlView: some View {
        VStack(spacing: 0) {
            // 进度条
            PlayerProgressView(
                playerService: playerService,
                isSeeking: $isSeeking,
                seekDebounceTimer: $seekDebounceTimer,
                isAudioReady: isAudioReady
            )
            .padding(.bottom, 12)
            
            // 主要播放控制按钮
            PlayerMainControls(
                playerService: playerService,
                isAudioReady: isAudioReady,
                showingConfigPanel: $showingConfigPanel
            )
            
            // 功能按钮区域（可展开/收起）
            if showingConfigPanel {
                let _ = print("⚙️ [BasePlayerView] 控制面板已展开 - showingConfigPanel: true")
                
                Divider()
                    .padding(.horizontal, 20)
                    .padding(.vertical, 8)
                
                functionButtonsView
                    .transition(.asymmetric(
                        insertion: .push(from: .bottom).combined(with: .opacity),
                        removal: .push(from: .top).combined(with: .opacity)
                    ))
            } else {
                let _ = print("⚙️ [BasePlayerView] 控制面板已收起 - showingConfigPanel: false")
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Color(.systemBackground))
        .shadow(color: .black.opacity(0.05), radius: 8, x: 0, y: -3)
    }
    
    // MARK: - 功能按钮区域
    
    @ViewBuilder
    private var functionButtonsView: some View {
        if let secondPage = secondPageButtons {
            // 有第二页：使用 TabView
            let _ = print("🔵 [BasePlayerView] TabView 渲染 - secondPageButtons 存在")
            TabView {
                // 第一页：功能按钮
                FunctionButtonGrid(buttons: functionButtons)
                    .onAppear {
                        print("🟢 [BasePlayerView] 第一页（功能按钮）已显示")
                    }
                
                // 第二页：额外按钮
                secondPage
                    .onAppear {
                        print("🟢 [BasePlayerView] 第二页（额外按钮）已显示")
                    }
            }
            .tabViewStyle(.page(indexDisplayMode: .automatic))
            .frame(height: 80)
            .padding(.horizontal, 20)
            .onAppear {
                print("🟡 [BasePlayerView] TabView 已显示")
            }
        } else {
            // 没有第二页：直接显示功能按钮
            let _ = print("🔴 [BasePlayerView] 无第二页 - secondPageButtons 为 nil")
            FunctionButtonGrid(buttons: functionButtons)
                .frame(height: 80)
                .padding(.horizontal, 20)
        }
    }
    
    // MARK: - 计算属性
    
    private var isAudioReady: Bool {
        return playerService.audioPreparationState == .audioReady
    }
    
    // MARK: - 辅助方法
    
    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        return formatter.string(from: date)
    }
}

// MARK: - 通用功能按钮构建器
extension BasePlayerView {
    /// 创建循环播放按钮
    static func makeLoopButton(
        isLooping: Bool,
        action: @escaping () -> Void
    ) -> FunctionButton {
        FunctionButton(
            icon: isLooping ? "repeat.circle.fill" : "repeat.circle",
            title: "循环",
            isActive: isLooping,
            action: action
        )
    }
    
    /// 创建生词解析按钮
    static func makeVocabularyButton(
        isEnabled: Bool,
        action: @escaping () -> Void
    ) -> FunctionButton {
        FunctionButton(
            icon: "book.circle",
            title: "生词",
            isActive: isEnabled,
            action: action
        )
    }
    
    /// 创建听力模式按钮
    static func makeListeningModeButton(
        isEnabled: Bool,
        action: @escaping () -> Void
    ) -> FunctionButton {
        FunctionButton(
            icon: isEnabled ? "ear.fill" : "ear",
            title: "听力",
            isActive: isEnabled,
            action: action
        )
    }
    
    /// 创建中文翻译按钮
    static func makeTranslationButton(
        showTranslation: Bool,
        isTranslating: Bool,
        action: @escaping () -> Void
    ) -> FunctionButton {
        FunctionButton(
            icon: isTranslating ? "hourglass" : (showTranslation ? "character.book.closed.fill" : "character.book.closed"),
            title: "翻译",
            isActive: showTranslation,
            action: action
        )
    }
}

// MARK: - 通用翻译功能
extension BasePlayerView {
    /// 翻译字幕（通用方法）
    static func translateSubtitles(
        subtitles: [Subtitle],
        isTranslating: Binding<Bool>,
        showTranslation: Binding<Bool>,
        onComplete: @escaping ([Subtitle]) -> Void
    ) {
        guard !isTranslating.wrappedValue else { return }
        guard !subtitles.isEmpty else { return }
        
        Task {
            await MainActor.run {
                isTranslating.wrappedValue = true
            }
            
            // 使用 TaskGroup 并发翻译所有字幕
            await withTaskGroup(of: (Int, String?).self) { group in
                for (index, subtitle) in subtitles.enumerated() {
                    // 跳过已翻译的字幕
                    if subtitle.translatedText != nil {
                        continue
                    }
                    
                    group.addTask {
                        let translatedText = await EdgeTTSService.shared.translate(text: subtitle.text, to: "zh-CN")
                        return (index, translatedText)
                    }
                }
                
                var updatedSubtitles = subtitles
                for await (index, translatedText) in group {
                    if let translatedText = translatedText {
                        updatedSubtitles[index].translatedText = translatedText
                    }
                }
                
                await MainActor.run {
                    onComplete(updatedSubtitles)
                    showTranslation.wrappedValue = true
                    isTranslating.wrappedValue = false
                    print("✅ [BasePlayerView] 字幕翻译完成")
                }
            }
        }
    }
}
