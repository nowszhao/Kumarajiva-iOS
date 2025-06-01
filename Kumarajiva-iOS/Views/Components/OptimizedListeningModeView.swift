import SwiftUI

// MARK: - 优化听力模式浮层
struct OptimizedListeningModeView: View {
    @Binding var isPresented: Bool
    @ObservedObject var playerService: PodcastPlayerService
    
    @State private var showingFeedback = false
    @State private var feedbackText = ""
    @State private var feedbackIcon = ""
    @State private var dragOffset: CGSize = .zero
    @State private var isInteracting = false
    
    // MARK: - 计算属性
    private var canSeekBackward: Bool {
        guard playerService.playbackState.currentEpisode != nil else { return false }
        return hasWordsToSeekBackward()
    }
    
    private var canSeekForward: Bool {
        guard playerService.playbackState.currentEpisode != nil else { return false }
        return hasWordsToSeekForward()
    }
    
    // 检查是否有足够的单词可以向后跳转
    private func hasWordsToSeekBackward() -> Bool {
        let currentTime = playerService.playbackState.currentTime
        
        // 收集所有单词
        var allWords: [SubtitleWord] = []
        for subtitle in playerService.currentSubtitles {
            allWords.append(contentsOf: subtitle.words)
        }
        
        // 按时间排序
        allWords.sort { $0.startTime < $1.startTime }
        
        // 找到当前单词索引
        for (index, word) in allWords.enumerated() {
            if currentTime >= word.startTime && currentTime <= word.endTime {
                return index >= 5 // 需要至少5个单词可以向后跳转
            }
        }
        
        // 如果没有找到当前单词，检查是否有任何单词
        return !allWords.isEmpty
    }
    
    // 检查是否有足够的单词可以向前跳转
    private func hasWordsToSeekForward() -> Bool {
        let currentTime = playerService.playbackState.currentTime
        
        // 收集所有单词
        var allWords: [SubtitleWord] = []
        for subtitle in playerService.currentSubtitles {
            allWords.append(contentsOf: subtitle.words)
        }
        
        // 按时间排序
        allWords.sort { $0.startTime < $1.startTime }
        
        // 找到当前单词索引
        for (index, word) in allWords.enumerated() {
            if currentTime >= word.startTime && currentTime <= word.endTime {
                return index < allWords.count - 5 // 需要至少还有5个单词可以向前跳转
            }
        }
        
        // 如果没有找到当前单词，检查是否还有单词
        return !allWords.isEmpty
    }
    
    var body: some View {
        ZStack {
            // 背景渐变
            backgroundView
            
            GeometryReader { geometry in
                VStack(spacing: 0) {
//                    // 顶部安全区域
//                    Color.clear
//                        .frame(height: geometry.safeAreaInsets.top + 10)
                    
                    // 主要内容区域 - 按新的比例布局
                    mainContentView(geometry: geometry)
                    
                    // 底部安全区域
                    Color.clear
                        .frame(height: geometry.safeAreaInsets.bottom + 30)
                }
            }
            
            // 顶部状态栏
            topStatusBar
            
            // 顶部小提示反馈
//            if showingFeedback {
//                topFeedbackView
//            }
        }
        .animation(.spring(response: 0.5, dampingFraction: 0.8), value: playerService.playbackState.isPlaying)
        .onReceive(playerService.$playbackState) { state in
            handlePlaybackStateChange(state)
        }
    }
    
