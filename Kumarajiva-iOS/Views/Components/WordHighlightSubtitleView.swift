import SwiftUI

/// 支持单词高亮的字幕显示组件
struct WordHighlightSubtitleView: View {
    let subtitle: Subtitle
    let currentTime: TimeInterval
    let playedWordIndices: [Int]
    let currentPlayingWordIndex: Int?
    
    // 样式配置
    let fontSize: CGFloat
    let playedWordColor: Color
    let currentWordColor: Color
    let unplayedWordColor: Color
    let backgroundColor: Color
    let cornerRadius: CGFloat
    let padding: EdgeInsets
    
    init(subtitle: Subtitle,
         currentTime: TimeInterval,
         playedWordIndices: [Int] = [],
         currentPlayingWordIndex: Int? = nil,
         fontSize: CGFloat = 16,
         playedWordColor: Color = .secondary,
         currentWordColor: Color = .primary,
         unplayedWordColor: Color = .gray,
         backgroundColor: Color = Color.black.opacity(0.7),
         cornerRadius: CGFloat = 8,
         padding: EdgeInsets = EdgeInsets(top: 8, leading: 12, bottom: 8, trailing: 12)) {
        self.subtitle = subtitle
        self.currentTime = currentTime
        self.playedWordIndices = playedWordIndices
        self.currentPlayingWordIndex = currentPlayingWordIndex
        self.fontSize = fontSize
        self.playedWordColor = playedWordColor
        self.currentWordColor = currentWordColor
        self.unplayedWordColor = unplayedWordColor
        self.backgroundColor = backgroundColor
        self.cornerRadius = cornerRadius
        self.padding = padding
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            // 主字幕文本（单词高亮）
            wordHighlightText
            
            // 时间信息（可选）
            timeInfoView
        }
        .padding(padding)
        .background(backgroundColor)
        .cornerRadius(cornerRadius)
    }
    
    /// 单词高亮文本视图
    private var wordHighlightText: some View {
        Text(buildAttributedString())
            .font(.system(size: fontSize, weight: .medium))
            .lineLimit(nil)
            .multilineTextAlignment(.leading)
    }
    
    /// 构建带高亮的属性字符串
    private func buildAttributedString() -> AttributedString {
        var attributedString = AttributedString()
        
        for (index, word) in subtitle.words.enumerated() {
            var wordString = AttributedString(word.word)
            
            // 根据播放状态设置颜色
            if let currentIndex = currentPlayingWordIndex, currentIndex == index {
                // 当前正在播放的单词
                wordString.foregroundColor = currentWordColor
                wordString.font = .system(size: fontSize, weight: .bold)
                wordString.backgroundColor = currentWordColor.opacity(0.2)
            } else if playedWordIndices.contains(index) {
                // 已播放的单词
                wordString.foregroundColor = playedWordColor
                wordString.font = .system(size: fontSize, weight: .regular)
            } else {
                // 未播放的单词
                wordString.foregroundColor = unplayedWordColor
                wordString.font = .system(size: fontSize, weight: .light)
            }
            
            attributedString.append(wordString)
            
            // 添加空格（除了最后一个单词）
            if index < subtitle.words.count - 1 {
                attributedString.append(AttributedString(" "))
            }
        }
        
        return attributedString
    }
    
    /// 时间信息视图
    private var timeInfoView: some View {
        HStack {
            Text(formatTime(subtitle.startTime))
                .font(.caption2)
                .foregroundColor(.secondary)
            
            Spacer()
            
            if let confidence = subtitle.confidence {
                Text("置信度: \(Int(confidence * 100))%")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            
            Text(formatTime(subtitle.endTime))
                .font(.caption2)
                .foregroundColor(.secondary)
        }
    }
    
    /// 格式化时间显示
    private func formatTime(_ time: TimeInterval) -> String {
        let minutes = Int(time) / 60
        let seconds = Int(time) % 60
        let milliseconds = Int((time.truncatingRemainder(dividingBy: 1)) * 100)
        return String(format: "%d:%02d.%02d", minutes, seconds, milliseconds)
    }
}

/// 简化版本的单词高亮字幕视图
struct SimpleWordHighlightSubtitleView: View {
    let subtitle: Subtitle
    let currentTime: TimeInterval
    
