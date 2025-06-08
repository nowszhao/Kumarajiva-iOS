import Foundation
import Combine

class PodcastDataService: ObservableObject {
    static let shared = PodcastDataService()
    
    @Published var podcasts: [Podcast] = []
    @Published var isLoading = false
    @Published var errorMessage: String?
    
    private let rssParser = RSSParserService.shared
    private var cancellables = Set<AnyCancellable>()
    
    // 持久化存储管理器
    private let persistentStorage = PersistentStorageManager.shared
    
    // 移除UserDefaults存储键，改用持久化存储
    
    // 字幕缓存，避免频繁更新主数据触发UI刷新
    private var subtitleCache: [String: [Subtitle]] = [:]
    
    private var updateTask: Task<Void, Never>?
    
    init() {
        print("🎧 [Data] PodcastDataService 初始化开始")
        
        // 检查存储状态
        persistentStorage.checkStorageStatus()
        
        // 直接在主线程同步加载数据，确保初始化完成时数据已可用
        loadPodcasts()
        loadSubtitleCache()
        
        print("🎧 [Data] PodcastDataService 初始化完成，播客数量: \(podcasts.count)")
        
        // 执行启动诊断
        startupDiagnostics()
        
        // 异步验证数据完整性（不影响初始化）
        DispatchQueue.main.async { [weak self] in
            Task {
                await self?.validateAndRepairData()
            }
        }
    }
    
    // MARK: - 公共方法
    
    /// 添加播客
    func addPodcast(rssURL: String) async throws {
        print("🎧 [Data] 添加播客: \(rssURL)")
        
        await MainActor.run {
            self.isLoading = true
            self.errorMessage = nil
        }
        
        do {
            // 检查是否已存在
            if podcasts.contains(where: { $0.rssURL == rssURL }) {
                throw PodcastError.alreadyExists
            }
            
            // 解析RSS
            let result = try await rssParser.parsePodcastRSS(from: rssURL)
            
            await MainActor.run {
                // 先添加到内存数组
                self.podcasts.append(result.podcast)
                print("🎧 [Data] 播客已添加到内存，当前总数: \(self.podcasts.count)")
                
                // 然后保存到持久化存储
                self.savePodcastsToPersistentStorage()
                
                self.isLoading = false
            }
            
            print("🎧 [Data] 播客添加成功: \(result.podcast.title)")
            
        } catch {
            await MainActor.run {
                self.isLoading = false
                self.errorMessage = error.localizedDescription
            }
            throw error
        }
    }
    
    /// 删除播客
    func deletePodcast(_ podcast: Podcast) throws {
        print("🎧 [Data] 删除播客: \(podcast.title)")
        
        // 从内存中删除
        podcasts.removeAll { $0.id == podcast.id }
        
        // 保存到持久化存储
        savePodcastsToPersistentStorage()
        
        print("🎧 [Data] 播客删除成功")
    }
    