    // MARK: - 背景视图
    @ViewBuilder
    private var backgroundView: some View {
        ZStack {
            // 主背景
            LinearGradient(
                gradient: Gradient(colors: [
                    Color.black.opacity(0.95),
                    Color.black.opacity(0.90),
                    Color.black.opacity(0.95)
                ]),
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()
            
            // 动态背景效果
            if playerService.playbackState.isPlaying {
                Circle()
                    .fill(
                        RadialGradient(
                            gradient: Gradient(colors: [
                                Color.accentColor.opacity(0.15),
                                Color.accentColor.opacity(0.05),
                                Color.clear
                            ]),
                            center: .center,
                            startRadius: 0,
                            endRadius: 300
                        )
                    )
                    .scaleEffect(1.5)
                    .opacity(0.6)
                    .animation(.easeInOut(duration: 2.0).repeatForever(autoreverses: true), value: playerService.playbackState.isPlaying)
            }
        }
    }
    
    // MARK: - 主要内容区域
    @ViewBuilder
    private func mainContentView(geometry: GeometryProxy) -> some View {
        VStack(spacing: 0) {
            // 上区域 - 上一句 (25% 高度)
            previousSentenceSection(height: geometry.size.height * 0.25)
            
            // 中区域 - 字幕显示 (25% 高度)
            subtitleSection(height: geometry.size.height * 0.25)
            
            // 下区域 - 下一句 (50% 高度)
            nextSentenceSection(height: geometry.size.height * 0.50)
        }
    }
    
    // MARK: - 上一句区域
    @ViewBuilder
    private func previousSentenceSection(height: CGFloat) -> some View {
        Spacer()
        Button {
            handleSeekForward()
        } label: {
            VStack(spacing: 16) {
                Spacer()
                
                ZStack {
                    // 背景圆形
                    Circle()
                        .fill(.ultraThinMaterial.opacity(0.3))
                        .frame(width: 80, height: 80)
                        .shadow(color: .black.opacity(0.3), radius: 15, x: 0, y: 8)
                    
                    // 图标
                    Image(systemName: "goforward.5")
                        .font(.system(size: 28, weight: .medium))
                        .foregroundStyle(.white)
                        .scaleEffect(canSeekForward ? 1.0 : 0.8)
                        .opacity(canSeekForward ? 1.0 : 0.4)
                }
                
                Text("+5词")
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.9))
                    .tracking(0.8)
                
                Spacer()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(ListeningInteractionStyle())
        .disabled(!canSeekForward)
        .frame(height: height)
    }
    
    // MARK: - 字幕显示区域
    @ViewBuilder
    private func subtitleSection(height: CGFloat) -> some View {
        VStack(spacing: 0) {
            // 上分隔线
            dividerLine
            
            // 字幕内容 - 始终显示字幕
            Button {
                handleSubtitleToggle()
            } label: {
                VStack(spacing: 0) {
                    Spacer()
                    
                    // 根据播放状态决定显示内容
                    if !playerService.playbackState.isPlaying {
                        // 暂停时始终显示字幕
                        subtitleDisplayView
                    } else {
                        // 播放时显示简单的字幕内容
                        simpleSubtitleView
                    }
                    
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .contentShape(Rectangle())
            }
            .buttonStyle(ListeningInteractionStyle())
            
            // 下分隔线
            dividerLine
        }
        .frame(height: height)
    }
    
    // MARK: - 下一句区域
    @ViewBuilder
    private func nextSentenceSection(height: CGFloat) -> some View {
        Button {
            handleSeekBackward()
        } label: {
            VStack(spacing: 24) {
                Spacer()
                
                ZStack {
                    // 背景圆形
                    Circle()
                        .fill(.ultraThinMaterial.opacity(0.3))
                        .frame(width: 120, height: 120)
                        .shadow(color: .black.opacity(0.3), radius: 20, x: 0, y: 10)
                    
                    // 图标
                    Image(systemName: "gobackward.5")
                        .font(.system(size: 42, weight: .medium))
                        .foregroundStyle(.white)
                        .scaleEffect(canSeekBackward ? 1.0 : 0.8)
                        .opacity(canSeekBackward ? 1.0 : 0.4)
                }
                
                Text("-5词")
                    .font(.system(size: 20, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.9))
                    .tracking(1.2)
                
                Spacer()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(ListeningInteractionStyle())
        .disabled(!canSeekBackward)
        .frame(height: height)
    }
    
    // MARK: - 分隔线
    @ViewBuilder
    private var dividerLine: some View {
        HStack {
            Rectangle()
                .fill(
                    LinearGradient(
                        gradient: Gradient(colors: [
                            .clear,
                            .white.opacity(0.2),
                            .white.opacity(0.4),
                            .white.opacity(0.2),
                            .clear
                        ]),
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .frame(height: 1)
                .padding(.horizontal, 80)
        }
    }
    
    // MARK: - 字幕显示视图
    @ViewBuilder
    private var subtitleDisplayView: some View {
        VStack(spacing: 10) {
            // 字幕文本
            if let currentSubtitle = getCurrentSubtitle() {
                VStack(spacing: 4) {
                    // 主要文本
                    Text(currentSubtitle.text)
                        .font(.system(size: 16, weight: .medium, design: .rounded))
                        .foregroundStyle(.white.opacity(0.9))
                        .multilineTextAlignment(.center)
                        .lineSpacing(3)
                        .padding(.horizontal, 14)
                        .shadow(color: .black.opacity(0.4), radius: 3, x: 0, y: 1)
                }
            } else {
                VStack(spacing: 8) {
                    Image(systemName: "text.bubble")
                        .font(.system(size: 32, weight: .light))
                        .foregroundStyle(.white.opacity(0.6))
                    
                    Text("暂无字幕")
                        .font(.system(size: 16, weight: .medium, design: .rounded))
                        .foregroundStyle(.white.opacity(0.7))
                }
            }
            
            // 播放/暂停提示
            if !playerService.playbackState.isPlaying {
                HStack(spacing: 1) {
                    Image(systemName: "play.circle")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.white.opacity(0.5))
                    
                    Text("点击继续播放")
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundStyle(.white.opacity(0.5))
                }
            }
        }
    }
    
    // MARK: - 简单字幕视图（播放时）
    @ViewBuilder
    private var simpleSubtitleView: some View {
        VStack(spacing: 8) {
            Image(systemName: "text.bubble")
                .font(.system(size: 28, weight: .light))
                .foregroundStyle(.white.opacity(0.5))
            
            Text("播放中，可点击暂停查看字幕")
                .font(.system(size: 14, weight: .medium, design: .rounded))
                .foregroundStyle(.white.opacity(0.6))
        }
    }
    
    // MARK: - 顶部状态栏
    @ViewBuilder
    private var topStatusBar: some View {
        VStack {
            HStack {
                Spacer()
                // 中间的听力模式状态信息
                statusInfoView
                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.top, 10)
            
            Spacer()
        }
        Spacer()

    }
    
    // MARK: - 状态信息视图
    @ViewBuilder
    private var statusInfoView: some View {
        VStack(alignment: .center, spacing: 4) {
            // 听力模式标题
            HStack(spacing: 5) {
                Image(systemName: playerService.playbackState.isPlaying ? "waveform" : "headphones")
                    .font(.system(size: 8, weight: .medium))
                    .foregroundStyle(.white)
                    .symbolEffect(.variableColor.iterative, isActive: playerService.playbackState.isPlaying)
                
                Text("听力模式")
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(
                Capsule()
                    .fill(.ultraThinMaterial.opacity(0.6))
                    .shadow(color: .black.opacity(0.2), radius: 8, x: 0, y: 4)
            )
            
        }
    }
    
    // MARK: - 方法
    
    private func handleSeekBackward() {
        guard canSeekBackward else { return }
        
        playerService.seekBackwardWords(wordCount: 5)
        
        // 添加触觉反馈
        let impactFeedback = UIImpactFeedbackGenerator(style: .light)
        impactFeedback.impactOccurred()
    }
    
    private func handleSeekForward() {
        guard canSeekForward else { return }
        
        playerService.seekForwardWords(wordCount: 5)
        
        // 添加触觉反馈
        let impactFeedback = UIImpactFeedbackGenerator(style: .light)
        impactFeedback.impactOccurred()
    }
    
    private func handlePreviousSubtitle() {
        guard playerService.hasPreviousSubtitle else { return }
        
        playerService.previousSubtitle()
    }
    
    private func handleNextSubtitle() {
        guard playerService.hasNextSubtitle else { return }
        
        playerService.nextSubtitle()
    }
    
    private func handleSubtitleToggle() {
        if playerService.playbackState.isPlaying {
            // 暂停播放
            playerService.pausePlayback()
        } else {
            // 开始播放
            playerService.resumePlayback()
        }
    }
    
    private func handlePlaybackStateChange(_ state: PodcastPlaybackState) {
        // 播放状态改变时的响应 - 移除自动隐藏字幕逻辑
    }
    
    private func getCurrentSubtitle() -> Subtitle? {
        guard let currentIndex = playerService.playbackState.currentSubtitleIndex,
              currentIndex >= 0 && currentIndex < playerService.currentSubtitles.count else {
            return nil
        }
        return playerService.currentSubtitles[currentIndex]
    }
}

// MARK: - 听力模式交互样式
struct ListeningInteractionStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.96 : 1.0)
            .opacity(configuration.isPressed ? 0.85 : 1.0)
            .animation(.easeInOut(duration: 0.12), value: configuration.isPressed)
    }
}

// MARK: - 预览
#Preview {
    OptimizedListeningModeView(
        isPresented: .constant(true),
        playerService: PodcastPlayerService.shared
    )
}
