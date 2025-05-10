import Foundation
import Combine

class WordCollocationService: ObservableObject {
    static let shared = WordCollocationService()
    
    // Published properties
    @Published var isLoading: Bool = false
    @Published var currentCollocation: WordCollocation?
    @Published var error: String?
    
    private let llmService = LLMService.shared
    private let cacheFileName = "word_collocations_cache.json"
    private var collocationsCache: [String: WordCollocation] = [:]
    
    private init() {
        loadCacheFromDisk()
    }
    
    /// Get collocations for a word
    /// - Parameters:
    ///   - word: The word to get collocations for
    ///   - forceRefresh: 是否强制刷新，忽略缓存
    /// - Returns: The collocations for the word, either from cache or LLM
    func getCollocations(for word: String, forceRefresh: Bool = false) async -> WordCollocation? {
        // 先检查是否要强制刷新
        if forceRefresh {
            clearCache(for: word)
        }
        
        // 检查缓存
        if !forceRefresh, let cached = collocationsCache[word.lowercased()] {
            print("WordCollocationService: Using cached collocations for '\(word)'")
            await MainActor.run {
                self.currentCollocation = cached
                self.isLoading = false
                self.error = nil
            }
            return cached
        }
        
        // 如果不在缓存中，从LLM获取
        await MainActor.run {
            self.isLoading = true
            self.error = nil
        }
        
        do {
            let prompt = """
            我们学习汉字一般会结合组词来记忆，比如学习"场"，会组词"场地"，"广场"，这样的好处是把这些搭配可以直接应用在表达中。所以我们学习英语单词应该不只是英文到中文的翻译，应该还出最常见的单词搭配形成词块去记忆。 按照这个思路，请给出单词的最常用的 3 个词块或搭配，按照优先级倒序排列，举例如下：
            - 举例：be on the cusp of    
            - 输出：
            {
                "word":"be on the cusp of"
                "chunks":[
                    {
                        "chunck":"be on the cusp of change"
                        "chunckChinese":"即将迎来变革"
                        "chunckSentence":"The industry is on the cusp of major change.(这个行业即将迎来变革。)"
                    },
                    ...
                ]
            }

            请严格按照Json格式输出，解析单词为：
            \(word)
            """
            
            print("WordCollocationService: Prompt: \(prompt)")
            print("WordCollocationService: 正在解析词语搭配: '\(word)'")

            let llmResponse = try await llmService.sendChatMessage(prompt: prompt)
            
            // Parse response to extract the JSON part
            let jsonData = extractJsonFromText(llmResponse)
            let collocation = try JSONDecoder().decode(WordCollocation.self, from: jsonData)
            
            // Save to cache
            collocationsCache[word.lowercased()] = collocation
            saveCacheToDisk()
            
            await MainActor.run {
                self.currentCollocation = collocation
                self.isLoading = false
            }
            
            return collocation
        } catch {
            print("WordCollocationService: Error getting collocations: \(error.localizedDescription)")
            await MainActor.run {
                self.error = "获取词语搭配失败：\(error.localizedDescription)"
                self.isLoading = false
            }
            return nil
        }
    }
    
    /// Load word collocations from disk
    private func loadCacheFromDisk() {
        guard let cacheFileURL = cacheFileURL else { return }
        
        do {
            if FileManager.default.fileExists(atPath: cacheFileURL.path) {
                let data = try Data(contentsOf: cacheFileURL)
                let cachedCollocations = try JSONDecoder().decode([String: WordCollocation].self, from: data)
                self.collocationsCache = cachedCollocations
                print("WordCollocationService: Loaded \(cachedCollocations.count) collocations from cache")
            }
        } catch {
            print("WordCollocationService: Error loading cache: \(error.localizedDescription)")
        }
    }
    
    /// Save word collocations to disk
    private func saveCacheToDisk() {
        guard let cacheFileURL = cacheFileURL else { return }
        
        do {
            let data = try JSONEncoder().encode(collocationsCache)
            try data.write(to: cacheFileURL)
            print("WordCollocationService: Saved \(collocationsCache.count) collocations to cache")
        } catch {
            print("WordCollocationService: Error saving cache: \(error.localizedDescription)")
        }
    }
    
