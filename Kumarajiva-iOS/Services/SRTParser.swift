import Foundation

/// 字幕解析器 - 支持SRT和VTT格式
class SubtitleParser {
    
    /// 从URL解析字幕文件（自动识别格式）
    static func parseFromURL(_ urlString: String) async throws -> [Subtitle] {
        guard let url = URL(string: urlString) else {
            throw SubtitleParserError.invalidURL
        }
        
        // 下载字幕文件
        print("📝 [SubtitleParser] 开始下载字幕文件: \(urlString)")
        let (data, _) = try await URLSession.shared.data(from: url)
        
        guard !data.isEmpty else {
            throw SubtitleParserError.emptyFile
        }
        
        print("📝 [SubtitleParser] 字幕文件下载成功，大小: \(data.count) bytes")
        
        // 转换为字符串
        guard let content = String(data: data, encoding: .utf8) else {
            throw SubtitleParserError.invalidEncoding
        }
        
        // 自动识别格式并解析
        return try parseSubtitleContent(content)
    }
    
    /// 从字符串内容解析字幕（自动识别格式）
    static func parseSubtitleContent(_ content: String) throws -> [Subtitle] {
        let trimmedContent = content.trimmingCharacters(in: .whitespacesAndNewlines)
        
        if trimmedContent.hasPrefix("WEBVTT") {
            print("📝 [SubtitleParser] 检测到VTT格式")
            return try parseVTT(content: trimmedContent)
        } else {
            print("📝 [SubtitleParser] 检测到SRT格式")
            return try parseSRT(content: trimmedContent)
        }
    }
    
    // MARK: - VTT格式解析
    
    /// 解析VTT格式字幕 - 重写版本，根据是否包含<c>标签采用不同策略
    static func parseVTT(content: String) throws -> [Subtitle] {
        let lines = content.components(separatedBy: .newlines)
        
        // 跳过VTT头部
        var i = 0
        while i < lines.count && !lines[i].contains("-->") {
            i += 1
        }
        
        print("📝 [VTT Parser] 开始解析VTT字幕...")
        
        // 预分析：检查文件是否包含<c>标签
        let hasWordLevelTimestamps = content.contains("<c>") && content.contains("</c>")
        
        if hasWordLevelTimestamps {
            print("📝 [VTT Parser] 检测到<c>标签，使用单词时间戳策略")
            return parseVTTWithWordTimestamps(lines: lines, startIndex: i)
        } else {
            print("📝 [VTT Parser] 未检测到<c>标签，使用标准VTT策略")
            return parseStandardVTT(lines: lines, startIndex: i)
        }
    }
    
    /// 策略1：解析带单词时间戳的VTT文件（包含<c>标签）
    static func parseVTTWithWordTimestamps(lines: [String], startIndex: Int) -> [Subtitle] {
        var subtitles: [Subtitle] = []
        var i = startIndex
        
        print("📝 [VTT Word] 开始解析带单词时间戳的VTT...")
        
        while i < lines.count {
            let line = lines[i].trimmingCharacters(in: .whitespaces)
            
            // 查找时间戳行
            if line.contains("-->") {
                let timeParts = line.components(separatedBy: "-->")
                guard timeParts.count >= 2 else {
                    i += 1
                    continue
                }
                
                let startTimeStr = timeParts[0].trimmingCharacters(in: .whitespaces)
                let endTimeStr = timeParts[1].trimmingCharacters(in: .whitespaces)
                    .components(separatedBy: " ")[0] // 去掉align等属性
                
                guard let segmentStartTime = parseVTTTimestamp(startTimeStr),
                      let segmentEndTime = parseVTTTimestamp(endTimeStr) else {
                    print("⚠️ [VTT Word] 无法解析时间戳: \(line)")
                    i += 1
                    continue
                }
                
                // 收集这个时间段的所有文本行
                i += 1
                var textLines: [String] = []
                
                while i < lines.count {
                    let textLine = lines[i].trimmingCharacters(in: .whitespaces)
                    
                    if textLine.isEmpty {
                        break
                    }
                    
                    if textLine.contains("-->") {
                        i -= 1 // 回退一行，让外层循环处理
                        break
                    }
                    
                    textLines.append(textLine)
                    i += 1
                }
                
                // 只处理包含<c>标签的行
                let cTagLines = textLines.filter { $0.contains("<c>") && $0.contains("</c>") }
                
                if !cTagLines.isEmpty {
                    // 处理第一个包含<c>标签的行（通常每个时间段只有一个这样的行）
                    if let cTagLine = cTagLines.first {
                        if let subtitle = parseLineWithCTags(cTagLine, segmentStartTime: segmentStartTime, segmentEndTime: segmentEndTime) {
                            subtitles.append(subtitle)
                            print("✅ [VTT Word] 添加字幕: '\(String(subtitle.text.prefix(30)))...' [\(formatTime(segmentStartTime)) -> \(formatTime(segmentEndTime))] (\(subtitle.words.count) words)")
                        }
                    }
                } else {
                    print("🚫 [VTT Word] 跳过无<c>标签时间段: \(formatTime(segmentStartTime)) -> \(formatTime(segmentEndTime))")
                }
            }
            
            i += 1
        }
        
        print("📝 [VTT Word] 解析完成: \(subtitles.count) 个字幕段落")
        return subtitles
    }
    
