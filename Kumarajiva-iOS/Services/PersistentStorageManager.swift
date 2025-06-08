import Foundation

/// 持久化存储管理器 - 确保APP重装后数据依然保留
class PersistentStorageManager {
    static let shared = PersistentStorageManager()
    
    // 存储目录URLs
    private var applicationSupportURL: URL
    private let podcastDataURL: URL
    private let subtitleCacheURL: URL
    private let youtuberDataURL: URL
    
    // 存储文件名
    private let podcastsFileName = "podcasts.json"
    private let subtitleCacheFileName = "subtitle_cache.json"
    private let youtubersFileName = "youtubers.json"
    
    // MARK: - 语音练习记录存储
    
    private let speechRecordsFileName = "speech_practice_records.json"
    private var speechRecordsURL: URL {
        return applicationSupportURL.appendingPathComponent(speechRecordsFileName)
    }
    
    // MARK: - 生词本存储
    
    private let vocabulariesFileName = "vocabularies_cache.json"
    private var vocabulariesURL: URL {
        return applicationSupportURL.appendingPathComponent(vocabulariesFileName)
    }
    
    // MARK: - 播放记录存储
    
    private let playbackRecordsFileName = "playback_records.json"
    private var playbackRecordsURL: URL {
        return applicationSupportURL.appendingPathComponent(playbackRecordsFileName)
    }
    
    private init() {
        // 获取应用程序支持目录 - 这个目录在APP重装后会保留
        let fileManager = FileManager.default
        
        // 创建应用程序支持目录
        do {
            applicationSupportURL = try fileManager.url(
                for: .applicationSupportDirectory,
                in: .userDomainMask,
                appropriateFor: nil,
                create: true
            ).appendingPathComponent("LEiP", isDirectory: true)
            
            // 创建Kumarajiva子目录
            if !fileManager.fileExists(atPath: applicationSupportURL.path) {
                try fileManager.createDirectory(
                    at: applicationSupportURL,
                    withIntermediateDirectories: true,
                    attributes: nil
                )
                
                // 设置为不排除iCloud备份，确保数据会被备份
                var resourceValues = URLResourceValues()
                resourceValues.isExcludedFromBackup = false
                try applicationSupportURL.setResourceValues(resourceValues)
                
                print("🎧 [Storage] 创建应用程序支持目录: \(applicationSupportURL.path)")
            }
            
            // 设置文件路径
            podcastDataURL = applicationSupportURL.appendingPathComponent(podcastsFileName)
            subtitleCacheURL = applicationSupportURL.appendingPathComponent(subtitleCacheFileName)
            youtuberDataURL = applicationSupportURL.appendingPathComponent(youtubersFileName)
            
            print("🎧 [Storage] 持久化存储初始化完成")
            print("🎧 [Storage] 播客数据路径: \(podcastDataURL.path)")
            print("🎧 [Storage] 字幕缓存路径: \(subtitleCacheURL.path)")
            print("📺 [Storage] YouTuber数据路径: \(youtuberDataURL.path)")
            
        } catch {
            // 如果无法创建应用程序支持目录，回退到文档目录
            print("🎧 [Storage] 无法创建应用程序支持目录，回退到文档目录: \(error)")
            
            let documentsURL = fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
            applicationSupportURL = documentsURL.appendingPathComponent("Persistent", isDirectory: true)
            
            do {
                if !fileManager.fileExists(atPath: applicationSupportURL.path) {
                    try fileManager.createDirectory(
                        at: applicationSupportURL,
                        withIntermediateDirectories: true,
                        attributes: nil
                    )
                    
                    // 设置为不排除iCloud备份
                    var resourceValues = URLResourceValues()
                    resourceValues.isExcludedFromBackup = false
                    try applicationSupportURL.setResourceValues(resourceValues)
                }
                
                podcastDataURL = applicationSupportURL.appendingPathComponent(podcastsFileName)
                subtitleCacheURL = applicationSupportURL.appendingPathComponent(subtitleCacheFileName)
                youtuberDataURL = applicationSupportURL.appendingPathComponent(youtubersFileName)
                
            } catch {
                fatalError("无法创建持久化存储目录: \(error)")
            }
        }
    }
    
    // MARK: - 播客数据存储
    
