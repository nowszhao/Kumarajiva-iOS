import Foundation
import SwiftUI

@MainActor
class VocabularyViewModel: ObservableObject {
    // 单例实例
    static let shared = VocabularyViewModel()
    
    @Published var vocabularies: [VocabularyItem] = []
    @Published var isLoading = false
    @Published var error: String?
    @Published var isRefreshing = false
    @Published var isSyncing = false
    @Published var hasLoadedFromServer = false  // 新增：标记是否已从服务器加载过数据
    
    private let apiService = APIService.shared
    private let authService = AuthService.shared
    private let cacheKey = "cached_vocabularies"
    private let hasLoadedKey = "has_loaded_vocabularies_from_server"
    
    private init() {
        print("🏗️ VocabularyViewModel 初始化开始...")
        print("🏗️ 调用栈: \(Thread.callStackSymbols.prefix(5).joined(separator: "\n"))")
        
        // 加载缓存的数据
        loadCachedVocabularies()
        // 恢复是否已从服务器加载的状态
        hasLoadedFromServer = UserDefaults.standard.bool(forKey: hasLoadedKey)
        print("🏗️ VocabularyViewModel 单例初始化完成，缓存词汇数: \(vocabularies.count)")
        print("🏗️ hasLoadedFromServer: \(hasLoadedFromServer)")
    }
    
    // MARK: - Public Methods
    
    func loadVocabularies() async {
        print("📱 [LoadVocab] 开始加载生词数据...")
        print("📱 [LoadVocab] 当前词汇数量: \(vocabularies.count)")
        
        // 如果已有数据，不要重新加载缓存
        if !vocabularies.isEmpty {
            print("📱 [LoadVocab] 已有词汇数据，跳过缓存加载，直接从服务器获取最新数据")
            await refreshVocabularies()
            return
        }
        
        isLoading = true
        error = nil
        
        // 首先尝试从缓存加载
        loadCachedVocabularies()
        
        // 如果缓存为空，从服务器获取
        if vocabularies.isEmpty {
            print("📱 [LoadVocab] 缓存为空，从服务器获取数据...")
            await refreshVocabularies()
        } else {
            print("📱 [LoadVocab] 使用缓存数据，共 \(vocabularies.count) 个生词")
        }
        
        isLoading = false
    }
    
    func refreshVocabularies() async {
        isRefreshing = true
        error = nil
        
        do {
            print("🔄 刷新：从服务器获取最新生词数据...")
            
            // 1. 详细检查所有本地生词的状态
            print("🔍 刷新前本地生词状态检查：")
            print("  - 总词汇数: \(vocabularies.count)")
            
            let allNewlyAdded = vocabularies.filter { $0.isNewlyAdded == true }
            print("  - isNewlyAdded=true 的词汇数: \(allNewlyAdded.count)")
            allNewlyAdded.forEach { vocab in
                print("    * '\(vocab.word)': isNewlyAdded=\(vocab.isNewlyAdded ?? false), isLocallyModified=\(vocab.isLocallyModified)")
            }
            
            let allLocallyModified = vocabularies.filter { $0.isLocallyModified }
            print("  - isLocallyModified=true 的词汇数: \(allLocallyModified.count)")
            allLocallyModified.forEach { vocab in
                print("    * '\(vocab.word)': isNewlyAdded=\(vocab.isNewlyAdded ?? false), isLocallyModified=\(vocab.isLocallyModified)")
            }
            
            // 2. 保存本地未同步的新词
            let localNewWords = vocabularies.filter { $0.isNewlyAdded == true && $0.isLocallyModified }
            print("🔄 刷新：发现 \(localNewWords.count) 个本地未同步的新词，将予以保护")
            localNewWords.forEach { vocab in
                print("  - 保护词汇: '\(vocab.word)'")
            }
            
            // 3. 从服务器获取最新数据
            let fetchedVocabularies = try await apiService.getVocabularyList()
            print("🔄 刷新：从服务器获取到 \(fetchedVocabularies.count) 个生词")
            
            // 4. 智能合并：服务器数据 + 本地未同步的新词
            var mergedVocabularies = fetchedVocabularies
            
            // 添加本地未同步的新词（避免重复）
            for localWord in localNewWords {
                // 检查服务器数据中是否已存在该词
                if !mergedVocabularies.contains(where: { $0.word.lowercased() == localWord.word.lowercased() }) {
                    mergedVocabularies.append(localWord)
                    print("🔄 刷新：保护本地新词 '\(localWord.word)'")
                } else {
                    print("🔄 刷新：本地新词 '\(localWord.word)' 已在服务器中存在，移除本地标记")
                }
            }
            
            // 5. 按时间倒序排列（最新的在前）
            vocabularies = mergedVocabularies.sorted { $0.timestamp > $1.timestamp }
            
            // 更新缓存
            cacheVocabularies()
            print("💾 刷新成功，已更新本地缓存，共 \(vocabularies.count) 个生词（包含 \(localNewWords.count) 个受保护的本地新词）")
            
            // 6. 刷新后状态检查
            let newlyAddedAfterRefresh = vocabularies.filter { $0.isNewlyAdded == true }
            print("🔍 刷新后新添加词汇数: \(newlyAddedAfterRefresh.count)")
            newlyAddedAfterRefresh.forEach { vocab in
                print("  - '\(vocab.word)': isNewlyAdded=\(vocab.isNewlyAdded ?? false), isLocallyModified=\(vocab.isLocallyModified)")
            }
        } catch {
            handleError(error)
        }
        
        isRefreshing = false
    }
    