    /// 更新播客节目列表
    func refreshPodcast(_ podcast: Podcast) async throws {
        print("🎧 [Data] 刷新播客: \(podcast.title)")
        
        await MainActor.run {
            self.isLoading = true
        }
        
        do {
            let result = try await rssParser.parsePodcastRSS(from: podcast.rssURL)
            
            // 调试：打印现有节目信息
            print("🎧 [Debug] 现有播客中的节目:")
            for (index, episode) in podcast.episodes.enumerated() {
                print("🎧 [Debug] 节目 \(index): \(episode.title)")
                print("🎧 [Debug] 节目ID: \(episode.id)")
                print("🎧 [Debug] 音频URL: \(episode.audioURL)")
                print("🎧 [Debug] 字幕数量: \(episode.subtitles.count)")
                if index >= 2 { // 只打印前3个节目，避免日志过长
                    print("🎧 [Debug] ... (还有 \(podcast.episodes.count - 3) 个节目)")
                    break
                }
            }
            
            // 更新播客信息，但保留现有节目的字幕数据
            var updatedPodcast = podcast
            var mergedEpisodes: [PodcastEpisode] = []
            
            // 为每个新解析的节目，检查是否已存在，如果存在则保留字幕数据
            for newEpisode in result.episodes {
                print("🎧 [Debug] 检查新节目: \(newEpisode.title)")
                print("🎧 [Debug] 新节目ID: \(newEpisode.id)")
                print("🎧 [Debug] 新节目音频URL: \(newEpisode.audioURL)")
                
                // 尝试通过ID匹配
                var existingEpisode = podcast.episodes.first(where: { $0.id == newEpisode.id })
                
                if existingEpisode != nil {
                    print("🎧 [Debug] 通过ID匹配到现有节目")
                } else {
                    print("🎧 [Debug] ID匹配失败，尝试音频URL匹配")
                    // 如果ID匹配失败，尝试通过音频URL匹配（兼容旧数据）
                    existingEpisode = podcast.episodes.first(where: { $0.audioURL == newEpisode.audioURL })
                    if existingEpisode != nil {
                        print("🎧 [Debug] 通过音频URL匹配到现有节目")
                        print("🎧 [Debug] 现有节目ID: \(existingEpisode!.id)")
                    } else {
                        print("🎧 [Debug] 音频URL匹配也失败")
                    }
                }
                
                if let existing = existingEpisode {
                    // 节目已存在，保留字幕数据，但更新其他信息
                    var mergedEpisode = newEpisode
                    mergedEpisode.subtitles = existing.subtitles
                    mergedEpisode.subtitleGenerationDate = existing.subtitleGenerationDate
                    mergedEpisode.subtitleVersion = existing.subtitleVersion
                    mergedEpisodes.append(mergedEpisode)
                    print("🎧 [Data] 保留节目字幕: \(newEpisode.title)，字幕数量: \(existing.subtitles.count)")
                    
                    // 检查字幕缓存
                    if let cachedSubtitles = subtitleCache[existing.id] {
                        print("🎧 [Debug] 缓存中找到字幕: \(cachedSubtitles.count) 条")
                        mergedEpisode.subtitles = cachedSubtitles
                    } else {
                        print("🎧 [Debug] 缓存中没有找到字幕")
                    }
                } else {
                    // 新节目，直接添加
                    mergedEpisodes.append(newEpisode)
                    print("🎧 [Data] 新节目: \(newEpisode.title)")
                }
            }
            
            updatedPodcast.episodes = mergedEpisodes
            
            // 在主线程中更新数据和缓存
            await MainActor.run {
                // 同时更新字幕缓存，确保缓存和主数据一致
                for episode in mergedEpisodes {
                    if !episode.subtitles.isEmpty {
                        self.subtitleCache[episode.id] = episode.subtitles
                    }
                }
                
                // 更新内存中的数据
                if let index = self.podcasts.firstIndex(where: { $0.id == podcast.id }) {
                    self.podcasts[index] = updatedPodcast
                }
                
                self.isLoading = false
                
                // 保存到持久化存储
                self.savePodcastsToPersistentStorage()
            }
            
            let preservedSubtitlesCount = mergedEpisodes.filter { !$0.subtitles.isEmpty }.count
            print("🎧 [Data] 播客刷新成功，获得 \(result.episodes.count) 个节目，保留了 \(preservedSubtitlesCount) 个节目的字幕")
            
            // 调试：检查字幕缓存状态
            debugSubtitleCache()
            
        } catch {
            await MainActor.run {
                self.isLoading = false
                self.errorMessage = error.localizedDescription
            }
            throw error
        }
    }
    
    /// 获取播客的所有节目
    func getEpisodes(for podcast: Podcast) -> [PodcastEpisode] {
        // 首先从主数据中获取最新的播客信息
        guard let currentPodcast = podcasts.first(where: { $0.id == podcast.id }) else {
        return podcast.episodes.sorted { $0.publishDate > $1.publishDate }
        }
        
        // 合并缓存中的字幕数据到节目中
        var episodesWithLatestSubtitles = currentPodcast.episodes
        for (index, episode) in episodesWithLatestSubtitles.enumerated() {
            if let cachedSubtitles = subtitleCache[episode.id] {
                episodesWithLatestSubtitles[index].subtitles = cachedSubtitles
            }
        }
        
        return episodesWithLatestSubtitles.sorted { $0.publishDate > $1.publishDate }
    }
    
