import Foundation

/// 持久化存储管理器 - 确保APP重装后数据依然保留
class PersistentStorageManager {
    static let shared = PersistentStorageManager()
    
    // 存储目录URLs
    private var applicationSupportURL: URL
    private let podcastDataURL: URL
    private let subtitleCacheURL: URL
    
    // 存储文件名
    private let podcastsFileName = "podcasts.json"
    private let subtitleCacheFileName = "subtitle_cache.json"
    
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
            ).appendingPathComponent("Kumarajiva", isDirectory: true)
            
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
            
            print("🎧 [Storage] 持久化存储初始化完成")
            print("🎧 [Storage] 播客数据路径: \(podcastDataURL.path)")
            print("🎧 [Storage] 字幕缓存路径: \(subtitleCacheURL.path)")
            
        } catch {
            // 如果无法创建应用程序支持目录，回退到文档目录
            print("🎧 [Storage] 无法创建应用程序支持目录，回退到文档目录: \(error)")
            
            let documentsURL = fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
            applicationSupportURL = documentsURL.appendingPathComponent("KumarajivaPersistent", isDirectory: true)
            
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
                
            } catch {
                fatalError("无法创建持久化存储目录: \(error)")
            }
        }
    }
    
    // MARK: - 播客数据存储
    
    /// 保存播客数据
    func savePodcasts(_ podcasts: [Podcast]) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        
        let data = try encoder.encode(podcasts)
        try data.write(to: podcastDataURL)
        
        // 确保文件不被排除在iCloud备份之外
        var resourceValues = URLResourceValues()
        resourceValues.isExcludedFromBackup = false
        var mutableURL = podcastDataURL
        try mutableURL.setResourceValues(resourceValues)
        
        print("🎧 [Storage] 播客数据已保存到: \(podcastDataURL.path)")
    }
    
    /// 加载播客数据
    func loadPodcasts() -> [Podcast] {
        do {
            // 首先尝试从新的持久化位置加载
            if FileManager.default.fileExists(atPath: podcastDataURL.path) {
                let data = try Data(contentsOf: podcastDataURL)
                let decoder = JSONDecoder()
                decoder.dateDecodingStrategy = .iso8601
                
                let podcasts = try decoder.decode([Podcast].self, from: data)
                print("🎧 [Storage] 从持久化存储加载了 \(podcasts.count) 个播客")
                return podcasts
            }
            
            // 如果新位置没有数据，尝试从UserDefaults迁移
            return migrateFromUserDefaults()
            
        } catch {
            print("🎧 [Storage] 加载播客数据失败: \(error)")
            
            // 尝试从UserDefaults迁移
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
} 