    /// 策略2：解析标准VTT文件（无<c>标签）
    static func parseStandardVTT(lines: [String], startIndex: Int) -> [Subtitle] {
        var subtitles: [Subtitle] = []
        var i = startIndex
        
        print("📝 [VTT Standard] 开始解析标准VTT...")
        
        while i < lines.count {
            let line = lines[i].trimmingCharacters(in: .whitespaces)
            
            // 查找时间戳行
            if line.contains("-->") {
                let timeParts = line.components(separatedBy: "-->")
                guard timeParts.count >= 2 else {
                    i += 1
                    continue
                }
                
                let startTimeStr = timeParts[0].trimmingCharacters(in: .whitespaces)
                let endTimeStr = timeParts[1].trimmingCharacters(in: .whitespaces)
                    .components(separatedBy: " ")[0] // 去掉align等属性
                
                guard let segmentStartTime = parseVTTTimestamp(startTimeStr),
                      let segmentEndTime = parseVTTTimestamp(endTimeStr) else {
                    print("⚠️ [VTT Standard] 无法解析时间戳: \(line)")
                    i += 1
                    continue
                }
                
                // 收集这个时间段的所有文本行
                i += 1
                var textLines: [String] = []
                
                while i < lines.count {
                    let textLine = lines[i].trimmingCharacters(in: .whitespaces)
                    
                    if textLine.isEmpty {
                        break
                    }
                    
                    if textLine.contains("-->") {
                        i -= 1 // 回退一行，让外层循环处理
                        break
                    }
                    
                    textLines.append(textLine)
                    i += 1
                }
                
                // 合并所有文本行
                if !textLines.isEmpty {
                    let fullText = textLines.joined(separator: " ")
                    let cleanText = cleanVTTText(fullText)
                    
                    if !cleanText.isEmpty && cleanText.count > 2 {
                        // 估算单词时间戳
                        let words = estimateWordTimings(for: cleanText, startTime: segmentStartTime, endTime: segmentEndTime)
                        
                        let subtitle = Subtitle(
                            startTime: segmentStartTime,
                            endTime: segmentEndTime,
                            text: cleanText,
                            confidence: nil,
                            words: words,
                            language: "en"
                        )
                        
                        subtitles.append(subtitle)
                        print("✅ [VTT Standard] 添加字幕: '\(String(cleanText.prefix(30)))...' [\(formatTime(segmentStartTime)) -> \(formatTime(segmentEndTime))] (\(words.count) words)")
                    }
                }
            }
            
            i += 1
        }
        
        print("📝 [VTT Standard] 解析完成: \(subtitles.count) 个字幕段落")
        return subtitles
    }
    