    func syncToCloud() async {
        print("🔄 [Sync] 开始同步云端...")
        isSyncing = true
        error = nil
        
        do {
            // 获取新添加的生词（而不是所有本地修改的生词）
            let newlyAddedVocabularies = vocabularies.filter { $0.isNewlyAdded == true && $0.isLocallyModified }
            print("🔄 [Sync] 找到 \(newlyAddedVocabularies.count) 个新添加的生词需要上传")
            
            if !newlyAddedVocabularies.isEmpty {
                print("🔄 [Sync] 开始上传新添加的生词...")
                let importRequest = convertToImportRequest(newlyAddedVocabularies)
                let success = try await apiService.importVocabularies(importRequest)
                
                if success {
                    print("🔄 [Sync] 上传成功，标记为已同步")
                    // 只标记新添加的生词为已同步
                    for i in vocabularies.indices {
                        if vocabularies[i].isNewlyAdded == true && vocabularies[i].isLocallyModified {
                            vocabularies[i].isLocallyModified = false
                        }
                    }
                    cacheVocabularies()
                } else {
                    error = "同步失败，请重试"
                    print("🔄 [Sync] 上传失败")
                }
            } else {
                print("🔄 [Sync] 没有新添加的生词需要上传，执行智能刷新操作...")
                // 如果没有新添加的生词，执行智能刷新操作
                await refreshVocabularies()
                print("🔄 [Sync] 智能刷新完成，共 \(vocabularies.count) 个生词")
            }
        } catch {
            print("🔄 [Sync] 同步过程中出错: \(error)")
            handleError(error)
        }
        
        isSyncing = false
        print("🔄 [Sync] 同步完成")
    }
    
    func deleteVocabulary(_ vocabulary: VocabularyItem) async {
        do {
            let success = try await apiService.deleteVocabulary(word: vocabulary.word)
            
            if success {
                vocabularies.removeAll { $0.word == vocabulary.word }
                cacheVocabularies()
                print("🗑️ 已删除生词 '\(vocabulary.word)' 并更新缓存")
            } else {
                error = "删除失败，请重试"
            }
        } catch {
            handleError(error)
        }
    }
    
    func updateVocabulary(_ vocabulary: VocabularyItem) async {
        do {
            print("🔄 [Update] 开始更新生词: \(vocabulary.word)")
            
            let success = try await apiService.updateVocabulary(vocabulary)
            
            if success {
                // 找到并更新本地列表中的词汇
                if let index = vocabularies.firstIndex(where: { $0.word == vocabulary.word }) {
                    vocabularies[index] = vocabulary
                    cacheVocabularies()
                    print("✅ 已更新生词 '\(vocabulary.word)' 并保存到缓存")
                }
            } else {
                error = "更新失败，请重试"
            }
        } catch {
            print("❌ 更新生词时出错: \(error)")
            handleError(error)
        }
    }
    
