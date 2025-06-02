import Foundation
import Combine

class RSSParserService: NSObject, ObservableObject {
    static let shared = RSSParserService()
    
    @Published var isLoading = false
    @Published var errorMessage: String?
    
    private var currentPodcast: Podcast?
    private var currentEpisodes: [PodcastEpisode] = []
    private var currentElement = ""
    private var currentTitle = ""
    private var currentDescription = ""
    private var currentLink = ""
    private var currentPubDate = ""
    private var currentDuration = ""
    private var currentEnclosureURL = ""
    private var currentImageURL = ""
    private var currentAuthor = ""
    private var currentLanguage = ""
    
    private var isInItem = false
    private var isInChannel = true
    
    override init() {
        super.init()
    }
    
    // MARK: - 公共方法
    func parsePodcastRSS(from urlString: String) async throws -> RSSParseResult {
        print("🎧 [RSS] 开始解析RSS: \(urlString)")
        
        guard let url = URL(string: urlString) else {
            throw RSSError.invalidURL
        }
        
        await MainActor.run {
            self.isLoading = true
            self.errorMessage = nil
        }
        
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            let result = try await parseRSSData(data, rssURL: urlString)
            
            await MainActor.run {
                self.isLoading = false
            }
            
            print("🎧 [RSS] 解析完成，获得 \(result.episodes.count) 个节目")
            return result
            
        } catch {
            await MainActor.run {
                self.isLoading = false
                self.errorMessage = error.localizedDescription
            }
            throw error
        }
    }
    
    // MARK: - 私有方法
    private func parseRSSData(_ data: Data, rssURL: String) async throws -> RSSParseResult {
        return try await withCheckedThrowingContinuation { continuation in
            // 重置解析状态
            resetParsingState()
            
            let parser = XMLParser(data: data)
            parser.delegate = self
            
            DispatchQueue.global(qos: .userInitiated).async {
                let success = parser.parse()
                
                DispatchQueue.main.async {
                    if success {
                        let podcast = Podcast(
                            title: self.currentTitle.isEmpty ? "未知播客" : self.currentTitle,
                            description: self.currentDescription,
                            rssURL: rssURL,
                            imageURL: self.currentImageURL.isEmpty ? nil : self.currentImageURL,
                            author: self.currentAuthor.isEmpty ? nil : self.currentAuthor,
                            language: self.currentLanguage.isEmpty ? nil : self.currentLanguage,
                            episodes: self.currentEpisodes
                        )
                        
                        let result = RSSParseResult(
                            podcast: podcast,
                            episodes: self.currentEpisodes,
                            error: nil
                        )
                        
                        continuation.resume(returning: result)
                    } else {
                        continuation.resume(throwing: RSSError.parsingFailed)
                    }
                }
            }
        }
    }
    
    private func resetParsingState() {
        currentEpisodes.removeAll()
        currentTitle = ""
        currentDescription = ""
        currentLink = ""
        currentImageURL = ""
        currentAuthor = ""
        currentLanguage = ""
        isInItem = false
        isInChannel = true
    }
    
    private func parseDuration(_ durationString: String) -> TimeInterval {
        // 支持多种时间格式: "HH:MM:SS", "MM:SS", "秒数"
        let components = durationString.components(separatedBy: ":")
        
        if components.count == 3 {
            // HH:MM:SS
            let hours = Double(components[0]) ?? 0
            let minutes = Double(components[1]) ?? 0
            let seconds = Double(components[2]) ?? 0
            return hours * 3600 + minutes * 60 + seconds
        } else if components.count == 2 {
            // MM:SS
            let minutes = Double(components[0]) ?? 0
            let seconds = Double(components[1]) ?? 0
            return minutes * 60 + seconds
        } else {
            // 纯秒数
            return Double(durationString) ?? 0
        }
    }
    
    private func parseDate(_ dateString: String) -> Date {
        let formatters = [
            "EEE, dd MMM yyyy HH:mm:ss Z",
            "yyyy-MM-dd'T'HH:mm:ssZ",
            "yyyy-MM-dd'T'HH:mm:ss.SSSZ",
            "yyyy-MM-dd HH:mm:ss"
        ]
        
        for format in formatters {
            let formatter = DateFormatter()
            formatter.dateFormat = format
            formatter.locale = Locale(identifier: "en_US_POSIX")
            
            if let date = formatter.date(from: dateString) {
                return date
            }
        }
        
        return Date()
    }
}

// MARK: - XMLParserDelegate
extension RSSParserService: XMLParserDelegate {
    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes attributeDict: [String : String] = [:]) {
        currentElement = elementName
        
        if elementName == "item" {
            isInItem = true
            isInChannel = false
            // 重置当前项目的数据
            currentTitle = ""
            currentDescription = ""
            currentLink = ""
            currentPubDate = ""
            currentDuration = ""
            currentEnclosureURL = ""
        } else if elementName == "enclosure" {
            currentEnclosureURL = attributeDict["url"] ?? ""
        } else if elementName == "image" && !isInItem {
            // 频道级别的图片
        }
    }
    
    func parser(_ parser: XMLParser, foundCharacters string: String) {
        let trimmedString = string.trimmingCharacters(in: .whitespacesAndNewlines)
        
        switch currentElement {
        case "title":
            if isInItem {
                currentTitle += trimmedString
            } else if isInChannel {
                self.currentTitle += trimmedString
            }
        case "description":
            if isInItem {
                currentDescription += trimmedString
            } else if isInChannel {
                self.currentDescription += trimmedString
            }
        case "link":
            if isInItem {
                currentLink += trimmedString
            }
        case "pubDate":
            if isInItem {
                currentPubDate += trimmedString
            }
        case "itunes:duration":
            if isInItem {
                currentDuration += trimmedString
            }
        case "itunes:author":
            if !isInItem {
                currentAuthor += trimmedString
            }
        case "language":
            if !isInItem {
                currentLanguage += trimmedString
            }
        case "url":
            if !isInItem {
                currentImageURL += trimmedString
            }
        default:
            break
        }
    }
    
    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
        if elementName == "item" {
            // 创建播客单集，使用稳定的ID（基于标题和音频URL）
            let stableId = generateStableEpisodeId(title: currentTitle, audioURL: currentEnclosureURL)
            
            let episode = PodcastEpisode(
                id: stableId,
                title: currentTitle.isEmpty ? "未知标题" : currentTitle,
                description: currentDescription,
                audioURL: currentEnclosureURL,
                duration: parseDuration(currentDuration),
                publishDate: parseDate(currentPubDate)
            )
            
            currentEpisodes.append(episode)
            isInItem = false
            isInChannel = true
        }
        
        currentElement = ""
    }
    
    /// 生成稳定的节目ID，基于标题和音频URL
    private func generateStableEpisodeId(title: String, audioURL: String) -> String {
        let combinedString = "\(title)_\(audioURL)"
        let hash = combinedString.hash
        return "episode_\(abs(hash))"
    }
    
    func parser(_ parser: XMLParser, parseErrorOccurred parseError: Error) {
        print("🎧 [RSS] 解析错误: \(parseError.localizedDescription)")
    }
}

// MARK: - 错误定义
enum RSSError: LocalizedError {
    case invalidURL
    case parsingFailed
    case networkError(Error)
    
    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "无效的RSS地址"
        case .parsingFailed:
            return "RSS解析失败"
        case .networkError(let error):
            return "网络错误: \(error.localizedDescription)"
        }
    }
} 
