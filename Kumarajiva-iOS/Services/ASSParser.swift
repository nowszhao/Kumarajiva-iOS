import Foundation

/// ASS/SSA 字幕解析器
class ASSParser {
    
    /// 解析 ASS/SSA 字幕文件
    static func parseASS(content: String) throws -> [Subtitle] {
        let lines = content.components(separatedBy: .newlines)
        var subtitles: [Subtitle] = []
        var inEventsSection = false
        var formatFields: [String] = []
        
        print("📝 [ASSParser] 开始解析 ASS/SSA 字幕")
        
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            
            // 跳过空行和注释
            if trimmed.isEmpty || trimmed.hasPrefix(";") {
                continue
            }
            
            // 检测 [Events] 段
            if trimmed == "[Events]" {
                inEventsSection = true
                print("📝 [ASSParser] 进入 Events 段")
                continue
            }
            
            // 检测其他段落开始
            if trimmed.hasPrefix("[") && trimmed.hasSuffix("]") {
                if inEventsSection {
                    print("📝 [ASSParser] 离开 Events 段")
                }
                inEventsSection = false
                continue
            }
            
            guard inEventsSection else { continue }
            
            // 解析 Format 行
            if trimmed.hasPrefix("Format:") {
                let formatLine = trimmed.replacingOccurrences(of: "Format:", with: "")
                formatFields = formatLine.components(separatedBy: ",").map { $0.trimmingCharacters(in: .whitespaces) }
                print("📝 [ASSParser] Format 字段: \(formatFields)")
                continue
            }
            
            // 解析 Dialogue 行
            if trimmed.hasPrefix("Dialogue:") {
                guard !formatFields.isEmpty else {
                    print("⚠️ [ASSParser] 未找到 Format 行，跳过 Dialogue")
                    continue
                }
                
                if let subtitle = parseDialogueLine(trimmed, formatFields: formatFields) {
                    subtitles.append(subtitle)
                }
            }
        }
        
        print("✅ [ASSParser] 解析完成，共 \(subtitles.count) 条字幕")
        return subtitles
    }
    
    /// 解析单行 Dialogue
    private static func parseDialogueLine(_ line: String, formatFields: [String]) -> Subtitle? {
        let dialogueLine = line.replacingOccurrences(of: "Dialogue:", with: "")
        
        // ASS 格式的 Dialogue 行可能包含逗号，需要特殊处理
        // 格式: Layer, Start, End, Style, Name, MarginL, MarginR, MarginV, Effect, Text
        // Text 字段可能包含逗号，所以需要从后往前解析
        
        var fields = dialogueLine.components(separatedBy: ",")
        
        // 确保至少有足够的字段
        guard fields.count >= formatFields.count else {
            return nil
        }
        
        // 如果字段数量超过 Format 定义，说明 Text 字段包含逗号
        // 需要将多余的字段合并到 Text 字段
        if fields.count > formatFields.count {
            let textStartIndex = formatFields.count - 1
            let textParts = fields[textStartIndex...]
            let mergedText = textParts.joined(separator: ",")
            fields = Array(fields[0..<textStartIndex]) + [mergedText]
        }
        
        // 构建字段字典
        var fieldDict: [String: String] = [:]
        for (index, field) in formatFields.enumerated() {
            if index < fields.count {
                fieldDict[field] = fields[index].trimmingCharacters(in: .whitespaces)
            }
        }
        
        // 提取时间和文本
        guard let startStr = fieldDict["Start"],
              let endStr = fieldDict["End"],
              let text = fieldDict["Text"] else {
            return nil
        }
        
        guard let startTime = parseASSTimestamp(startStr),
              let endTime = parseASSTimestamp(endStr) else {
            return nil
        }
        
        // 清理文本(移除 ASS 标签)
        let cleanText = cleanASSText(text)
        
        // 跳过空字幕
        guard !cleanText.isEmpty else {
            return nil
        }
        
        return Subtitle(
            startTime: startTime,
            endTime: endTime,
            text: cleanText
        )
    }
    
    /// 解析 ASS 时间戳
    /// 格式: 0:00:00.00 (小时:分钟:秒.厘秒)
    private static func parseASSTimestamp(_ timestamp: String) -> TimeInterval? {
        let components = timestamp.components(separatedBy: ":")
        guard components.count == 3 else { return nil }
        
        let hours = Double(components[0]) ?? 0
        let minutes = Double(components[1]) ?? 0
        let seconds = Double(components[2]) ?? 0
        
        return hours * 3600 + minutes * 60 + seconds
    }
    
    /// 清理 ASS 文本标签
    /// ASS 支持丰富的格式标签，如 {\b1}粗体{\b0}，{\i1}斜体{\i0} 等
    private static func cleanASSText(_ text: String) -> String {
        var cleaned = text
        
        // 移除 {\...} 标签
        // 使用正则表达式匹配所有 {\...} 格式的标签
        let pattern = "\\{[^}]*\\}"
        if let regex = try? NSRegularExpression(pattern: pattern, options: []) {
            let range = NSRange(cleaned.startIndex..., in: cleaned)
            cleaned = regex.stringByReplacingMatches(in: cleaned, options: [], range: range, withTemplate: "")
        }
        
        // 移除 \N 换行符 (ASS 使用 \N 表示换行)
        cleaned = cleaned.replacingOccurrences(of: "\\N", with: " ")
        
        // 移除 \n 换行符
        cleaned = cleaned.replacingOccurrences(of: "\\n", with: " ")
        
        // 移除 \h 硬空格
        cleaned = cleaned.replacingOccurrences(of: "\\h", with: " ")
        
        // 移除其他转义字符
        cleaned = cleaned.replacingOccurrences(of: "\\", with: "")
        
        // 清理多余空格
        cleaned = cleaned.replacingOccurrences(of: "  ", with: " ")
        
        return cleaned.trimmingCharacters(in: .whitespaces)
    }
}

// MARK: - SSA 格式支持
extension ASSParser {
    /// 解析 SSA 字幕文件 (SSA 是 ASS 的前身，格式类似)
    static func parseSSA(content: String) throws -> [Subtitle] {
        // SSA 格式与 ASS 基本相同，可以复用 ASS 解析器
        return try parseASS(content: content)
    }
}

// MARK: - 错误类型
enum ASSParserError: LocalizedError {
    case invalidFormat
    case noEventsSection
    case noFormatLine
    
    var errorDescription: String? {
        switch self {
        case .invalidFormat:
            return "无效的 ASS/SSA 格式"
        case .noEventsSection:
            return "未找到 [Events] 段"
        case .noFormatLine:
            return "未找到 Format 行"
        }
    }
}
