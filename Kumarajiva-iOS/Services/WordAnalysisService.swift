import Foundation

/// 单词分析服务 - 负责智能解析结果的持久化存储
class WordAnalysisService: ObservableObject {
    static let shared = WordAnalysisService()
    
    private let userDefaults = UserDefaults.standard
    private let storageKey = "wordAnalysisCache"
    
    @Published private(set) var analysisCache: [String: WordAnalysis] = [:]
    
    private init() {
        loadCache()
    }
    
    // MARK: - Cache Management
    
    /// 从本地存储加载缓存
    private func loadCache() {
        guard let data = userDefaults.data(forKey: storageKey),
              let cache = try? JSONDecoder().decode([String: WordAnalysis].self, from: data) else {
            print("🧠 [Analysis] 未找到本地缓存或解析失败")
            return
        }
        
        analysisCache = cache
        print("🧠 [Analysis] 成功加载 \(cache.count) 个单词解析缓存")
    }
    
    /// 保存缓存到本地存储
    private func saveCache() {
        do {
            let data = try JSONEncoder().encode(analysisCache)
            userDefaults.set(data, forKey: storageKey)
            print("🧠 [Analysis] 缓存已保存，共 \(analysisCache.count) 个单词")
        } catch {
            print("🧠 [Analysis] 保存缓存失败: \(error)")
        }
    }
    
    // MARK: - Public Methods
    
    /// 获取单词的解析结果
    func getAnalysis(for word: String) -> WordAnalysis? {
        return analysisCache[word.lowercased()]
    }
    
    /// 保存单词解析结果
    func saveAnalysis(_ analysis: WordAnalysis) {
        let key = analysis.word.lowercased()
        var updatedAnalysis = analysis
        updatedAnalysis = WordAnalysis(
            word: analysis.word,
            basicInfo: analysis.basicInfo,
            splitAssociationMethod: analysis.splitAssociationMethod,
            sceneMemory: analysis.sceneMemory,
            synonymPreciseGuidance: analysis.synonymPreciseGuidance,
            createdAt: analysisCache[key]?.createdAt ?? Date(),
            updatedAt: Date()
        )
        
        analysisCache[key] = updatedAnalysis
        saveCache()
        print("🧠 [Analysis] 已保存单词 '\(analysis.word)' 的解析结果")
    }
    
    /// 删除单词解析结果
    func deleteAnalysis(for word: String) {
        let key = word.lowercased()
        analysisCache.removeValue(forKey: key)
        saveCache()
        print("🧠 [Analysis] 已删除单词 '\(word)' 的解析结果")
    }
    
    /// 检查是否有缓存的解析结果
    func hasAnalysis(for word: String) -> Bool {
        return analysisCache[word.lowercased()] != nil
    }
    
    /// 清空所有缓存
    func clearCache() {
        analysisCache.removeAll()
        userDefaults.removeObject(forKey: storageKey)
        print("🧠 [Analysis] 已清空所有解析缓存")
    }
    
    /// 获取缓存统计信息
    func getCacheStats() -> (count: Int, totalSize: String) {
        let count = analysisCache.count
        let data = (try? JSONEncoder().encode(analysisCache)) ?? Data()
        let sizeInBytes = data.count
        let sizeString = ByteCountFormatter.string(fromByteCount: Int64(sizeInBytes), countStyle: .file)
        
        return (count: count, totalSize: sizeString)
    }
} 