    /// 根据ID获取单个节目
    func getEpisode(by episodeId: String) -> PodcastEpisode? {
        // 遍历所有播客查找节目
        for podcast in podcasts {
            for episode in podcast.episodes {
                if episode.id == episodeId {
                    // 如果缓存中有最新字幕，使用缓存中的
                    var updatedEpisode = episode
                    if let cachedSubtitles = subtitleCache[episodeId] {
                        updatedEpisode.subtitles = cachedSubtitles
                    }
                    return updatedEpisode
                }
            }
        }
        return nil
    }
    
    /// 更新节目的字幕
    func updateEpisodeSubtitles(_ episodeId: String, subtitles: [Subtitle]) async {
        await updateEpisodeSubtitlesWithMetadata(episodeId, subtitles: subtitles, generationDate: nil, version: nil)
    }
    
    /// 只更新字幕缓存，不触发UI更新
    func updateEpisodeSubtitlesCache(_ episodeId: String, subtitles: [Subtitle]) async {
        await MainActor.run {
            self.subtitleCache[episodeId] = subtitles
            print("🎧 [Data] 字幕已更新到缓存: \(episodeId)，共 \(subtitles.count) 条")
            
            // 立即保存字幕缓存到持久化存储
            Task {
                do {
                    try self.persistentStorage.saveSubtitleCache(self.subtitleCache)
                    print("🎧 [Data] 字幕缓存已保存到持久化存储")
                } catch {
                    print("🎧 [Data] 保存字幕缓存到持久化存储失败: \(error)")
                }
            }
        }
    }
    
    /// 更新节目的字幕（包含元数据）
    func updateEpisodeSubtitlesWithMetadata(_ episodeId: String, subtitles: [Subtitle], generationDate: Date?, version: String?) async {
        print("🎧 [Data] 更新节目字幕: \(episodeId)")
        
        await MainActor.run {
            // 先更新缓存，立即可用
            self.subtitleCache[episodeId] = subtitles
        }
        
        // 取消之前的更新任务，避免重复更新
        updateTask?.cancel()
        
        updateTask = Task { @MainActor in
            // 延迟更长时间，确保用户已经离开播放页面
            try? await Task.sleep(nanoseconds: 10_000_000_000) // 10秒延迟
            
            guard !Task.isCancelled else { 
                print("🎧 [Data] 数据更新任务被取消")
                return 
            }
            
            print("🎧 [Data] 开始延迟更新主数据...")
            
                // 查找并更新对应的节目
                for (podcastIndex, podcast) in self.podcasts.enumerated() {
                    for (episodeIndex, episode) in podcast.episodes.enumerated() {
                        if episode.id == episodeId {
                            // 创建更新后的节目
                            var updatedEpisode = episode
                            updatedEpisode.subtitles = subtitles
                            if let date = generationDate {
                                updatedEpisode.subtitleGenerationDate = date
                            }
                            if let ver = version {
                                updatedEpisode.subtitleVersion = ver
                            }
                            
                            // 更新播客中的节目
                            var updatedPodcast = podcast
                            updatedPodcast.episodes[episodeIndex] = updatedEpisode
                            
                            // 更新播客列表
                            self.podcasts[podcastIndex] = updatedPodcast
                            
                        // 保存到持久化存储
                        self.savePodcastsToPersistentStorage()
                            
                        print("🎧 [Data] 延迟更新完成，节目字幕更新成功，共 \(subtitles.count) 条字幕")
                            return
                    }
                }
            }
            
            print("🎧 [Data] 未找到对应的节目: \(episodeId)")
        }
    }
    
    /// 删除节目的字幕
    func deleteEpisodeSubtitles(_ episodeId: String) async {
        print("🎧 [Data] 删除节目字幕: \(episodeId)")
        
        await MainActor.run {
            // 清空缓存
            self.subtitleCache.removeValue(forKey: episodeId)
            
            // 更新主数据
            for (podcastIndex, podcast) in self.podcasts.enumerated() {
                for (episodeIndex, episode) in podcast.episodes.enumerated() {
                    if episode.id == episodeId {
                        // 创建清空字幕的节目
                        var updatedEpisode = episode
                        updatedEpisode.subtitles = []
                        updatedEpisode.subtitleGenerationDate = nil
                        updatedEpisode.subtitleVersion = nil
                        
                        // 更新播客中的节目
                        var updatedPodcast = podcast
                        updatedPodcast.episodes[episodeIndex] = updatedEpisode
                        
                        // 更新播客列表
                        self.podcasts[podcastIndex] = updatedPodcast
                        
                        // 保存到持久化存储
                        self.savePodcastsToPersistentStorage()
                        
                        print("🎧 [Data] 节目字幕删除成功")
                        return
                    }
                }
            }
            
            print("🎧 [Data] 未找到对应的节目: \(episodeId)")
        }
    }
    
