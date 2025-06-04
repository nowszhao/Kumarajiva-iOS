import SwiftUI

// MARK: - 独立听力模式页面 - 保留所有原有功能
struct ListeningModeView: View {
    @ObservedObject var playerService: PodcastPlayerService
    @Environment(\.dismiss) private var dismiss
    
    @State private var showingFeedback = false
    @State private var feedbackText = ""
    @State private var feedbackIcon = ""
    @State private var isInteracting = false
    
    // MARK: - 生词标注相关状态
    @State private var showWordSelectionHint = false
    
    // MARK: - 性能优化缓存
    static let wordRegex = try! NSRegularExpression(pattern: #"[\w']+|[.!?;,]"#, options: [])
    static let textParsingRegex = try! NSRegularExpression(pattern: #"(\w+|[^\w\s]+|\s+)"#, options: [])
    
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
                    // 主要内容区域 - 按新的比例布局
                    mainContentView(geometry: geometry)
                    
                    // 底部安全区域
                    Color.clear
                        .frame(height: geometry.safeAreaInsets.bottom + 30)
                }
            }
            
            // 顶部状态栏
            topStatusBar
        }
        .navigationBarHidden(true)
        .animation(.spring(response: 0.8, dampingFraction: 0.9), value: playerService.playbackState.isPlaying)
        .onReceive(playerService.$playbackState) { state in
            handlePlaybackStateChange(state)
        }
    }
    
    // MARK: - 背景视图
    @ViewBuilder
    private var backgroundView: some View {
        ZStack {
            // 主背景 - 移除复杂渐变
            Color.black.opacity(0.95)
                .ignoresSafeArea()
            
            // 简化的背景效果 - 减少动画频率
            if playerService.playbackState.isPlaying {
                Circle()
                    .fill(
                        RadialGradient(
                            gradient: Gradient(colors: [
                                Color.accentColor.opacity(0.08),
                                Color.clear
                            ]),
                            center: .center,
                            startRadius: 0,
                            endRadius: 200
                        )
                    )
                    .scaleEffect(1.2)
                    .opacity(0.4)
                    .animation(.easeInOut(duration: 4.0).repeatForever(autoreverses: true), value: playerService.playbackState.isPlaying)
            }
        }
    }
    
    // MARK: - 主要内容区域
    @ViewBuilder
    private func mainContentView(geometry: GeometryProxy) -> some View {
        VStack(spacing: 0) {
            // 顶部间距，为状态栏留出空间
            Color.clear
                .frame(height: 80)
            
            // 上区域 - 前进5词 (15% 高度，缩小)
            forwardWordsSection(height: (geometry.size.height - 80) * 0.15)
            
            // 中区域 - 字幕显示 (35% 高度，增加)
            subtitleSection(height: (geometry.size.height - 80) * 0.35)
            
            // 下区域 - 后退5词 (50% 高度，保持)
            backwardWordsSection(height: (geometry.size.height - 80) * 0.50)
        }
    }
    
    // MARK: - 前进5词区域
    @ViewBuilder
    private func forwardWordsSection(height: CGFloat) -> some View {
        Spacer()
        Button {
            handleSeekForward()
        } label: {
            VStack(spacing: 12) {
                Spacer()
                
                ZStack {
                    // 背景圆形 - 缩小
                    Circle()
                        .fill(.ultraThinMaterial.opacity(0.3))
                        .frame(width: 60, height: 60)
                        .shadow(color: .black.opacity(0.3), radius: 12, x: 0, y: 6)
                    
                    // 图标 - 缩小
                    Image(systemName: "goforward.5")
                        .font(.system(size: 22, weight: .medium))
                        .foregroundStyle(.white)
                        .scaleEffect(canSeekForward ? 1.0 : 0.8)
                        .opacity(canSeekForward ? 1.0 : 0.4)
                }
                
                Text("+5词")
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.9))
                    .tracking(0.6)
                
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
                    subtitleDisplayView
                    
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
    
    // MARK: - 后退5词区域
    @ViewBuilder
    private func backwardWordsSection(height: CGFloat) -> some View {
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
                VStack(spacing: 8) {
                    // 根据播放状态决定显示交互式或只读字幕
                    if playerService.playbackState.isPlaying {
                        // 播放时：只读显示，但保持高亮
                        readOnlySubtitleView(currentSubtitle)
                    } else {
                        // 暂停时：可交互字幕
                        interactiveSubtitleView(currentSubtitle)
                    }
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
            
            // 标注提示和状态
            subtitleInteractionHint
        }
    }
    
    // MARK: - 只读字幕视图（播放时）
    @ViewBuilder
    private func readOnlySubtitleView(_ subtitle: Subtitle) -> some View {
        VStack(spacing: 4) {
            // 始终显示带实时高亮的文本 - 使用AttributedString
            Text(buildMarkedWordsAttributedString(subtitle.text))
                .font(.system(size: 16, weight: .medium, design: .rounded))
                .multilineTextAlignment(.center)
                .lineSpacing(3)
                .padding(.horizontal, 14)
                .shadow(color: .black.opacity(0.4), radius: 3, x: 0, y: 1)
        }
    }
    
    // MARK: - 可交互字幕视图（暂停时）
    @ViewBuilder
    private func interactiveSubtitleView(_ subtitle: Subtitle) -> some View {
        VStack(spacing: 8) {
            // 可交互的字幕文本 - 使用AttributedString点击
            InteractiveTextView(
                subtitle: subtitle,
                playerService: playerService,
                onWordTap: { word in
                    handleWordTap(word)
                }
            )
            .padding(.horizontal, 14)
            
            // 标注统计
            if playerService.markedWordCount > 0 {
                HStack(spacing: 4) {
                    Image(systemName: "bookmark.fill")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.yellow.opacity(0.8))
                    
                    Text("已标注 \(playerService.markedWordCount) 个单词")
                        .font(.system(size: 10, weight: .medium, design: .rounded))
                        .foregroundStyle(.white.opacity(0.6))
                }
            }
        }
    }
    
    // MARK: - 标注提示和状态
    @ViewBuilder
    private var subtitleInteractionHint: some View {
        if playerService.playbackState.isPlaying {
            Text("播放中，可点击暂停")
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .foregroundStyle(.white.opacity(0.5))
        } else {
            Text("暂停中，可点击继续播放")
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .foregroundStyle(.white.opacity(0.5))
        }
    }
    
    // MARK: - 顶部状态栏
    @ViewBuilder
    private var topStatusBar: some View {
        VStack {
            HStack {
                // 返回按钮
                Button {
                    dismiss()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 14, weight: .semibold))
                        Text("返回")
                            .font(.system(size: 14, weight: .medium))
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(
                        Capsule()
                            .fill(.ultraThinMaterial.opacity(0.6))
                            .shadow(color: .black.opacity(0.2), radius: 8, x: 0, y: 4)
                    )
                }
                
                Spacer()
                // 中间的听力模式状态信息
                statusInfoView
                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.top, 10)
            
            Spacer()
        }
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
        // 播放状态改变时的响应
    }
    
    private func getCurrentSubtitle() -> Subtitle? {
        guard let currentIndex = playerService.playbackState.currentSubtitleIndex,
              currentIndex >= 0 && currentIndex < playerService.currentSubtitles.count else {
            return nil
        }
        return playerService.currentSubtitles[currentIndex]
    }
    
    // MARK: - 生词标注辅助方法
    
    /// 解析文本为单词数组
    private func parseWordsFromText(_ text: String) -> [String] {
        // 使用缓存的正则表达式，避免重复编译
        let range = NSRange(location: 0, length: text.utf16.count)
        let matches = ListeningModeView.wordRegex.matches(in: text, options: [], range: range)
        
        return matches.compactMap { match -> String? in
            guard let range = Range(match.range, in: text) else { return nil }
            let word = String(text[range])
            
            // 过滤掉单独的标点符号
            if word.count == 1 && CharacterSet.punctuationCharacters.contains(word.unicodeScalars.first!) {
                return nil
            }
            
            return word
        }
    }
    
    /// 处理单词点击
    private func handleWordTap(_ word: String) {
        // 添加触觉反馈
        let impactFeedback = UIImpactFeedbackGenerator(style: .light)
        impactFeedback.impactOccurred()
        
        // 切换标注状态
        playerService.toggleMarkedWord(word)
        
        // 显示短暂的视觉反馈
        withAnimation(.easeInOut(duration: 0.2)) {
            showWordSelectionHint = true
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            withAnimation(.easeInOut(duration: 0.3)) {
                showWordSelectionHint = false
            }
        }
    }
    
    // MARK: - 构建标注单词的属性字符串
    /// 构建带标注高亮的属性字符串（用于只读模式）
    private func buildMarkedWordsAttributedString(_ text: String) -> AttributedString {
        var attributedString = AttributedString()
        
        // 使用缓存的正则表达式，避免重复编译
        let range = NSRange(location: 0, length: text.utf16.count)
        let matches = ListeningModeView.textParsingRegex.matches(in: text, options: [], range: range)
        
        for match in matches {
            guard let range = Range(match.range, in: text) else { continue }
            let textPart = String(text[range])
            
            var textString = AttributedString(textPart)
            
            // 检查是否为标注单词
            let cleanText = textPart.trimmingCharacters(in: .punctuationCharacters)
            let isMarkedWord = playerService.isWordMarked(cleanText)
            
            // 统一使用相同的字体重量，只改变颜色和背景
            let baseFont = Font.system(size: 16, weight: .medium, design: .rounded)
            
            if isMarkedWord && !cleanText.isEmpty && cleanText.rangeOfCharacter(from: .letters) != nil {
                // 标注单词：黄色背景高亮
                textString.foregroundColor = .black
                textString.font = baseFont
                textString.backgroundColor = .yellow.opacity(0.8)
            } else {
                // 普通文本：白色，无背景
                textString.foregroundColor = .white.opacity(0.9)
                textString.font = baseFont
            }
            
            attributedString.append(textString)
        }
        
        return attributedString
    }
} 
