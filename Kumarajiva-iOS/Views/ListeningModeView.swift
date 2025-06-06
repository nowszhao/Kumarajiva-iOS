import SwiftUI

// MARK: - 独立听力模式页面 - 保留所有原有功能
struct ListeningModeView: View {
    @ObservedObject var playerService: PodcastPlayerService
    @Environment(\.dismiss) private var dismiss
    
    @State private var showingFeedback = false
    @State private var feedbackText = ""
    @State private var feedbackIcon = ""
    @State private var isInteracting = false
    
    // MARK: - 精听模式相关状态
    @State private var isIntensiveMode = false
    @State private var previousLoopState = false // 保存进入精听前的循环状态
    
    // MARK: - 生词标注相关状态
    @State private var showWordSelectionHint = false
    
    // MARK: - 性能优化缓存
    static let wordRegex = try! NSRegularExpression(pattern: #"[\w']+|[.!?;,]"#, options: [])
    static let textParsingRegex = try! NSRegularExpression(pattern: #"(\w+|[^\w\s]+|\s+)"#, options: [])
    
    // MARK: - 计算属性
    private var canSeekBackward: Bool {
        guard playerService.playbackState.currentEpisode != nil else { return false }
        return isIntensiveMode ? playerService.hasNextSubtitle : hasWordsToSeekBackward()
    }
    
    private var canSeekForward: Bool {
        guard playerService.playbackState.currentEpisode != nil else { return false }
        return isIntensiveMode ? playerService.hasPreviousSubtitle : hasWordsToSeekForward()
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
            
            // 模式切换反馈提示
            if showingFeedback {
                modeChangeHintView
            }
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
            
            // 上区域 - 动态标题和功能 (15% 高度，缩小)
            topActionSection(height: (geometry.size.height - 80) * 0.15)
            
            // 中区域 - 字幕显示 (35% 高度，增加)
            subtitleSection(height: (geometry.size.height - 80) * 0.35)
            
            // 下区域 - 动态标题和功能 (50% 高度，保持)
            bottomActionSection(height: (geometry.size.height - 80) * 0.50)
        }
    }
    
    // MARK: - 上区域（动态功能）
    @ViewBuilder
    private func topActionSection(height: CGFloat) -> some View {
        Spacer()
        Button {
            if isIntensiveMode {
                handlePreviousSubtitle()
            } else {
                handleSeekForward()
            }
        } label: {
            VStack(spacing: 12) {
                Spacer()
                
                ZStack {
                    // 背景圆形 - 缩小
                    Circle()
                        .fill(.ultraThinMaterial.opacity(0.3))
                        .frame(width: 60, height: 60)
                        .shadow(color: .black.opacity(0.3), radius: 12, x: 0, y: 6)
                    
                    // 动态图标
                    Image(systemName: isIntensiveMode ? "backward.end.fill" : "goforward.5")
                        .font(.system(size: 22, weight: .medium))
                        .foregroundStyle(.white)
                        .scaleEffect(canSeekForward ? 1.0 : 0.8)
                        .opacity(canSeekForward ? 1.0 : 0.4)
                }
                
                Text(isIntensiveMode ? "上一句" : "+5词")
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
    
    // MARK: - 下区域（动态功能）
    @ViewBuilder
    private func bottomActionSection(height: CGFloat) -> some View {
        Button {
            if isIntensiveMode {
                handleNextSubtitle()
            } else {
                handleSeekBackward()
            }
        } label: {
            VStack(spacing: 24) {
                Spacer()
                
                ZStack {
                    // 背景圆形
                    Circle()
                        .fill(.ultraThinMaterial.opacity(0.3))
                        .frame(width: 120, height: 120)
                        .shadow(color: .black.opacity(0.3), radius: 20, x: 0, y: 10)
                    
                    // 动态图标
                    Image(systemName: isIntensiveMode ? "forward.end.fill" : "gobackward.5")
                        .font(.system(size: 42, weight: .medium))
                        .foregroundStyle(.white)
                        .scaleEffect(canSeekBackward ? 1.0 : 0.8)
                        .opacity(canSeekBackward ? 1.0 : 0.4)
                }
                
                Text(isIntensiveMode ? "下一句" : "-5词")
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
            Text(isIntensiveMode ? "精听模式：播放中，可点击暂停" : "播放中，可点击暂停")
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .foregroundStyle(.white.opacity(0.5))
        } else {
            if isIntensiveMode {
                Text("精听模式：暂停中，可标注单词后继续播放")
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(0.5))
            } else {
                Text("暂停中，可标注单词，点击空白处继续播放")
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(0.5))
            }
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
                
                // 精听模式开关
                intensiveModeToggle
            }
            .overlay {
                // 中间的听力模式状态信息 - 使用overlay确保真正居中
                statusInfoView
            }
            .padding(.horizontal, 20)
            .padding(.top, 10)
            
            Spacer()
        }
    }
    
    // MARK: - 精听模式开关
    @ViewBuilder
    private var intensiveModeToggle: some View {
        Button {
            toggleIntensiveMode()
        } label: {
            HStack(spacing: 6) {
                Image(systemName: isIntensiveMode ? "repeat.circle.fill" : "repeat.circle")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(isIntensiveMode ? .yellow : .white)
                
                Text("精听")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(isIntensiveMode ? .yellow : .white)
                
                // 小圆点指示器
                Circle()
                    .fill(isIntensiveMode ? .yellow : .white.opacity(0.5))
                    .frame(width: 6, height: 6)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(
                Capsule()
                    .fill(.ultraThinMaterial.opacity(0.6))
                    .overlay(
                        Capsule()
                            .stroke(isIntensiveMode ? .yellow.opacity(0.6) : .clear, lineWidth: 1)
                    )
                    .shadow(color: .black.opacity(0.2), radius: 8, x: 0, y: 4)
            )
        }
        .animation(.easeInOut(duration: 0.3), value: isIntensiveMode)
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
                
                Text(isIntensiveMode ? "精听模式" : "听力模式")
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)
                
                // 循环指示器（精听模式下显示）
                if isIntensiveMode && playerService.playbackState.isLooping {
                    Image(systemName: "repeat")
                        .font(.system(size: 8, weight: .medium))
                        .foregroundStyle(.yellow)
                }
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
    
    // MARK: - 模式切换反馈提示
    @ViewBuilder
    private var modeChangeHintView: some View {
        VStack {
            Spacer()
            
            HStack(spacing: 12) {
                Image(systemName: feedbackIcon)
                    .font(.system(size: 20, weight: .medium))
                    .foregroundStyle(.white)
                
                Text(feedbackText)
                    .font(.system(size: 16, weight: .medium, design: .rounded))
                    .foregroundStyle(.white)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .background(
                Capsule()
                    .fill(.ultraThinMaterial.opacity(0.8))
                    .shadow(color: .black.opacity(0.3), radius: 16, x: 0, y: 8)
            )
            .transition(.asymmetric(
                insertion: .scale.combined(with: .opacity),
                removal: .scale.combined(with: .opacity)
            ))
            
            Spacer()
        }
    }
    
    // MARK: - 方法
    
    private func toggleIntensiveMode() {
        withAnimation(.easeInOut(duration: 0.3)) {
            if isIntensiveMode {
                // 退出精听模式
                isIntensiveMode = false
                // 恢复之前的循环状态
                if !previousLoopState {
                    playerService.toggleLoop()
                }
            } else {
                // 进入精听模式
                isIntensiveMode = true
                // 保存当前循环状态
                previousLoopState = playerService.playbackState.isLooping
                // 如果当前没有开启循环，则开启
                if !playerService.playbackState.isLooping {
                    playerService.toggleLoop()
                }
            }
        }
        
        // 添加触觉反馈
        let impactFeedback = UIImpactFeedbackGenerator(style: .medium)
        impactFeedback.impactOccurred()
        
        // 显示模式切换提示
        showModeChangeHint()
    }
    
    private func showModeChangeHint() {
        withAnimation(.easeInOut(duration: 0.2)) {
            feedbackText = isIntensiveMode ? "已开启精听模式" : "已关闭精听模式"
            feedbackIcon = isIntensiveMode ? "repeat.circle.fill" : "waveform"
            showingFeedback = true
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            withAnimation(.easeInOut(duration: 0.3)) {
                showingFeedback = false
            }
        }
    }
    
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
        
        // 添加触觉反馈
        let impactFeedback = UIImpactFeedbackGenerator(style: .light)
        impactFeedback.impactOccurred()
    }
    
    private func handleNextSubtitle() {
        guard playerService.hasNextSubtitle else { return }
        
        playerService.nextSubtitle()
        
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

// MARK: - 精听模式功能测试
extension ListeningModeView {
    /// 测试精听模式的基本功能
    private func testIntensiveModeLogic() {
        print("🎯 [精听模式测试] 开始测试精听模式功能")
        
        // 测试模式切换
        print("🎯 [精听模式测试] 当前精听状态: \(isIntensiveMode)")
        print("🎯 [精听模式测试] 前进按钮启用: \(canSeekForward)")
        print("🎯 [精听模式测试] 后退按钮启用: \(canSeekBackward)")
        
        if isIntensiveMode {
            print("🎯 [精听模式测试] ✅ 精听模式已激活")
            print("🎯 [精听模式测试] - 前进5词 → 上一句 功能")
            print("🎯 [精听模式测试] - 后退5词 → 下一句 功能")
            print("🎯 [精听模式测试] - 循环播放状态: \(playerService.playbackState.isLooping)")
        } else {
            print("🎯 [精听模式测试] ⚪ 普通听力模式")
            print("🎯 [精听模式测试] - 前进5词 → +5词 功能")
            print("🎯 [精听模式测试] - 后退5词 → -5词 功能")
        }
        
        print("🎯 [精听模式测试] 测试完成")
    }
} 