    // 清除缓存（可选方法，用于调试或设置中）
    func clearCache() {
        UserDefaults.standard.removeObject(forKey: cacheKey)
        UserDefaults.standard.removeObject(forKey: hasLoadedKey)
        hasLoadedFromServer = false
        vocabularies = []
        print("🧹 已清除生词缓存")
    }
    
    // 添加生词到本地（不同步到云端）
    func addVocabularyLocally(_ vocabulary: VocabularyItem) {
        print("🔍 [AddVocab] 开始添加生词 '\(vocabulary.word)'")
        print("🔍 [AddVocab] 添加前状态：")
        print("  - 总词汇数: \(vocabularies.count)")
        print("  - 新添加词汇数: \(vocabularies.filter { $0.isNewlyAdded == true }.count)")
        print("  - 本地修改词汇数: \(vocabularies.filter { $0.isLocallyModified }.count)")
        
        // 检查是否已存在
        if vocabularies.contains(where: { $0.word.lowercased() == vocabulary.word.lowercased() }) {
            print("⚠️ 生词 '\(vocabulary.word)' 已存在于生词库中")
            return
        }
        
        // 添加到列表开头（最新的在前）
        var newVocabulary = vocabulary
        newVocabulary.isLocallyModified = true  // 标记为本地修改
        
        // 直接在当前线程更新数据
        vocabularies.insert(newVocabulary, at: 0)
        
        print("🔍 [AddVocab] 添加后状态：")
        print("  - 总词汇数: \(vocabularies.count)")
        print("  - 新添加词汇数: \(vocabularies.filter { $0.isNewlyAdded == true }.count)")
        print("  - 本地修改词汇数: \(vocabularies.filter { $0.isLocallyModified }.count)")
        
        // 立即保存到缓存，防止页面切换时被覆盖
        cacheVocabularies()
        print("💾 [AddVocab] 已保存到缓存")
        
        // 验证缓存是否正确保存
        if let data = UserDefaults.standard.data(forKey: cacheKey),
           let cached = try? JSONDecoder().decode([VocabularyItem].self, from: data) {
            print("🔍 [AddVocab] 缓存验证：")
            print("  - 缓存中总词汇数: \(cached.count)")
            print("  - 缓存中新添加词汇数: \(cached.filter { $0.isNewlyAdded == true }.count)")
            print("  - 缓存中本地修改词汇数: \(cached.filter { $0.isLocallyModified }.count)")
            
            // 检查刚添加的词汇是否在缓存中
            if let cachedWord = cached.first(where: { $0.word.lowercased() == vocabulary.word.lowercased() }) {
                print("  - 新词在缓存中: ✅")
                print("    * isNewlyAdded: \(cachedWord.isNewlyAdded ?? false)")
                print("    * isLocallyModified: \(cachedWord.isLocallyModified)")
            } else {
                print("  - 新词在缓存中: ❌")
            }
        }
        
        // 详细调试信息
        print("✅ 已将生词 '\(vocabulary.word)' 添加到本地生词库")
        print("🔍 新添加生词详情:")
        print("  - word: \(newVocabulary.word)")
        print("  - isNewlyAdded: \(newVocabulary.isNewlyAdded ?? false)")
        print("  - isLocallyModified: \(newVocabulary.isLocallyModified)")
        print("  - timestamp: \(newVocabulary.timestamp)")
        print("  - definitions: \(newVocabulary.definitions)")
        
        // 统计信息
        let newlyAddedCount = vocabularies.filter { $0.isNewlyAdded == true }.count
        let locallyModifiedCount = vocabularies.filter { $0.isLocallyModified }.count
        print("📊 当前生词库总数: \(vocabularies.count)")
        print("📊 新添加的生词数量: \(newlyAddedCount)")
        print("📊 本地修改的生词数量: \(locallyModifiedCount)")
        print("💾 已立即保存到本地缓存")
    }
    
