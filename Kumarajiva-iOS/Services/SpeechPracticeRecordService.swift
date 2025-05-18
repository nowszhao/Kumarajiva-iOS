//
//  SpeechPracticeRecordService.swift
//  Kumarajiva-iOS
//
//  Created by AI Assistant on 2023-11-15.
//

import Foundation

class SpeechPracticeRecordService {
    static let shared = SpeechPracticeRecordService()
    
    private(set) var records: [SpeechPracticeRecord] = []
    private(set) var recordsByWord: [String: [SpeechPracticeRecord]] = [:]
    private(set) var countByWord: [String: Int] = [:]
    private(set) var highestScoreByWord: [String: Int] = [:]
    
    private init() {
        loadRecords()
    }
    
    func loadRecords() {
        let userDefaults = UserDefaults.standard
        guard let data = userDefaults.data(forKey: "speechPracticeRecords") else {
            records = []
            updateCaches()
            return
        }
        
        do {
            let decoder = JSONDecoder()
            let savedRecords = try decoder.decode([SpeechPracticeRecord].self, from: data)
            
            // 过滤掉无效的记录
            records = savedRecords.filter { record in
                FileManager.default.fileExists(atPath: record.audioURL.path)
            }
            
            updateCaches()
        } catch {
            print("加载语音练习记录失败: \(error)")
            records = []
            updateCaches()
        }
    }
    
    private func updateCaches() {
        // 更新按单词分组的缓存
        recordsByWord = Dictionary(grouping: records) { $0.word }
        
        // 更新每个单词的记录数量
        countByWord = recordsByWord.mapValues { $0.count }
        
        // 更新每个单词的最高分数
        highestScoreByWord = recordsByWord.mapValues { records in
            records.map { $0.score }.max() ?? 0
        }
    }
    
    func getRecordsForWord(_ word: String) -> [SpeechPracticeRecord] {
        return recordsByWord[word] ?? []
    }
    
    func getRecordCount(forWord word: String) -> Int {
        return countByWord[word] ?? 0
    }
    
    func getHighestScore(forWord word: String) -> Int {
        return highestScoreByWord[word] ?? 0
    }
    
    func addRecord(_ record: SpeechPracticeRecord) {
        records.insert(record, at: 0)
        saveRecords()
    }
    
    func deleteRecord(id: UUID) {
        guard let index = records.firstIndex(where: { $0.id == id }) else { return }
        
        let record = records[index]
        
        // 删除文件
        do {
            try FileManager.default.removeItem(at: record.audioURL)
        } catch {
            print("删除录音文件失败: \(error)")
        }
        
        // 从记录中移除
        records.remove(at: index)
        saveRecords()
    }
    
    func deleteAllRecordsForWord(_ word: String) {
        let recordsToDelete = records.filter { $0.word == word }
        
        // 删除文件
        for record in recordsToDelete {
            do {
                try FileManager.default.removeItem(at: record.audioURL)
            } catch {
                print("删除录音文件失败: \(error)")
            }
        }
        
        // 从记录中移除
        records.removeAll { $0.word == word }
        saveRecords()
    }
    
    private func saveRecords() {
        do {
            let encoder = JSONEncoder()
            let data = try encoder.encode(records)
            UserDefaults.standard.set(data, forKey: "speechPracticeRecords")
            
            // 更新缓存
            updateCaches()
        } catch {
            print("保存语音练习记录失败: \(error)")
        }
    }
}