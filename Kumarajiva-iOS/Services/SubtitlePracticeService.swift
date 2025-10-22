import Foundation

/// 字幕跟读练习服务
@MainActor
class SubtitlePracticeService: ObservableObject {
    static let shared = SubtitlePracticeService()
    
    @Published var practiceStats: [String: SubtitlePracticeStats] = [:]
    
    private init() {
        loadAllStats()
    }
    
    /// 获取字幕的练习统计
    func getStats(videoId: String, subtitleId: String) -> SubtitlePracticeStats {
        let key = makeKey(videoId: videoId, subtitleId: subtitleId)
        return practiceStats[key] ?? SubtitlePracticeStats(videoId: videoId, subtitleId: subtitleId)
    }
    
    /// 添加练习记录
    func addRecord(_ record: SubtitlePracticeRecord) {
        let key = makeKey(videoId: record.videoId, subtitleId: record.subtitleId)
        var stats = practiceStats[key] ?? SubtitlePracticeStats(videoId: record.videoId, subtitleId: record.subtitleId)
        stats.addRecord(record)
        practiceStats[key] = stats
        saveAllStats()
    }
    
    /// 获取视频的所有练习记录
    func getRecords(for videoId: String) -> [SubtitlePracticeRecord] {
        return practiceStats.values
            .filter { $0.videoId == videoId }
            .flatMap { $0.records }
            .sorted { $0.timestamp > $1.timestamp }
    }
    
    /// 获取特定字幕的练习记录
    func getRecords(videoId: String, subtitleId: String) -> [SubtitlePracticeRecord] {
        let key = makeKey(videoId: videoId, subtitleId: subtitleId)
        return practiceStats[key]?.records ?? []
    }
    
    /// 删除练习记录
    func deleteRecord(id: UUID) {
        for (key, var stats) in practiceStats {
            if let index = stats.records.firstIndex(where: { $0.id == id }) {
                let record = stats.records[index]
                
                // 删除音频文件
                try? FileManager.default.removeItem(at: record.audioURL)
                
                // 从统计中移除
                stats.records.remove(at: index)
                
                // 重新计算统计数据
                if stats.records.isEmpty {
                    practiceStats.removeValue(forKey: key)
                } else {
                    stats.practiceCount = stats.records.count
                    stats.highestScore = stats.records.map { $0.score }.max() ?? 0
                    stats.averageScore = Double(stats.records.map { $0.score }.reduce(0, +)) / Double(stats.records.count)
                    practiceStats[key] = stats
                }
                
                saveAllStats()
                break
            }
        }
    }
    
    /// 清空视频的所有练习记录
    func clearRecords(for videoId: String) {
        let keysToRemove = practiceStats.keys.filter { key in
            key.hasPrefix("\(videoId)_")
        }
        
        for key in keysToRemove {
            if let stats = practiceStats[key] {
                // 删除所有音频文件
                for record in stats.records {
                    try? FileManager.default.removeItem(at: record.audioURL)
                }
            }
            practiceStats.removeValue(forKey: key)
        }
        
        saveAllStats()
    }
    
    // MARK: - Private Methods
    
    private func makeKey(videoId: String, subtitleId: String) -> String {
        return "\(videoId)_\(subtitleId)"
    }
    
    private func loadAllStats() {
        practiceStats = PersistentStorageManager.shared.loadSubtitlePracticeStats()
    }
    
    private func saveAllStats() {
        PersistentStorageManager.shared.saveSubtitlePracticeStats(practiceStats)
    }
}