    /// 获取节目的字幕
    func getEpisodeSubtitles(_ episodeId: String) -> [Subtitle] {
        // 优先从缓存获取最新字幕
        if let cachedSubtitles = subtitleCache[episodeId] {
            return cachedSubtitles
        }
        
        // 如果缓存中没有，从主数据获取
        for podcast in podcasts {
            for episode in podcast.episodes {
                if episode.id == episodeId {
                    return episode.subtitles
                }
            }
        }
        return []
    }
    
    /// 调试方法：打印字幕缓存状态
    func debugSubtitleCache() {
        print("🎧 [Debug] 字幕缓存状态:")
        print("🎧 [Debug] 缓存中共有 \(subtitleCache.count) 个节目")
        for (episodeId, subtitles) in subtitleCache {
            print("🎧 [Debug] 节目 \(episodeId): \(subtitles.count) 条字幕")
        }
        
        print("🎧 [Debug] 主数据中的字幕:")
        for podcast in podcasts {
            for episode in podcast.episodes {
                if !episode.subtitles.isEmpty {
                    print("🎧 [Debug] 主数据节目 \(episode.id): \(episode.subtitles.count) 条字幕")
                }
            }
        }
    }
    
    // MARK: - 持久化存储操作
    
    private func loadPodcasts() {
        print("🎧 [Data] 开始加载播客数据...")
        
        let loadedPodcasts = persistentStorage.loadPodcasts()
        
        // 直接设置数据，确保Published属性触发UI更新
        podcasts = loadedPodcasts
        
        print("🎧 [Data] 从持久化存储加载了 \(podcasts.count) 个播客")
        
        // 输出详细加载信息用于调试
        if podcasts.isEmpty {
            print("🎧 [Data] 警告：没有从持久化存储中加载到任何播客数据")
            print("🎧 [Data] 检查存储路径和文件是否存在")
            persistentStorage.checkStorageStatus()
        } else {
            for (index, podcast) in podcasts.enumerated() {
                print("🎧 [Data] 播客 \(index + 1): \(podcast.title) - \(podcast.episodes.count) 个节目")
            }
        }
        
        // 强制通知UI更新
        objectWillChange.send()
    }
    
    private func updatePodcast(_ podcast: Podcast) {
        if let index = podcasts.firstIndex(where: { $0.id == podcast.id }) {
            podcasts[index] = podcast
        }
        savePodcastsToPersistentStorage()
    }
    
    private func savePodcastsToPersistentStorage() {
        do {
            try persistentStorage.savePodcasts(podcasts)
            print("🎧 [Data] 播客数据已保存到持久化存储")
        } catch {
            print("🎧 [Data] 保存播客到持久化存储失败: \(error)")
            self.errorMessage = "保存播客失败"
        }
    }
    
    /// 兼容性方法：保存到UserDefaults（已弃用 - 避免4MB限制警告）
    private func savePodcastsToUserDefaults() {
        // 不再向UserDefaults写入大量数据，避免CFPreferences限制警告
        print("🎧 [Data] ⚠️  UserDefaults保存已禁用，避免4MB限制警告")
    }
    
    private func loadSubtitleCache() {
        // 首先从持久化存储加载字幕缓存
        subtitleCache = persistentStorage.loadSubtitleCache()
        
        // 如果持久化存储中没有缓存，从主数据中重建
        if subtitleCache.isEmpty {
            for podcast in podcasts {
                for episode in podcast.episodes {
                    if !episode.subtitles.isEmpty {
                        subtitleCache[episode.id] = episode.subtitles
                    }
                }
            }
            
            // 保存重建的缓存到持久化存储
            if !subtitleCache.isEmpty {
                do {
                    try persistentStorage.saveSubtitleCache(subtitleCache)
                } catch {
                    print("🎧 [Data] 保存字幕缓存失败: \(error)")
                }
            }
        }
        
        print("🎧 [Data] 字幕缓存已加载，共 \(subtitleCache.count) 个节目有字幕")
    }
    