    /// Get the URL for the cache file
    private var cacheFileURL: URL? {
        do {
            let documentsDirectory = try FileManager.default.url(
                for: .documentDirectory,
                in: .userDomainMask,
                appropriateFor: nil,
                create: true
            )
            return documentsDirectory.appendingPathComponent(cacheFileName)
        } catch {
            print("WordCollocationService: Error getting documents directory: \(error.localizedDescription)")
            return nil
        }
    }
    
    /// Extract JSON from text returned by LLM with improved error handling
    private func extractJsonFromText(_ text: String) -> Data {
        // Try to find JSON content between curly braces
        if let jsonStartIndex = text.firstIndex(of: "{"),
           let jsonEndIndex = text.lastIndex(of: "}") {
            let jsonSubstring = text[jsonStartIndex...jsonEndIndex]
            var jsonString = String(jsonSubstring)
            
            // Clean up the string
            jsonString = jsonString.replacingOccurrences(of: "\\n", with: " ")
            jsonString = jsonString.replacingOccurrences(of: "\\", with: "")
            
            // Fix common issues that might occur with LLM responses
            // If the response has missing commas between properties
            jsonString = jsonString.replacingOccurrences(of: "\"chunck\":\"", with: "\"chunck\":\"")
            jsonString = jsonString.replacingOccurrences(of: "\"\"chunckChinese\":\"", with: "\",\"chunckChinese\":\"")
            jsonString = jsonString.replacingOccurrences(of: "\"\"chunckSentence\":\"", with: "\",\"chunckSentence\":\"")
            
            // Log the cleaned JSON for debugging
            print("WordCollocationService: Extracted JSON: \(jsonString)")
            
            return jsonString.data(using: .utf8) ?? Data()
        }
        
        // Try to manually construct a JSON if we couldn't find a valid JSON object
        if text.contains("chunck") && text.contains("chunckChinese") {
            // Attempt to extract data in a different way
            print("WordCollocationService: Attempting manual JSON extraction from: \(text)")
            
            // Create a basic JSON structure
            let wordMatch = text.range(of: "word\":\\s*\"([^\"]*)\"", options: .regularExpression)
            let word = wordMatch != nil ? String(text[wordMatch!]) : "unknown"
            
            var jsonString = """
            {
                "word": "\(word)",
                "chunks": [
            """
            
            // Extract chunk patterns
            let chunkPattern = "chunck\":\\s*\"([^\"]*)\".*?chunckChinese\":\\s*\"([^\"]*)\".*?chunckSentence\":\\s*\"([^\"]*)\"" 
            let regex = try? NSRegularExpression(pattern: chunkPattern, options: .dotMatchesLineSeparators)
            
            if let regex = regex {
                let matches = regex.matches(in: text, options: [], range: NSRange(text.startIndex..., in: text))
                for (index, match) in matches.enumerated() {
                    if let chunkRange = Range(match.range(at: 1), in: text),
                       let chineseRange = Range(match.range(at: 2), in: text),
                       let sentenceRange = Range(match.range(at: 3), in: text) {
                        
                        let chunk = String(text[chunkRange])
                        let chinese = String(text[chineseRange])
                        let sentence = String(text[sentenceRange])
                        
                        jsonString += """
                            {
                                "chunck": "\(chunk)",
                                "chunckChinese": "\(chinese)",
                                "chunckSentence": "\(sentence)"
                            }
                        """
                        
                        if index < matches.count - 1 {
                            jsonString += ","
                        }
                    }
                }
            }
            
            jsonString += "]}"
            print("WordCollocationService: Manually constructed JSON: \(jsonString)")
            
            return jsonString.data(using: .utf8) ?? Data()
        }
        
        print("WordCollocationService: Could not extract JSON from: \(text)")
        return Data()
    }
    
    /// Clear the cache for a specific word
    func clearCache(for word: String? = nil) {
        if let word = word {
            collocationsCache.removeValue(forKey: word.lowercased())
        } else {
            collocationsCache.removeAll()
        }
        saveCacheToDisk()
    }
} 