    /// 解析包含<c>标签的单行文本
    static func parseLineWithCTags(_ line: String, segmentStartTime: TimeInterval, segmentEndTime: TimeInterval) -> Subtitle? {
        var words: [SubtitleWord] = []
        var cleanTextParts: [String] = []
        
        // 第一步：提取<c>标签前的文本
        if let firstCTagRange = line.range(of: #"<\d{2}:\d{2}:\d{2}\.\d{3}><c>"#, options: .regularExpression) {
            let beforeCTags = String(line[..<firstCTagRange.lowerBound])
            let beforeWords = beforeCTags.components(separatedBy: .whitespaces)
                .map { cleanVTTText($0) }
                .filter { !$0.isEmpty }
            
            if !beforeWords.isEmpty {
                let wordDuration = min(0.3, (segmentEndTime - segmentStartTime) / Double(beforeWords.count + 5)) // 假设后面还有5个<c>单词
                
                for (index, word) in beforeWords.enumerated() {
                    let wordStartTime = segmentStartTime + Double(index) * wordDuration
                    let wordEndTime = wordStartTime + wordDuration
                    
                    let subtitleWord = SubtitleWord(
                        word: word,
                        startTime: wordStartTime,
                        endTime: wordEndTime,
                        confidence: 0.8
                    )
                    
                    words.append(subtitleWord)
                    cleanTextParts.append(word)
                }
                
                print("📝 [VTT CTag] 添加前置单词: \(beforeWords.joined(separator: " "))")
            }
        }
        
        // 第二步：提取所有<时间戳><c>单词</c>组合
        let cTagPattern = #"<(\d{2}:\d{2}:\d{2}\.\d{3})><c>\s*([^<]+?)\s*</c>"#
        let cTagRegex = try? NSRegularExpression(pattern: cTagPattern, options: [])
        let lineRange = NSRange(location: 0, length: line.count)
        
        if let regex = cTagRegex {
            let matches = regex.matches(in: line, options: [], range: lineRange)
            
            for match in matches {
                if match.numberOfRanges >= 3 {
                    let timestampRange = match.range(at: 1)
                    if let timestampRange = Range(timestampRange, in: line) {
                        let timestampStr = String(line[timestampRange])
                        
                        let wordRange = match.range(at: 2)
                        if let wordRange = Range(wordRange, in: line) {
                            let word = String(line[wordRange]).trimmingCharacters(in: .whitespaces)
                            
                            if let wordStartTime = parseVTTTimestamp(timestampStr), !word.isEmpty {
                                let wordDuration: TimeInterval = 0.4
                                let wordEndTime = min(wordStartTime + wordDuration, segmentEndTime)
                                
                                let subtitleWord = SubtitleWord(
                                    word: word,
                                    startTime: wordStartTime,
                                    endTime: wordEndTime,
                                    confidence: 0.95
                                )
                                
                                words.append(subtitleWord)
                                cleanTextParts.append(word)
                            }
                        }
                    }
                }
            }
        }
        
        let finalText = cleanTextParts.joined(separator: " ")
        
        guard !finalText.isEmpty, !words.isEmpty else {
            return nil
        }
        
        return Subtitle(
            startTime: segmentStartTime,
            endTime: segmentEndTime,
            text: finalText,
            confidence: 0.95,
            words: words,
            language: "en"
        )
    }
    