    /// 保存播客数据
    func savePodcasts(_ podcasts: [Podcast]) throws {
        print("🎧 [Storage] 开始保存播客数据，共 \(podcasts.count) 个播客")
        
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        
        let data = try encoder.encode(podcasts)
        
        // 创建备份文件（保存前先备份现有数据）
        if FileManager.default.fileExists(atPath: podcastDataURL.path) {
            createBackup()
        }
        
        // 保存到主文件
        try data.write(to: podcastDataURL)
        
        // 确保文件不被排除在iCloud备份之外
        var resourceValues = URLResourceValues()
        resourceValues.isExcludedFromBackup = false
        var mutableURL = podcastDataURL
        try mutableURL.setResourceValues(resourceValues)
        
        print("🎧 [Storage] 播客数据已保存到: \(podcastDataURL.path)")
        print("🎧 [Storage] 保存的数据大小: \(ByteCountFormatter.string(fromByteCount: Int64(data.count), countStyle: .file))")
        
        // 验证保存是否成功
        if let savedData = try? Data(contentsOf: podcastDataURL),
           let verifyPodcasts = try? JSONDecoder().decode([Podcast].self, from: savedData) {
            print("🎧 [Storage] 数据保存验证成功，重新读取了 \(verifyPodcasts.count) 个播客")
        } else {
            print("🎧 [Storage] 警告：数据保存验证失败")
        }
    }
    
    /// 加载播客数据
    func loadPodcasts() -> [Podcast] {
        print("🎧 [Storage] 开始加载播客数据...")
        
        do {
            // 首先尝试从新的持久化位置加载
            if FileManager.default.fileExists(atPath: podcastDataURL.path) {
                let data = try Data(contentsOf: podcastDataURL)
                let decoder = JSONDecoder()
                decoder.dateDecodingStrategy = .iso8601
                
                let podcasts = try decoder.decode([Podcast].self, from: data)
                print("🎧 [Storage] 从持久化存储加载了 \(podcasts.count) 个播客")
                
                // 验证数据完整性
                for podcast in podcasts {
                    print("🎧 [Storage] 验证播客: \(podcast.title) - \(podcast.episodes.count) 个节目")
                }
                
                return podcasts
            } else {
                print("🎧 [Storage] 持久化文件不存在，尝试从UserDefaults迁移")
            }
            
            // 如果新位置没有数据，尝试从UserDefaults迁移
            return migrateFromUserDefaults()
            
        } catch {
            print("🎧 [Storage] 加载播客数据失败: \(error)")
            
            // 尝试从备份文件恢复
            if let backupData = loadFromBackup() {
                print("🎧 [Storage] 从备份文件恢复数据成功")
                return backupData
            }
            
            // 最后尝试从UserDefaults迁移
            return migrateFromUserDefaults()
        }
    }
    
    /// 从UserDefaults迁移数据到持久化存储
    private func migrateFromUserDefaults() -> [Podcast] {
        print("🎧 [Storage] 尝试从UserDefaults迁移数据...")
        
        guard let data = UserDefaults.standard.data(forKey: "SavedPodcasts") else {
            print("🎧 [Storage] UserDefaults中没有找到播客数据")
            return []
        }
        
        do {
            let decoder = JSONDecoder()
            let podcasts = try decoder.decode([Podcast].self, from: data)
            
            // 迁移到新的持久化存储
            try savePodcasts(podcasts)
            
            // 清除UserDefaults中的旧数据（可选）
            // UserDefaults.standard.removeObject(forKey: "SavedPodcasts")
            
            print("🎧 [Storage] 成功从UserDefaults迁移了 \(podcasts.count) 个播客")
            return podcasts
            
        } catch {
            print("🎧 [Storage] UserDefaults数据迁移失败: \(error)")
            return []
        }
    }
    
    // MARK: - 字幕缓存存储
    
    /// 保存字幕缓存
    func saveSubtitleCache(_ cache: [String: [Subtitle]]) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        
        let data = try encoder.encode(cache)
        try data.write(to: subtitleCacheURL)
        
        // 确保文件不被排除在iCloud备份之外
        var resourceValues = URLResourceValues()
        resourceValues.isExcludedFromBackup = false
        var mutableCacheURL = subtitleCacheURL
        try mutableCacheURL.setResourceValues(resourceValues)
        