    // 检查生词是否已存在
    func isVocabularyCollected(_ word: String) -> Bool {
        return vocabularies.contains { $0.word.lowercased() == word.lowercased() }
    }
    
    // 检查生词是否为本地新词（可以取消收藏）
    func isVocabularyLocallyAdded(_ word: String) -> Bool {
        if let vocab = vocabularies.first(where: { $0.word.lowercased() == word.lowercased() }) {
            return vocab.isNewlyAdded == true && vocab.isLocallyModified
        }
        return false
    }
    
    // 检查生词是否为云端词汇（不可取消收藏）
    func isVocabularyFromCloud(_ word: String) -> Bool {
        if let vocab = vocabularies.first(where: { $0.word.lowercased() == word.lowercased() }) {
            return vocab.isNewlyAdded != true || !vocab.isLocallyModified
        }
        return false
    }
    
    // 取消收藏本地新词
    func removeLocalVocabulary(_ word: String) {
        print("🔍 [RemoveVocab] 开始移除本地生词 '\(word)'")
        
        // 检查是否为本地新词
        guard let vocab = vocabularies.first(where: { $0.word.lowercased() == word.lowercased() }),
              vocab.isNewlyAdded == true && vocab.isLocallyModified else {
            print("⚠️ 生词 '\(word)' 不是本地新词，无法移除")
            return
        }
        
        print("🔍 [RemoveVocab] 移除前状态：")
        print("  - 总词汇数: \(vocabularies.count)")
        print("  - 新添加词汇数: \(vocabularies.filter { $0.isNewlyAdded == true }.count)")
        print("  - 本地修改词汇数: \(vocabularies.filter { $0.isLocallyModified }.count)")
        
        // 从列表中移除
        vocabularies.removeAll { $0.word.lowercased() == word.lowercased() }
        
        print("🔍 [RemoveVocab] 移除后状态：")
        print("  - 总词汇数: \(vocabularies.count)")
        print("  - 新添加词汇数: \(vocabularies.filter { $0.isNewlyAdded == true }.count)")
        print("  - 本地修改词汇数: \(vocabularies.filter { $0.isLocallyModified }.count)")
        
        // 立即保存到缓存
        cacheVocabularies()
        print("💾 [RemoveVocab] 已保存到缓存")
        
        print("✅ 已将本地生词 '\(word)' 从生词库中移除")
    }
    
    // MARK: - Private Methods
    