    /// 同步字幕缓存到主数据和持久化存储（用于应用关闭前保存）
    func syncSubtitleCacheToMainData() async {
        await MainActor.run {
            var hasChanges = false
            
            for (podcastIndex, podcast) in self.podcasts.enumerated() {
                for (episodeIndex, episode) in podcast.episodes.enumerated() {
                    if let cachedSubtitles = self.subtitleCache[episode.id],
                       cachedSubtitles.count != episode.subtitles.count {
                        // 缓存中的字幕与主数据不同，需要同步
                        var updatedEpisode = episode
                        updatedEpisode.subtitles = cachedSubtitles
                        
                        var updatedPodcast = podcast
                        updatedPodcast.episodes[episodeIndex] = updatedEpisode
                        
                        self.podcasts[podcastIndex] = updatedPodcast
                        hasChanges = true
                        
                        print("🎧 [Data] 同步字幕缓存到主数据: \(episode.title)，字幕数量: \(cachedSubtitles.count)")
                    }
                }
            }
            
            if hasChanges {
                self.savePodcastsToPersistentStorage()
                print("🎧 [Data] 字幕缓存同步完成")
            }
            
            // 同时保存字幕缓存到持久化存储
            do {
                try self.persistentStorage.saveSubtitleCache(self.subtitleCache)
                print("🎧 [Data] 字幕缓存已保存到持久化存储")
            } catch {
                print("🎧 [Data] 保存字幕缓存到持久化存储失败: \(error)")
            }
        }
    }
    
    // MARK: - 数据验证和恢复
    
    /// 验证和修复数据完整性
    func validateAndRepairData() async {
        await MainActor.run {
            print("🎧 [Data] 开始验证数据完整性...")
            
            var needsRepair = false
            var repairedPodcasts: [Podcast] = []
            
            for podcast in self.podcasts {
                // 验证播客基本信息
                if podcast.title.isEmpty || podcast.rssURL.isEmpty {
                    print("🎧 [Data] 发现损坏的播客数据: \(podcast.id)")
                    needsRepair = true
                    continue
                }
                
                // 验证节目数据
                var validEpisodes: [PodcastEpisode] = []
                for episode in podcast.episodes {
                    if !episode.title.isEmpty && !episode.audioURL.isEmpty {
                        validEpisodes.append(episode)
                    } else {
                        print("🎧 [Data] 发现损坏的节目数据: \(episode.id)")
                        needsRepair = true
                    }
                }
                
                if validEpisodes.count != podcast.episodes.count {
                    var repairedPodcast = podcast
                    repairedPodcast.episodes = validEpisodes
                    repairedPodcasts.append(repairedPodcast)
                    needsRepair = true
                } else {
                    repairedPodcasts.append(podcast)
                }
            }
            
            if needsRepair {
                print("🎧 [Data] 数据需要修复，原有 \(self.podcasts.count) 个播客，修复后 \(repairedPodcasts.count) 个播客")
                self.podcasts = repairedPodcasts
                self.savePodcastsToPersistentStorage()
            } else {
                print("🎧 [Data] 数据完整性验证通过")
            }
        }
    }
    
    /// 强制重新加载数据
    func forceReloadData() async {
        await MainActor.run {
            print("🎧 [Data] 强制重新加载数据...")
            
            // 清空当前数据
            self.podcasts.removeAll()
            self.subtitleCache.removeAll()
            
            // 重新加载
            self.loadPodcasts()
            self.loadSubtitleCache()
            
            print("🎧 [Data] 数据重新加载完成，共 \(self.podcasts.count) 个播客")
        }
    }
    