    /// 清理VTT文本 - 处理HTML实体和格式标记
    static func cleanVTTText(_ text: String) -> String {
        var cleanText = text
        
        // 移除HTML标签和VTT格式标记
        cleanText = cleanText.replacingOccurrences(of: #"<[^>]+>"#, with: "", options: .regularExpression)
        
        // 处理HTML实体
        cleanText = cleanText.replacingOccurrences(of: "&nbsp;", with: " ")
        cleanText = cleanText.replacingOccurrences(of: "&amp;", with: "&")
        cleanText = cleanText.replacingOccurrences(of: "&lt;", with: "<")
        cleanText = cleanText.replacingOccurrences(of: "&gt;", with: ">")
        cleanText = cleanText.replacingOccurrences(of: "&quot;", with: "\"")
        cleanText = cleanText.replacingOccurrences(of: "&#39;", with: "'")
        
        // 移除VTT的换行标记
        cleanText = cleanText.replacingOccurrences(of: "\\N", with: " ")
        
        // 清理多余空格
        cleanText = cleanText.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
        
        return cleanText.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    /// 解析VTT时间戳格式 (00:00:03.120)
    static func parseVTTTimestamp(_ timestamp: String) -> TimeInterval? {
        let cleanTimestamp = timestamp.trimmingCharacters(in: .whitespaces)
        let components = cleanTimestamp.components(separatedBy: ":")
        
        guard components.count == 3 else { return nil }
        
        guard let hours = Double(components[0]),
              let minutes = Double(components[1]),
              let seconds = Double(components[2]) else {
            return nil
        }
        
        return hours * 3600 + minutes * 60 + seconds
    }
    
    /// 输出VTT解析结果的详细调试信息
    static func logVTTParsingResults(_ segments: [Subtitle]) {
        guard !segments.isEmpty else {
            print("❌ [VTT Debug] 没有生成任何字幕段落！")
            return
        }
        
        let firstSegment = segments[0]
        let lastSegment = segments[segments.count - 1]
        
        print("🎯 [VTT Debug] ===== 解析结果汇总 =====")
        print("📊 字幕段落总数: \(segments.count)")
        print("⏰ 时间范围: \(formatTime(firstSegment.startTime)) - \(formatTime(lastSegment.endTime))")
        print("📏 平均段落长度: \(String(format: "%.1f", Double(segments.reduce(0) { $0 + $1.text.count }) / Double(segments.count))) 字符")
        
        // 输出前5个段落的详细信息
        print("\n🔍 [VTT Debug] 前5个字幕段落:")
        for (index, segment) in segments.prefix(5).enumerated() {
            let wordsInfo = segment.words.count
            print("  #\(index + 1): [\(formatTime(segment.startTime)) -> \(formatTime(segment.endTime))] \"\(segment.text)\" (\(wordsInfo) words)")
            
            // 如果有单词级时间戳，显示前3个单词的详情
            if !segment.words.isEmpty {
                print("    Words: ", terminator: "")
                for (wordIndex, word) in segment.words.prefix(3).enumerated() {
                    print("'\(word.word)'[\(formatTime(word.startTime))]", terminator: wordIndex < min(2, segment.words.count - 1) ? ", " : "")
                }
                if segment.words.count > 3 {
                    print("...")
                } else {
                    print("")
                }
            }
        }
        
        // 检查混合时间戳的段落
        let mixedTimingSegments = segments.filter { segment in
            guard segment.words.count >= 2 else { return false }
            // 检查是否有使用VTT行头时间的单词（通常是前几个单词）
            let firstWordTime = segment.words[0].startTime
            let segmentTime = segment.startTime
            return abs(firstWordTime - segmentTime) < 0.1 // 容差100ms
        }
        
        if !mixedTimingSegments.isEmpty {
            print("\n🔀 [VTT Debug] 发现 \(mixedTimingSegments.count) 个混合时间戳段落:")
            for (index, segment) in mixedTimingSegments.prefix(3).enumerated() {
                print("  Mixed #\(index + 1): \"\(String(segment.text.prefix(50)))...\"")
                let words = segment.words
                let vttWords = words.filter { abs($0.startTime - segment.startTime) < 0.5 }
                let cWords = words.filter { abs($0.startTime - segment.startTime) >= 0.5 }
                print("    VTT时间单词: \(vttWords.count), <c>时间单词: \(cWords.count)")
            }
        }
        
        // 检查特定时间点的字幕（用于验证同步性）
        let testTimes: [TimeInterval] = [20.0, 40.0, 60.0, 120.0]
        print("\n⏱️ [VTT Debug] 特定时间点字幕:")
        for testTime in testTimes {
            if let segment = segments.first(where: { $0.startTime <= testTime && $0.endTime >= testTime }) {
                print("  \(Int(testTime))s: \"\(String(segment.text.prefix(60)))...\"")
            } else {
                print("  \(Int(testTime))s: (无字幕)")
            }
        }
        
        // 检查是否有HTML标签残留
        let segmentsWithTags = segments.filter { 
            $0.text.contains("<") || $0.text.contains("&")
        }
        
        if !segmentsWithTags.isEmpty {
            print("\n⚠️ [VTT Debug] 发现 \(segmentsWithTags.count) 个段落仍有HTML实体或标签:")
            for (index, segment) in segmentsWithTags.prefix(3).enumerated() {
                print("  #\(index + 1): \"\(segment.text)\"")
            }
        } else {
            print("\n✅ [VTT Debug] 所有HTML实体和标签已清理完毕")
        }
        
        // 检查时间戳连续性
        var timeGaps: [TimeInterval] = []
        for i in 1..<segments.count {
            let gap = segments[i].startTime - segments[i-1].endTime
            if gap > 1.0 { // 超过1秒的间隙
                timeGaps.append(gap)
            }
        }
        
        if !timeGaps.isEmpty {
            print("\n⏳ [VTT Debug] 发现 \(timeGaps.count) 个时间间隙 (>1s)，最大间隙: \(String(format: "%.1f", timeGaps.max() ?? 0))s")
        } else {
            print("\n✅ [VTT Debug] 时间戳连续性良好")
        }
        
        print("===============================\n")
    }
    
    /// 验证和修复混合时间戳的正确性
    static func validateAndFixMixedTimings(_ words: [SubtitleWord], segmentStartTime: TimeInterval, segmentEndTime: TimeInterval) -> [SubtitleWord] {
        var fixedWords = words
        
        // 修复时间戳异常的单词
        for i in 0..<fixedWords.count {
            let word = fixedWords[i]
            
            // 确保单词时间在段落时间范围内
            if word.startTime < segmentStartTime {
                print("⚠️ [VTT Fix] 修复单词 '\(word.word)' 开始时间: \(formatTime(word.startTime)) -> \(formatTime(segmentStartTime))")
                fixedWords[i] = SubtitleWord(
                    word: word.word,
                    startTime: segmentStartTime,
                    endTime: word.endTime,
                    confidence: word.confidence
                )
            }
            
            if word.endTime > segmentEndTime {
                print("⚠️ [VTT Fix] 修复单词 '\(word.word)' 结束时间: \(formatTime(word.endTime)) -> \(formatTime(segmentEndTime))")
                fixedWords[i] = SubtitleWord(
                    word: word.word,
                    startTime: word.startTime,
                    endTime: segmentEndTime,
                    confidence: word.confidence
                )
            }
            
            // 确保单词时间戳的合理性（开始时间 < 结束时间）
            if fixedWords[i].startTime >= fixedWords[i].endTime {
                let duration = min(0.3, segmentEndTime - fixedWords[i].startTime)
                fixedWords[i] = SubtitleWord(
                    word: word.word,
                    startTime: fixedWords[i].startTime,
                    endTime: fixedWords[i].startTime + duration,
                    confidence: word.confidence
                )
            }
        }
        
        // 确保单词之间时间戳的顺序
        for i in 1..<fixedWords.count {
            if fixedWords[i].startTime < fixedWords[i-1].endTime {
                // 调整当前单词的开始时间
                fixedWords[i] = SubtitleWord(
                    word: fixedWords[i].word,
                    startTime: fixedWords[i-1].endTime,
                    endTime: max(fixedWords[i-1].endTime + 0.1, fixedWords[i].endTime),
                    confidence: fixedWords[i].confidence
                )
            }
        }
        
        return fixedWords
    }
    
    /// 格式化时间显示（调试用）
    static func formatTime(_ time: TimeInterval) -> String {
        let minutes = Int(time) / 60
        let seconds = Int(time) % 60
        let milliseconds = Int((time.truncatingRemainder(dividingBy: 1)) * 100)
        return String(format: "%d:%02d.%02d", minutes, seconds, milliseconds)
    }
    
    // MARK: - SRT格式解析
    
    /// 解析SRT格式字幕
    static func parseSRT(content: String) throws -> [Subtitle] {
        let lines = content.components(separatedBy: .newlines)
        var subtitles: [Subtitle] = []
        var i = 0
        
        while i < lines.count {
            let line = lines[i].trimmingCharacters(in: .whitespaces)
            
            // 跳过空行
            if line.isEmpty {
                i += 1
                continue
            }
            
            // 检查是否是序号行（纯数字）
            if Int(line) != nil {
                i += 1
                
                // 下一行应该是时间戳
                if i < lines.count {
                    let timeLine = lines[i].trimmingCharacters(in: .whitespaces)
                    
                    if let (startTime, endTime) = parseSRTTimestamps(timeLine) {
                        i += 1
                        
                        // 收集字幕文本
                        var textLines: [String] = []
                        while i < lines.count && !lines[i].trimmingCharacters(in: .whitespaces).isEmpty {
                            let textLine = lines[i].trimmingCharacters(in: .whitespaces)
                            if Int(textLine) == nil { // 确保不是下一个序号
                                textLines.append(textLine)
                                i += 1
                            } else {
                                break
                            }
                        }
                        
                        let fullText = textLines.joined(separator: " ")
                        let cleanText = cleanSRTText(fullText)
                        
                        if !cleanText.isEmpty {
                            let words = estimateWordTimings(for: cleanText, startTime: startTime, endTime: endTime)
                            
                            let subtitle = Subtitle(
                                startTime: startTime,
                                endTime: endTime,
                                text: cleanText,
                                confidence: nil,
                                words: words,
                                language: "en"
                            )
                            subtitles.append(subtitle)
                        }
                    } else {
                        print("⚠️ [SubtitleParser] 无法解析SRT时间戳: \(timeLine)")
                        i += 1
                    }
                } else {
                    break
                }
            } else {
                i += 1
            }
        }
        
        print("📝 [SubtitleParser] SRT解析完成: \(subtitles.count) 条字幕")
        return subtitles
    }
    
    /// 解析SRT时间戳
    static func parseSRTTimestamps(_ line: String) -> (TimeInterval, TimeInterval)? {
        // SRT格式: 00:00:01,234 --> 00:00:04,567
        let components = line.components(separatedBy: " --> ")
        guard components.count == 2 else { return nil }
        
        let startTimeStr = components[0].trimmingCharacters(in: .whitespaces)
        let endTimeStr = components[1].trimmingCharacters(in: .whitespaces)
        
        guard let startTime = parseSRTTimestamp(startTimeStr),
              let endTime = parseSRTTimestamp(endTimeStr) else {
            return nil
        }
        
        return (startTime, endTime)
    }
    
    /// 解析单个SRT时间戳
    static func parseSRTTimestamp(_ timestamp: String) -> TimeInterval? {
        // 格式: 00:00:01,234
        let parts = timestamp.components(separatedBy: ",")
        guard parts.count == 2 else { return nil }
        
        let timePart = parts[0]
        let millisecondsPart = parts[1]
        
        let timeComponents = timePart.components(separatedBy: ":")
        guard timeComponents.count == 3,
              let hours = Double(timeComponents[0]),
              let minutes = Double(timeComponents[1]),
              let seconds = Double(timeComponents[2]),
              let milliseconds = Double(millisecondsPart) else {
            return nil
        }
        
        return hours * 3600 + minutes * 60 + seconds + milliseconds / 1000
    }
    
    /// 清理SRT文本
    static func cleanSRTText(_ text: String) -> String {
        var cleanText = text
        
        // 移除HTML标签
        cleanText = cleanText.replacingOccurrences(of: #"<[^>]+>"#, with: "", options: .regularExpression)
        
        // 移除字幕格式标记
        cleanText = cleanText.replacingOccurrences(of: "\\N", with: " ")
        cleanText = cleanText.replacingOccurrences(of: "{\\*}", with: "")
        
        // 清理多余空格
        cleanText = cleanText.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
        
        return cleanText.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    // MARK: - 通用辅助方法
    
    /// 估算单词时间戳
    static func estimateWordTimings(for text: String, startTime: TimeInterval, endTime: TimeInterval) -> [SubtitleWord] {
        let words = text.components(separatedBy: .whitespaces).filter { !$0.isEmpty }
        let duration = endTime - startTime
        let wordDuration = duration / Double(words.count)
        
        return words.enumerated().map { index, word in
            let wordStartTime = startTime + Double(index) * wordDuration
            let wordEndTime = wordStartTime + wordDuration
            
            return SubtitleWord(
                word: word,
                startTime: wordStartTime,
                endTime: wordEndTime,
                confidence: nil
            )
        }
    }
    
  
}

// MARK: - 错误类型

enum SubtitleParserError: Error, LocalizedError {
    case invalidURL
    case emptyFile
    case invalidEncoding
    case parseError(String)
    
    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "无效的URL"
        case .emptyFile:
            return "字幕文件为空"
        case .invalidEncoding:
            return "字幕文件编码错误"
        case .parseError(let message):
            return "解析错误: \(message)"
        }
    }
}

// MARK: - 向后兼容

/// SRTParser的向后兼容性别名
typealias SRTParser = SubtitleParser 