    private func loadCachedVocabularies() {
        print("📱 [LoadCache] 开始加载缓存...")
        
        do {
            // 首先尝试从持久化存储加载
            if let cached = try PersistentStorageManager.shared.loadVocabulariesCache([VocabularyItem].self) {
            
            print("📱 [LoadCache] 缓存数据解码成功，原始数据：")
            print("  - 缓存中总词汇数: \(cached.count)")
            print("  - 缓存中新添加词汇数: \(cached.filter { $0.isNewlyAdded == true }.count)")
            print("  - 缓存中本地修改词汇数: \(cached.filter { $0.isLocallyModified }.count)")
            
            // 恢复本地状态：新添加的词汇应该标记为本地修改
            vocabularies = cached.map { vocab in
                var mutableVocab = vocab
                // 如果是新添加的词汇，恢复本地修改状态
                if vocab.isNewlyAdded == true {
                    mutableVocab.isLocallyModified = true
                }
                return mutableVocab
            }
            
            print("📱 [LoadCache] 状态恢复后：")
            print("  - 总词汇数: \(vocabularies.count)")
            print("  - 新添加词汇数: \(vocabularies.filter { $0.isNewlyAdded == true }.count)")
            print("  - 本地修改词汇数: \(vocabularies.filter { $0.isLocallyModified }.count)")
            
            print("📱 已从本地缓存加载 \(cached.count) 个生词")
            
            // 调试：检查恢复后的状态
            let newlyAddedCount = vocabularies.filter { $0.isNewlyAdded == true }.count
            let locallyModifiedCount = vocabularies.filter { $0.isLocallyModified }.count
            print("📱 缓存恢复状态：新添加=\(newlyAddedCount), 本地修改=\(locallyModifiedCount)")
            
            // 列出所有新添加的词汇
            let newlyAddedWords = vocabularies.filter { $0.isNewlyAdded == true }
            print("📱 [LoadCache] 新添加的词汇列表：")
            newlyAddedWords.forEach { vocab in
                print("  - '\(vocab.word)': isNewlyAdded=\(vocab.isNewlyAdded ?? false), isLocallyModified=\(vocab.isLocallyModified)")
            }
            
            return // 成功加载持久化存储，返回
        }
        } catch {
            print("📱 [LoadCache] 从持久化存储加载失败，尝试UserDefaults迁移: \(error)")
        }
        
        // 如果持久化存储失败，尝试从UserDefaults迁移
        if let data = UserDefaults.standard.data(forKey: cacheKey),
           let cached = try? JSONDecoder().decode([VocabularyItem].self, from: data) {
            
            print("📱 [LoadCache] 从UserDefaults加载缓存数据成功：")
            print("  - 缓存中总词汇数: \(cached.count)")
            print("  - 缓存中新添加词汇数: \(cached.filter { $0.isNewlyAdded == true }.count)")
            print("  - 缓存中本地修改词汇数: \(cached.filter { $0.isLocallyModified }.count)")
            
            // 恢复本地状态：新添加的词汇应该标记为本地修改
            vocabularies = cached.map { vocab in
                var mutableVocab = vocab
                // 如果是新添加的词汇，恢复本地修改状态
                if vocab.isNewlyAdded == true {
                    mutableVocab.isLocallyModified = true
                }
                return mutableVocab
            }
            
            // 迁移到持久化存储
            do {
                try PersistentStorageManager.shared.saveVocabulariesCache(vocabularies)
                print("📱 [LoadCache] 成功迁移生词缓存到持久化存储")
                // 可选择性清除UserDefaults
                // UserDefaults.standard.removeObject(forKey: cacheKey)
            } catch {
                print("📱 [LoadCache] 迁移生词缓存失败: \(error)")
            }
            
            print("📱 已从UserDefaults缓存加载 \(cached.count) 个生词")
        } else {
            print("📱 [LoadCache] 没有找到缓存数据或解码失败")
        }
    }
    
    private func cacheVocabularies() {
        do {
            try PersistentStorageManager.shared.saveVocabulariesCache(vocabularies)
        } catch {
            print("📚 [Cache] 保存生词缓存失败: \(error)")
        }
    }
    
    private func getModifiedVocabularies() -> [VocabularyItem] {
        return vocabularies.filter { $0.isLocallyModified }
    }
    
    private func convertToImportRequest(_ vocabularies: [VocabularyItem]) -> VocabularyImportRequest {
        var importData: [String: VocabularyImportData] = [:]
        
        for vocab in vocabularies {
            let importItem = VocabularyImportData(
                word: vocab.word,
                definitions: vocab.definitions,  // 直接使用数组格式
                pronunciation: vocab.pronunciation,  // 直接使用字典格式
                memoryMethod: vocab.memoryMethod,
                mastered: vocab.mastered > 0,
                timestamp: vocab.timestamp
            )
            
            importData[vocab.word] = importItem
        }
        
        return VocabularyImportRequest(vocabularies: importData)
    }
    
    private func handleError(_ error: Error) {
        if let apiError = error as? APIError, case .unauthorized = apiError {
            authService.logout()
            self.error = "登录已过期，请重新登录"
        } else {
            self.error = error.localizedDescription
        }
    }
    
    // MARK: - Computed Properties
    
    var hasModifiedVocabularies: Bool {
        vocabularies.contains { $0.isNewlyAdded == true && $0.isLocallyModified }
    }
    
    var modifiedCount: Int {
        vocabularies.filter { $0.isNewlyAdded == true && $0.isLocallyModified }.count
    }
} 