    var body: some View {
        WordHighlightSubtitleView(
            subtitle: subtitle,
            currentTime: currentTime,
            playedWordIndices: subtitle.getWordsBeforeTime(currentTime),
            currentPlayingWordIndex: subtitle.getCurrentPlayingWordIndex(at: currentTime),
            fontSize: 18,
            playedWordColor: .white.opacity(0.6),
            currentWordColor: .yellow,
            unplayedWordColor: .white.opacity(0.4),
            backgroundColor: .black.opacity(0.8),
            cornerRadius: 12,
            padding: EdgeInsets(top: 12, leading: 16, bottom: 12, trailing: 16)
        )
    }
}

/// 字幕列表视图（支持单词高亮）
struct SubtitleListView: View {
    let subtitles: [Subtitle]
    let currentTime: TimeInterval
    let currentSubtitleIndex: Int?
    let onSubtitleTap: (Int) -> Void
    
    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 8) {
                    ForEach(Array(subtitles.enumerated()), id: \.element.id) { index, subtitle in
                        VStack(alignment: .leading, spacing: 4) {
                            // 字幕索引
                            HStack {
                                Text("#\(index + 1)")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 2)
                                    .background(Color.gray.opacity(0.2))
                                    .cornerRadius(4)
                                
                                Spacer()
                                
                                // 当前播放指示器
                                if currentSubtitleIndex == index {
                                    Image(systemName: "play.fill")
                                        .foregroundColor(.blue)
                                        .font(.caption)
                                }
                            }
                            
                            // 字幕内容（单词高亮）
                            if currentSubtitleIndex == index {
                                // 当前字幕显示单词高亮
                                SimpleWordHighlightSubtitleView(
                                    subtitle: subtitle,
                                    currentTime: currentTime
                                )
                            } else {
                                // 其他字幕显示普通文本
                                Text(subtitle.text)
                                    .font(.system(size: 16))
                                    .foregroundColor(currentSubtitleIndex == index ? .primary : .secondary)
                                    .padding()
                                    .background(
                                        RoundedRectangle(cornerRadius: 8)
                                            .fill(currentSubtitleIndex == index ? Color.blue.opacity(0.1) : Color.gray.opacity(0.1))
                                    )
                            }
                        }
                        .onTapGesture {
                            onSubtitleTap(index)
                        }
                        .id(index)
                    }
                }
                .padding()
            }
            .onChange(of: currentSubtitleIndex) { newIndex in
                if let index = newIndex {
                    withAnimation(.easeInOut(duration: 0.3)) {
                        proxy.scrollTo(index, anchor: .center)
                    }
                }
            }
        }
    }
}

// MARK: - 预览
struct WordHighlightSubtitleView_Previews: PreviewProvider {
    static var previews: some View {
        VStack(spacing: 20) {
            // 示例字幕
            let sampleWords = [
                SubtitleWord(word: "Hello", startTime: 0.0, endTime: 0.5),
                SubtitleWord(word: "world", startTime: 0.5, endTime: 1.0),
                SubtitleWord(word: "this", startTime: 1.0, endTime: 1.3),
                SubtitleWord(word: "is", startTime: 1.3, endTime: 1.5),
                SubtitleWord(word: "a", startTime: 1.5, endTime: 1.6),
                SubtitleWord(word: "test", startTime: 1.6, endTime: 2.0)
            ]
            
            let sampleSubtitle = Subtitle(
                startTime: 0.0,
                endTime: 2.0,
                text: "Hello world this is a test",
                words: sampleWords
            )
            
            // 不同播放状态的预览
            Group {
                WordHighlightSubtitleView(
                    subtitle: sampleSubtitle,
                    currentTime: 0.7,
                    playedWordIndices: [0],
                    currentPlayingWordIndex: 1
                )
                .previewDisplayName("播放中 - 第二个单词")
                
                SimpleWordHighlightSubtitleView(
                    subtitle: sampleSubtitle,
                    currentTime: 1.4
                )
                .previewDisplayName("简化版本")
            }
        }
        .padding()
        .background(Color.black)
        .previewLayout(.sizeThatFits)
    }
} 