    /// 启动诊断 - 检查所有可能的数据存储位置
    func startupDiagnostics() {
        print("🎧 [Diagnostics] =================== 启动诊断开始 ===================")
        
        // 1. 检查当前内存中的数据
        print("🎧 [Diagnostics] 当前内存中的播客数量: \(podcasts.count)")
        
        // 2. 检查持久化存储
        persistentStorage.checkStorageStatus()
        
        // 3. 直接检查文件系统
        let fileManager = FileManager.default
        let appSupportPath = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("LEiP")
        let podcastFile = appSupportPath.appendingPathComponent("podcasts.json")
        
        print("🎧 [Diagnostics] 播客文件路径: \(podcastFile.path)")
        print("🎧 [Diagnostics] 文件是否存在: \(fileManager.fileExists(atPath: podcastFile.path))")
        
        if fileManager.fileExists(atPath: podcastFile.path) {
            do {
                let data = try Data(contentsOf: podcastFile)
                print("🎧 [Diagnostics] 文件大小: \(data.count) 字节")
                
                let decoder = JSONDecoder()
                decoder.dateDecodingStrategy = .iso8601
                let filePodcasts = try decoder.decode([Podcast].self, from: data)
                print("🎧 [Diagnostics] 文件中的播客数量: \(filePodcasts.count)")
                
                for (index, podcast) in filePodcasts.enumerated() {
                    print("🎧 [Diagnostics] 文件播客 \(index + 1): \(podcast.title)")
                }
            } catch {
                print("🎧 [Diagnostics] 读取文件失败: \(error)")
            }
        }
        
        // 4. 检查UserDefaults
        if let userData = UserDefaults.standard.data(forKey: "SavedPodcasts") {
            do {
                let decoder = JSONDecoder()
                let userDefaultsPodcasts = try decoder.decode([Podcast].self, from: userData)
                print("🎧 [Diagnostics] UserDefaults中的播客数量: \(userDefaultsPodcasts.count)")
            } catch {
                print("🎧 [Diagnostics] UserDefaults数据解码失败: \(error)")
            }
        } else {
            print("🎧 [Diagnostics] UserDefaults中没有播客数据")
        }
        
        // 5. 检查应用支持目录的完整内容
        do {
            let contents = try fileManager.contentsOfDirectory(at: appSupportPath, includingPropertiesForKeys: nil)
            print("🎧 [Diagnostics] 应用支持目录内容:")
            for url in contents {
                let attributes = try fileManager.attributesOfItem(atPath: url.path)
                let size = attributes[.size] as? UInt64 ?? 0
                print("🎧 [Diagnostics] - \(url.lastPathComponent): \(size) 字节")
                
                // 特别检查临时文件，这可能包含实际数据
                if url.lastPathComponent == "podcasts.json.tmp" && size > 100 {
                    print("🎧 [Diagnostics] 发现临时文件包含数据，尝试恢复...")
                    Task { @MainActor in
                        await self.tryRecoverFromTempFile(tempFileURL: url)
                    }
                }
            }
        } catch {
            print("🎧 [Diagnostics] 无法读取应用支持目录: \(error)")
        }
        
        print("🎧 [Diagnostics] =================== 启动诊断结束 ===================")
    }
    
    /// 尝试从临时文件恢复数据
    private func tryRecoverFromTempFile(tempFileURL: URL) async {
        do {
            let data = try Data(contentsOf: tempFileURL)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            
            let tempPodcasts = try decoder.decode([Podcast].self, from: data)
            print("🎧 [Recovery] 临时文件中发现 \(tempPodcasts.count) 个播客")
            
            if tempPodcasts.count > 0 && podcasts.isEmpty {
                print("🎧 [Recovery] 从临时文件恢复数据...")
                
                // 更新内存数据
                podcasts = tempPodcasts
                
                // 保存到正式文件
                savePodcastsToPersistentStorage()
                
                print("🎧 [Recovery] 数据恢复成功！现在有 \(podcasts.count) 个播客")
                
                // 清理临时文件
                try? FileManager.default.removeItem(at: tempFileURL)
                print("🎧 [Recovery] 临时文件已清理")
            }
        } catch {
            print("🎧 [Recovery] 从临时文件恢复失败: \(error)")
        }
    }
}

// MARK: - 错误定义
enum PodcastError: LocalizedError {
    case alreadyExists
    case notFound
    case saveFailed
    
    var errorDescription: String? {
        switch self {
        case .alreadyExists:
            return "播客已存在"
        case .notFound:
            return "播客不存在"
        case .saveFailed:
            return "保存失败"
        }
    }
}

// MARK: - 数据存储说明
/*
 使用 UserDefaults 进行本地存储，播客数据以 JSON 格式保存
 如需更复杂的数据管理，可以后续迁移到 Core Data
 */ 
