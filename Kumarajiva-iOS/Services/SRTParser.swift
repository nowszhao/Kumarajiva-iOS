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
    
    /// 解析VTT格式字幕 - 优化版本，支持<c>标签和去重
    static func parseVTT(content: String) throws -> [Subtitle] {
        let lines = content.components(separatedBy: .newlines)
        var subtitles: [Subtitle] = []
        var i = 0
        
        // 跳过VTT头部
        while i < lines.count && !lines[i].contains("-->") {
            i += 1
        }
        
        print("📝 [VTT Parser] 开始解析VTT字幕（智能模式）...")
        
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
                    print("⚠️ [VTT Parser] 无法解析时间戳: \(line)")
                    i += 1
                    continue
                }
                
                // 收集这个时间段的所有文本行
                i += 1
                var textLines: [String] = []
                
                while i < lines.count {
                    let textLine = lines[i].trimmingCharacters(in: .whitespaces)
                    
                    // 空行表示段落结束
                    if textLine.isEmpty {
                        break
                    }
                    
                    // 检查是否是下一个时间戳行
                    if textLine.contains("-->") {
                        i -= 1 // 回退一行，让外层循环处理
                        break
                    }
                    
                    // 收集所有文本行
                    textLines.append(textLine)
                    i += 1
                }
                
                // 处理收集到的文本
                if !textLines.isEmpty {
                    let fullText = textLines.joined(separator: " ")
                    
                    // 检查是否包含<c>标签（单词级时间戳）
                    if fullText.contains("<c>") && fullText.contains("</c>") {
                        // 解析带<c>标签的精确单词时间戳（新逻辑）
                        if let subtitle = parseVTTWithMixedTimings(fullText, segmentStartTime: segmentStartTime, segmentEndTime: segmentEndTime) {
                            subtitles.append(subtitle)
                        }
                    } else {
                        // 普通句子级别解析
                        let cleanText = cleanVTTText(fullText)
                        
                        if !cleanText.isEmpty {
                            // 为段落中的单词估算时间戳
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
                        }
                    }
                }
            }
            
            i += 1
        }
        
        print("📝 [VTT Parser] 初步解析完成: \(subtitles.count) 个字幕段落")
        
        // 去重处理：处理相同时间戳的重复内容
        let deduplicatedSubtitles = deduplicateSubtitles(subtitles)
        
        print("📝 [VTT Parser] 去重后: \(deduplicatedSubtitles.count) 个字幕段落")
        
        // 输出解析结果的详细调试信息
        logVTTParsingResults(deduplicatedSubtitles)
        
        return deduplicatedSubtitles
    }
    
    /// 解析包含<c>标签的VTT文本，支持混合时间戳分配（新实现）
    static func parseVTTWithMixedTimings(_ text: String, segmentStartTime: TimeInterval, segmentEndTime: TimeInterval) -> Subtitle? {
        print("🎯 [VTT Mixed] 解析混合时间戳文本: \(text.prefix(100))...")
        
        var words: [SubtitleWord] = []
        var cleanTextParts: [String] = []
        
        // 策略：对于包含<c>标签的字幕，只提取<c>内的内容，忽略其他文本
        // 这样可以避免重复，因为<c>内容是独特的且有精确时间戳
        
        // 第一步：检查是否包含<c>标签
        if text.contains("<c>") && text.contains("</c>") {
            print("📝 [VTT Mixed] 检测到<c>标签，仅提取<c>内容")
            
            // 第二步：提取所有 <时间戳><c>单词</c> 组合
            let pattern = #"<(\d{2}:\d{2}:\d{2}\.\d{3})><c>\s*([^<]+?)\s*</c>"#
            let regex = try? NSRegularExpression(pattern: pattern, options: [])
            let textRange = NSRange(location: 0, length: text.count)
            
            if let regex = regex {
                let matches = regex.matches(in: text, options: [], range: textRange)
                
                if !matches.isEmpty {
                    // 有<c>标签的精确时间戳，完全按照<c>内容构建字幕
                    for match in matches {
                        if match.numberOfRanges >= 3 {
                            // 提取时间戳
                            let timestampRange = match.range(at: 1)
                            if let timestampRange = Range(timestampRange, in: text) {
                                let timestampStr = String(text[timestampRange])
                                
                                // 提取单词
                                let wordRange = match.range(at: 2)
                                if let wordRange = Range(wordRange, in: text) {
                                    let word = String(text[wordRange]).trimmingCharacters(in: .whitespaces)
                                    
                                    if let wordStartTime = parseVTTTimestamp(timestampStr), !word.isEmpty {
                                        let wordDuration: TimeInterval = 0.4 // <c>标签的单词持续时间
                                        let wordEndTime = min(wordStartTime + wordDuration, segmentEndTime)
                                        
                                        let subtitleWord = SubtitleWord(
                                            word: word,
                                            startTime: wordStartTime,
                                            endTime: wordEndTime,
                                            confidence: 0.95 // 最高置信度，有精确时间戳
                                        )
                                        
                                        words.append(subtitleWord)
                                        cleanTextParts.append(word)
                                        
                                        print("📝 [VTT Mixed] <c>单词: '\(word)' → 时间: \(formatTime(wordStartTime))")
                                    }
                                }
                            }
                        }
                    }
                } else {
                    print("⚠️ [VTT Mixed] 没有找到有效的<c>标签匹配")
                    return nil
                }
            }
        } else {
            print("📝 [VTT Mixed] 无<c>标签，按原逻辑处理")
            // 如果没有<c>标签，回退到原来的逻辑
            let cleanText = cleanVTTText(text)
            if !cleanText.isEmpty {
                let estimatedWords = estimateWordTimings(for: cleanText, startTime: segmentStartTime, endTime: segmentEndTime)
                words = estimatedWords
                cleanTextParts = estimatedWords.map { $0.word }
            }
        }
        
        // 第三步：组合最终文本和计算段落时间范围
        let finalText = cleanTextParts.joined(separator: " ")
        
        guard !finalText.isEmpty, !words.isEmpty else {
            print("⚠️ [VTT Mixed] 解析结果为空")
            return nil
        }
        
        // 使用<c>标签的精确时间范围
        let actualStartTime = words.first?.startTime ?? segmentStartTime
        let actualEndTime = words.last?.endTime ?? segmentEndTime
        
        let subtitle = Subtitle(
            startTime: actualStartTime,
            endTime: actualEndTime,
            text: finalText,
            confidence: 0.95,
            words: words,
            language: "en"
        )
        
        print("✅ [VTT Mixed] 成功解析: '\(finalText)' [\(formatTime(actualStartTime)) -> \(formatTime(actualEndTime))] (\(words.count) words)")
        
        return subtitle
    }
    
    /// 解析带有<c>标签的VTT文本，提取精确的单词时间戳（保留旧版本作为备用）
    static func parseVTTWithWordTimings(_ text: String, segmentStartTime: TimeInterval, segmentEndTime: TimeInterval) -> Subtitle? {
        // 先提取基础文本（去掉时间戳标记）
        var baseText = text
        
        // 移除时间戳标记 <00:00:03.120> 但保留 <c> 标签
        baseText = baseText.replacingOccurrences(of: #"<\d{2}:\d{2}:\d{2}\.\d{3}>"#, with: "", options: .regularExpression)
        
        // 现在解析<c>标签内的单词和它们的时间戳
        var words: [SubtitleWord] = []
        var cleanText = ""
        
        // 分割文本，寻找<c>标签
        let pattern = #"([^<]*)<c>([^<]*)</c>"#
        let regex = try? NSRegularExpression(pattern: pattern, options: [])
        let range = NSRange(location: 0, length: text.count)
        
        var lastRange = 0
        var currentTime = segmentStartTime
        
        regex?.enumerateMatches(in: text, options: [], range: range) { match, _, _ in
            guard let match = match else { return }
            
            // 获取<c>标签前的文本
            if match.range.location > lastRange {
                let beforeRange = NSRange(location: lastRange, length: match.range.location - lastRange)
                if let beforeText = Range(beforeRange, in: text) {
                    let before = String(text[beforeText]).trimmingCharacters(in: .whitespaces)
                    if !before.isEmpty {
                        // 处理<c>标签前的文本，可能包含时间戳
                        let (beforeWords, newTime) = extractWordsWithTimestamps(from: before, startTime: currentTime)
                        words.append(contentsOf: beforeWords)
                        cleanText += beforeWords.map { $0.word }.joined(separator: " ")
                        if !cleanText.isEmpty && !beforeWords.isEmpty {
                            cleanText += " "
                        }
                        currentTime = newTime
                    }
                }
            }
            
            // 获取<c>标签内的单词
            if match.numberOfRanges > 2 {
                let wordRange = match.range(at: 2)
                if let wordRange = Range(wordRange, in: text) {
                    let word = String(text[wordRange]).trimmingCharacters(in: .whitespaces)
                    if !word.isEmpty {
                        // 估算这个单词的结束时间（简单估算）
                        let wordDuration = 0.3 // 假设每个单词0.3秒
                        let wordEndTime = min(currentTime + wordDuration, segmentEndTime)
                        
                        let subtitleWord = SubtitleWord(
                            word: word,
                            startTime: currentTime,
                            endTime: wordEndTime,
                            confidence: 0.95 // 高置信度，因为有精确时间戳
                        )
                        
                        words.append(subtitleWord)
                        if !cleanText.isEmpty {
                            cleanText += " "
                        }
                        cleanText += word
                        currentTime = wordEndTime
                    }
                }
            }
            
            lastRange = match.range.location + match.range.length
        }
        
        // 处理最后剩余的文本
        if lastRange < text.count {
            let remainingRange = NSRange(location: lastRange, length: text.count - lastRange)
            if let remainingRange = Range(remainingRange, in: text) {
                let remaining = String(text[remainingRange]).trimmingCharacters(in: .whitespaces)
                if !remaining.isEmpty {
                    let (remainingWords, _) = extractWordsWithTimestamps(from: remaining, startTime: currentTime)
                    words.append(contentsOf: remainingWords)
                    if !cleanText.isEmpty && !remainingWords.isEmpty {
                        cleanText += " "
                    }
                    cleanText += remainingWords.map { $0.word }.joined(separator: " ")
                }
            }
        }
        
        // 清理最终文本
        cleanText = cleanVTTText(cleanText)
        
        guard !cleanText.isEmpty else { return nil }
        
        return Subtitle(
            startTime: segmentStartTime,
            endTime: segmentEndTime,
            text: cleanText,
            confidence: 0.95, // 高置信度
            words: words,
            language: "en"
        )
    }
    
    /// 从文本中提取带时间戳的单词
    static func extractWordsWithTimestamps(from text: String, startTime: TimeInterval) -> ([SubtitleWord], TimeInterval) {
        var words: [SubtitleWord] = []
        var currentTime = startTime
        
        // 先提取所有时间戳
        let timestampPattern = #"<(\d{2}:\d{2}:\d{2}\.\d{3})>"#
        let timestampRegex = try? NSRegularExpression(pattern: timestampPattern, options: [])
        
        var textWithoutTimestamps = text
        var timestamps: [TimeInterval] = []
        
        // 收集所有时间戳
        if let regex = timestampRegex {
            let matches = regex.matches(in: text, options: [], range: NSRange(location: 0, length: text.count))
            for match in matches.reversed() { // 从后往前处理，避免索引偏移
                if match.numberOfRanges > 1 {
                    let timestampRange = match.range(at: 1)
                    if let range = Range(timestampRange, in: text) {
                        let timestampStr = String(text[range])
                        if let timestamp = parseVTTTimestamp(timestampStr) {
                            timestamps.insert(timestamp, at: 0)
                        }
                    }
                    // 移除时间戳标记
                    let fullRange = match.range
                    if let range = Range(fullRange, in: textWithoutTimestamps) {
                        textWithoutTimestamps.removeSubrange(range)
                    }
                }
            }
        }
        
        // 分割单词
        let wordList = textWithoutTimestamps.components(separatedBy: .whitespaces).filter { !$0.isEmpty }
        
        for (index, word) in wordList.enumerated() {
            let cleanWord = cleanVTTText(word)
            if !cleanWord.isEmpty {
                // 如果有对应的时间戳，使用它；否则估算
                let wordStartTime = index < timestamps.count ? timestamps[index] : currentTime
                let wordEndTime = wordStartTime + 0.3 // 假设每个单词0.3秒
                
                let subtitleWord = SubtitleWord(
                    word: cleanWord,
                    startTime: wordStartTime,
                    endTime: wordEndTime,
                    confidence: 0.9
                )
                
                words.append(subtitleWord)
                currentTime = wordEndTime
            }
        }
        
        return (words, currentTime)
    }
    
    /// 去重字幕：处理相同时间戳的重复内容，保留最长的
    static func deduplicateSubtitles(_ subtitles: [Subtitle]) -> [Subtitle] {
        var deduplicatedSubtitles: [Subtitle] = []
        
        print("🔄 [VTT Dedup] 开始去重处理: \(subtitles.count) 个字幕")
        
        for subtitle in subtitles {
            var shouldAdd = true
            var indexToReplace: Int? = nil
            
            // 检查是否与现有字幕重复或重叠
            for (index, existingSubtitle) in deduplicatedSubtitles.enumerated() {
                let timeTolerance: TimeInterval = 2.0 // 增加时间容差到2秒
                let timeOverlap = checkTimeOverlap(subtitle, existingSubtitle, tolerance: timeTolerance)
                
                if timeOverlap {
                    let existingText = existingSubtitle.text
                    let newText = subtitle.text
                    
                    // 计算文本重叠度
                    let overlapScore = calculateTextOverlap(existingText, newText)
                    
                    print("🔍 [VTT Dedup] 检查重叠:")
                    print("   现有: '\(String(existingText.prefix(40)))...' [\(formatTime(existingSubtitle.startTime))-\(formatTime(existingSubtitle.endTime))]")
                    print("   新的: '\(String(newText.prefix(40)))...' [\(formatTime(subtitle.startTime))-\(formatTime(subtitle.endTime))]")
                    print("   重叠度: \(String(format: "%.1f", overlapScore * 100))%")
                    
                    // 如果文本重叠度超过50%，认为是重复或重叠
                    if overlapScore > 0.5 {
                        if newText.count > existingText.count {
                            // 新文本更长更完整，替换现有的
                            print("🔄 [VTT Dedup] 替换为更长文本: \(existingText.count) -> \(newText.count) 字符")
                            indexToReplace = index
                            break
                        } else if newText.count < Int(Double(existingText.count) * 0.8) {
                            // 新文本明显更短，跳过
                            print("🚫 [VTT Dedup] 跳过较短文本")
                            shouldAdd = false
                            break
                        } else if subtitle.words.count > existingSubtitle.words.count {
                            // 新字幕有更多单词级时间戳，更精确
                            print("🔄 [VTT Dedup] 替换为更精确字幕: \(existingSubtitle.words.count) -> \(subtitle.words.count) words")
                            indexToReplace = index
                            break
                        } else {
                            // 保留现有的
                            print("🚫 [VTT Dedup] 保留现有字幕")
                            shouldAdd = false
                            break
                        }
                    }
                }
            }
            
            if shouldAdd {
                if let replaceIndex = indexToReplace {
                    // 替换现有字幕
                    deduplicatedSubtitles[replaceIndex] = subtitle
                } else {
                    // 添加新字幕
                    deduplicatedSubtitles.append(subtitle)
                }
            }
        }
        
        // 按时间排序
        let sortedSubtitles = deduplicatedSubtitles.sorted { $0.startTime < $1.startTime }
        
        print("📊 [VTT Dedup] 去重完成: \(subtitles.count) -> \(sortedSubtitles.count) 个字幕段落")
        
        return sortedSubtitles
    }
    
    /// 检查两个字幕的时间是否重叠
    static func checkTimeOverlap(_ subtitle1: Subtitle, _ subtitle2: Subtitle, tolerance: TimeInterval) -> Bool {
        // 检查时间范围是否重叠或接近
        let start1 = subtitle1.startTime
        let end1 = subtitle1.endTime
        let start2 = subtitle2.startTime
        let end2 = subtitle2.endTime
        
        // 时间重叠检测
        let timeOverlap = max(0, min(end1, end2) - max(start1, start2))
        let minDuration = min(end1 - start1, end2 - start2)
        
        // 如果重叠时间超过较短字幕持续时间的30%，或者间隙小于容差，认为是重叠
        return timeOverlap > minDuration * 0.3 || abs(start1 - start2) < tolerance || abs(end1 - end2) < tolerance
    }
    
    /// 计算两个文本的重叠度（0-1之间的值）
    static func calculateTextOverlap(_ text1: String, _ text2: String) -> Double {
        // 清理文本
        let clean1 = cleanTextForComparison(text1)
        let clean2 = cleanTextForComparison(text2)
        
        // 分词
        let words1 = Set(clean1.components(separatedBy: .whitespaces).filter { !$0.isEmpty })
        let words2 = Set(clean2.components(separatedBy: .whitespaces).filter { !$0.isEmpty })
        
        // 计算重叠度
        let intersection = words1.intersection(words2)
        let union = words1.union(words2)
        
        if union.isEmpty {
            return 0.0
        }
        
        // Jaccard相似度
        let jaccardSimilarity = Double(intersection.count) / Double(union.count)
        
        // 同时检查是否一个文本包含另一个文本
        let containmentSimilarity1 = clean2.contains(clean1) ? 1.0 : 0.0
        let containmentSimilarity2 = clean1.contains(clean2) ? 1.0 : 0.0
        let containmentSimilarity = max(containmentSimilarity1, containmentSimilarity2)
        
        // 返回最大相似度
        return max(jaccardSimilarity, containmentSimilarity)
    }
    
    /// 清理文本用于比较
    static func cleanTextForComparison(_ text: String) -> String {
        return text
            .lowercased()
            .replacingOccurrences(of: #"[^\w\s]"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
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
    
    // MARK: - SRT格式解析（保持原有逻辑）
    
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