        print("🎧 [Storage] 字幕缓存已保存，共 \(cache.count) 个节目")
    }
    
    /// 加载字幕缓存
    func loadSubtitleCache() -> [String: [Subtitle]] {
        do {
            if FileManager.default.fileExists(atPath: subtitleCacheURL.path) {
                let data = try Data(contentsOf: subtitleCacheURL)
                let decoder = JSONDecoder()
                decoder.dateDecodingStrategy = .iso8601
                
                let cache = try decoder.decode([String: [Subtitle]].self, from: data)
                print("🎧 [Storage] 从持久化存储加载了 \(cache.count) 个节目的字幕缓存")
                return cache
            }
            
            print("🎧 [Storage] 字幕缓存文件不存在")
            return [:]
            
        } catch {
            print("🎧 [Storage] 加载字幕缓存失败: \(error)")
            return [:]
        }
    }
    
    // MARK: - YouTuber数据存储
    
    /// 保存YouTuber数据
    func saveYouTubers(_ youtubers: [YouTuber]) throws {
        print("📺 [Storage] 开始保存YouTuber数据，共 \(youtubers.count) 个YouTuber")
        
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        
        let data = try encoder.encode(youtubers)
        
        // 创建备份文件（保存前先备份现有数据）
        if FileManager.default.fileExists(atPath: youtuberDataURL.path) {
            createYouTuberBackup()
        }
        
        // 保存到主文件
        try data.write(to: youtuberDataURL)
        
        // 确保文件不被排除在iCloud备份之外
        var resourceValues = URLResourceValues()
        resourceValues.isExcludedFromBackup = false
        var mutableURL = youtuberDataURL
        try mutableURL.setResourceValues(resourceValues)
        
        print("📺 [Storage] YouTuber数据已保存到: \(youtuberDataURL.path)")
        print("📺 [Storage] 保存的数据大小: \(ByteCountFormatter.string(fromByteCount: Int64(data.count), countStyle: .file))")
        
        // 验证保存是否成功 - 使用相同的日期策略
        if let savedData = try? Data(contentsOf: youtuberDataURL) {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            
            if let verifyYouTubers = try? decoder.decode([YouTuber].self, from: savedData) {
                print("📺 [Storage] YouTuber数据保存验证成功，重新读取了 \(verifyYouTubers.count) 个YouTuber")
                
                // 验证每个YouTuber的视频数量
                for youtuber in verifyYouTubers {
                    print("📺 [Storage] 验证保存数据 - YouTuber: \(youtuber.title), 视频: \(youtuber.videos.count) 个")
                }
            } else {
                print("📺 [Storage] 警告：YouTuber数据保存验证失败 - 解码错误")
            }
        } else {
            print("📺 [Storage] 警告：YouTuber数据保存验证失败 - 读取文件错误")
        }
    }
    
    /// 加载YouTuber数据
    func loadYouTubers() throws -> [YouTuber] {
        print("📺 [Storage] 开始加载YouTuber数据...")
        
        do {
            if FileManager.default.fileExists(atPath: youtuberDataURL.path) {
                let data = try Data(contentsOf: youtuberDataURL)
                let decoder = JSONDecoder()
                decoder.dateDecodingStrategy = .iso8601
                
                let youtubers = try decoder.decode([YouTuber].self, from: data)
                print("📺 [Storage] 从持久化存储加载了 \(youtubers.count) 个YouTuber")
                
                // 验证数据完整性
                for youtuber in youtubers {
                    print("📺 [Storage] 验证YouTuber: \(youtuber.title) - \(youtuber.videos.count) 个视频")
                }
                
                return youtubers
            } else {
                print("📺 [Storage] YouTuber数据文件不存在")
                return []
            }
            
        } catch {
            print("📺 [Storage] 加载YouTuber数据失败: \(error)")
            
            // 尝试从备份文件恢复
            if let backupData = loadYouTuberFromBackup() {
                print("📺 [Storage] 从备份文件恢复YouTuber数据成功")
                return backupData
            }
            
            throw error
        }
    }
    
    // MARK: - 存储状态检查
    
    /// 检查存储目录状态
    func checkStorageStatus() {
        let fileManager = FileManager.default
        
        print("🎧 [Storage] 存储状态检查:")
        print("🎧 [Storage] 应用程序支持目录: \(applicationSupportURL.path)")
        print("🎧 [Storage] 目录存在: \(fileManager.fileExists(atPath: applicationSupportURL.path))")
        
        if fileManager.fileExists(atPath: podcastDataURL.path) {
            do {
                let attributes = try fileManager.attributesOfItem(atPath: podcastDataURL.path)
                let fileSize = attributes[.size] as? UInt64 ?? 0
                let modificationDate = attributes[.modificationDate] as? Date
                print("🎧 [Storage] 播客数据文件: \(ByteCountFormatter.string(fromByteCount: Int64(fileSize), countStyle: .file))")
                print("🎧 [Storage] 最后修改: \(modificationDate?.description ?? "未知")")
            } catch {
                print("🎧 [Storage] 无法获取播客数据文件属性: \(error)")
            }
        } else {
            print("🎧 [Storage] 播客数据文件不存在")
        }
        
        if fileManager.fileExists(atPath: subtitleCacheURL.path) {
            do {
                let attributes = try fileManager.attributesOfItem(atPath: subtitleCacheURL.path)
                let fileSize = attributes[.size] as? UInt64 ?? 0
                let modificationDate = attributes[.modificationDate] as? Date
                print("🎧 [Storage] 字幕缓存文件: \(ByteCountFormatter.string(fromByteCount: Int64(fileSize), countStyle: .file))")
                print("🎧 [Storage] 最后修改: \(modificationDate?.description ?? "未知")")
            } catch {
                print("🎧 [Storage] 无法获取字幕缓存文件属性: \(error)")
            }
        } else {
            print("🎧 [Storage] 字幕缓存文件不存在")
        }
    }
    
    /// 清除所有存储数据（用于测试或重置）
    func clearAllData() throws {
        let fileManager = FileManager.default
        
        if fileManager.fileExists(atPath: podcastDataURL.path) {
            try fileManager.removeItem(at: podcastDataURL)
            print("🎧 [Storage] 播客数据文件已删除")
        }
        
        if fileManager.fileExists(atPath: subtitleCacheURL.path) {
            try fileManager.removeItem(at: subtitleCacheURL)
            print("🎧 [Storage] 字幕缓存文件已删除")
        }
    }
    
    /// 获取存储目录大小
    func getStorageSize() -> Int64 {
        let fileManager = FileManager.default
        var totalSize: Int64 = 0
        
        do {
            let contents = try fileManager.contentsOfDirectory(at: applicationSupportURL, includingPropertiesForKeys: [.fileSizeKey])
            
            for url in contents {
                let attributes = try fileManager.attributesOfItem(atPath: url.path)
                if let fileSize = attributes[.size] as? UInt64 {
                    totalSize += Int64(fileSize)
                }
            }
        } catch {
            print("🎧 [Storage] 计算存储大小失败: \(error)")
        }
        
        return totalSize
    }
    
    // MARK: - 备份和恢复机制
    
    private var backupPodcastDataURL: URL {
        return applicationSupportURL.appendingPathComponent("podcasts_backup.json")
    }
    
    private var backupYouTuberDataURL: URL {
        return applicationSupportURL.appendingPathComponent("youtubers_backup.json")
    }
    
    /// 创建数据备份
    private func createBackup() {
        do {
            if FileManager.default.fileExists(atPath: podcastDataURL.path) {
                // 如果备份文件已存在，先删除
                if FileManager.default.fileExists(atPath: backupPodcastDataURL.path) {
                    try FileManager.default.removeItem(at: backupPodcastDataURL)
                    print("🎧 [Storage] 删除已存在的备份文件")
                }
                
                try FileManager.default.copyItem(at: podcastDataURL, to: backupPodcastDataURL)
                print("🎧 [Storage] 数据备份创建成功")
            }
        } catch {
            print("🎧 [Storage] 创建备份失败: \(error)")
        }
    }
    
    /// 创建YouTuber数据备份
    private func createYouTuberBackup() {
        do {
            if FileManager.default.fileExists(atPath: youtuberDataURL.path) {
                // 如果备份文件已存在，先删除
                if FileManager.default.fileExists(atPath: backupYouTuberDataURL.path) {
                    try FileManager.default.removeItem(at: backupYouTuberDataURL)
                    print("📺 [Storage] 删除已存在的YouTuber备份文件")
                }
                
                try FileManager.default.copyItem(at: youtuberDataURL, to: backupYouTuberDataURL)
                print("📺 [Storage] YouTuber数据备份创建成功")
            }
        } catch {
            print("📺 [Storage] 创建YouTuber备份失败: \(error)")
        }
    }
    
    /// 从备份文件恢复数据
    private func loadFromBackup() -> [Podcast]? {
        do {
            if FileManager.default.fileExists(atPath: backupPodcastDataURL.path) {
                let data = try Data(contentsOf: backupPodcastDataURL)
                let decoder = JSONDecoder()
                decoder.dateDecodingStrategy = .iso8601
                
                let podcasts = try decoder.decode([Podcast].self, from: data)
                print("🎧 [Storage] 从备份文件恢复了 \(podcasts.count) 个播客")
                
                // 恢复成功后，将备份数据复制回主文件
                if FileManager.default.fileExists(atPath: podcastDataURL.path) {
                    try FileManager.default.removeItem(at: podcastDataURL)
                    print("🎧 [Storage] 删除损坏的主文件")
                }
                
                try FileManager.default.copyItem(at: backupPodcastDataURL, to: podcastDataURL)
                print("🎧 [Storage] 备份数据已恢复到主文件")
                
                return podcasts
            }
        } catch {
            print("🎧 [Storage] 从备份恢复失败: \(error)")
        }
        
        return nil
    }
    
    /// 从备份文件恢复YouTuber数据
    private func loadYouTuberFromBackup() -> [YouTuber]? {
        do {
            if FileManager.default.fileExists(atPath: backupYouTuberDataURL.path) {
                let data = try Data(contentsOf: backupYouTuberDataURL)
                let decoder = JSONDecoder()
                decoder.dateDecodingStrategy = .iso8601
                
                let youtubers = try decoder.decode([YouTuber].self, from: data)
                print("📺 [Storage] 从备份文件恢复了 \(youtubers.count) 个YouTuber")
                
                // 恢复成功后，将备份数据复制回主文件
                if FileManager.default.fileExists(atPath: youtuberDataURL.path) {
                    try FileManager.default.removeItem(at: youtuberDataURL)
                    print("📺 [Storage] 删除损坏的YouTuber主文件")
                }
                
                try FileManager.default.copyItem(at: backupYouTuberDataURL, to: youtuberDataURL)
                print("📺 [Storage] YouTuber备份数据已恢复到主文件")
                
                return youtubers
            }
        } catch {
            print("📺 [Storage] 从YouTuber备份恢复失败: \(error)")
        }
        
        return nil
    }
    
    /// 强制保存数据（应用退出时调用）
    func forceSave(_ podcasts: [Podcast]) {
        do {
            try savePodcasts(podcasts)
            // 不再保存到UserDefaults，避免4MB限制警告
            print("🎧 [Storage] 强制保存完成，数据已保存到持久化文件")
        } catch {
            print("🎧 [Storage] 强制保存失败: \(error)")
        }
    }
    
    /// 保存语音练习记录
    func saveSpeechPracticeRecords(_ records: [SpeechPracticeRecord]) throws {
        print("🎤 [Storage] 开始保存语音练习记录，共 \(records.count) 条记录")
        
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        
        let data = try encoder.encode(records)
        try data.write(to: speechRecordsURL)
        
        // 确保文件不被排除在iCloud备份之外
        var resourceValues = URLResourceValues()
        resourceValues.isExcludedFromBackup = false
        var mutableURL = speechRecordsURL
        try mutableURL.setResourceValues(resourceValues)
        
        print("🎤 [Storage] 语音练习记录已保存")
    }
    
    /// 加载语音练习记录
    func loadSpeechPracticeRecords() throws -> [SpeechPracticeRecord] {
        print("🎤 [Storage] 开始加载语音练习记录...")
        
        if FileManager.default.fileExists(atPath: speechRecordsURL.path) {
            let data = try Data(contentsOf: speechRecordsURL)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            
            let records = try decoder.decode([SpeechPracticeRecord].self, from: data)
            print("🎤 [Storage] 从持久化存储加载了 \(records.count) 条语音练习记录")
            return records
        } else {
            print("🎤 [Storage] 语音练习记录文件不存在")
            return []
        }
    }
    
    /// 保存生词本缓存
    func saveVocabulariesCache<T: Codable>(_ vocabularies: T) throws {
        print("📚 [Storage] 开始保存生词本缓存")
        
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        
        let data = try encoder.encode(vocabularies)
        try data.write(to: vocabulariesURL)
        
        // 确保文件不被排除在iCloud备份之外
        var resourceValues = URLResourceValues()
        resourceValues.isExcludedFromBackup = false
        var mutableURL = vocabulariesURL
        try mutableURL.setResourceValues(resourceValues)
        
        print("📚 [Storage] 生词本缓存已保存，大小: \(ByteCountFormatter.string(fromByteCount: Int64(data.count), countStyle: .file))")
    }
    
    /// 加载生词本缓存
    func loadVocabulariesCache<T: Codable>(_ type: T.Type) throws -> T? {
        print("📚 [Storage] 开始加载生词本缓存...")
        
        if FileManager.default.fileExists(atPath: vocabulariesURL.path) {
            let data = try Data(contentsOf: vocabulariesURL)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            
            let vocabularies = try decoder.decode(type, from: data)
            print("📚 [Storage] 从持久化存储加载生词本缓存成功")
            return vocabularies
        } else {
            print("📚 [Storage] 生词本缓存文件不存在")
            return nil
        }
    }
    
    /// 保存播放记录
    func savePlaybackRecords<T: Codable>(_ records: T) throws {
        print("🎵 [Storage] 开始保存播放记录")
        
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        
        let data = try encoder.encode(records)
        try data.write(to: playbackRecordsURL)
        
        // 确保文件不被排除在iCloud备份之外
        var resourceValues = URLResourceValues()
        resourceValues.isExcludedFromBackup = false
        var mutableURL = playbackRecordsURL
        try mutableURL.setResourceValues(resourceValues)
        
        print("🎵 [Storage] 播放记录已保存")
    }
    
    /// 加载播放记录
    func loadPlaybackRecords<T: Codable>(_ type: T.Type) throws -> T? {
        print("🎵 [Storage] 开始加载播放记录...")
        
        if FileManager.default.fileExists(atPath: playbackRecordsURL.path) {
            let data = try Data(contentsOf: playbackRecordsURL)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            
            let records = try decoder.decode(type, from: data)
            print("🎵 [Storage] 从持久化存储加载播放记录成功")
            return records
        } else {
            print("🎵 [Storage] 播放记录文件不存在")
            return nil
        }
    }
    
    // MARK: - UserDefaults清理工具
    
    /// 清理UserDefaults中的大数据，避免4MB限制警告
    func cleanupUserDefaultsLargeData() {
        let keysToClean = [
            "SavedPodcasts",
            "speechPracticeRecords", 
            "podcast_playback_records",
            "vocabularies_cache_v2"  // VocabularyViewModel中的cacheKey
        ]
        
        var totalSizeFreed: Int64 = 0
        
        for key in keysToClean {
            if let data = UserDefaults.standard.data(forKey: key) {
                let size = Int64(data.count)
                totalSizeFreed += size
                
                print("🧹 [Cleanup] 清理UserDefaults键: \(key), 大小: \(ByteCountFormatter.string(fromByteCount: size, countStyle: .file))")
                UserDefaults.standard.removeObject(forKey: key)
            }
        }
        
        if totalSizeFreed > 0 {
            UserDefaults.standard.synchronize()
            print("🧹 [Cleanup] UserDefaults清理完成，释放空间: \(ByteCountFormatter.string(fromByteCount: totalSizeFreed, countStyle: .file))")
            print("🧹 [Cleanup] 这将解决CFPreferences 4MB限制警告问题")
        } else {
            print("🧹 [Cleanup] UserDefaults中没有发现大数据需要清理")
        }
    }
    
    /// 检查UserDefaults中的大数据
    func checkUserDefaultsLargeData() {
        let keysToCheck = [
            "SavedPodcasts",
            "speechPracticeRecords", 
            "podcast_playback_records",
            "vocabularies_cache_v2"
        ]
        
        var totalSize: Int64 = 0
        var hasLargeData = false
        
        print("🔍 [Check] 检查UserDefaults中的大数据...")
        
        for key in keysToCheck {
            if let data = UserDefaults.standard.data(forKey: key) {
                let size = Int64(data.count)
                totalSize += size
                
                if size > 1024 * 1024 { // 大于1MB
                    hasLargeData = true
                    print("⚠️  [Check] 发现大数据: \(key) - \(ByteCountFormatter.string(fromByteCount: size, countStyle: .file))")
                } else {
                    print("✅ [Check] 正常数据: \(key) - \(ByteCountFormatter.string(fromByteCount: size, countStyle: .file))")
                }
            }
        }
        
        print("🔍 [Check] UserDefaults总数据大小: \(ByteCountFormatter.string(fromByteCount: totalSize, countStyle: .file))")
        
        if hasLargeData {
            print("⚠️  [Check] 发现大数据，建议调用cleanupUserDefaultsLargeData()清理")
        } else {
            print("✅ [Check] UserDefaults数据大小正常")
        }
    }
} 
