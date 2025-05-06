import Foundation

/// Service for managing speech practice recordings
class SpeechRecordService {
    static let shared = SpeechRecordService()
    
    private init() {}
    
    /// Find the highest score recording for a specific word
    /// - Parameter word: The word to find recordings for
    /// - Returns: The recording with the highest score, or nil if none exists
    func findHighestScoreRecording(for word: String) -> SpeechPracticeRecord? {
        let records = loadAllRecordsFromDisk()
        
        // Filter recordings for this specific word
        let wordRecords = records.filter { $0.word.lowercased() == word.lowercased() }
        
        // Find the recording with the highest score
        return wordRecords.max(by: { $0.score < $1.score })
    }
    
    /// Load all speech practice records from disk
    /// - Returns: Array of all speech practice records
    private func loadAllRecordsFromDisk() -> [SpeechPracticeRecord] {
        let userDefaults = UserDefaults.standard
        if let data = userDefaults.data(forKey: "speechPracticeRecords") {
            do {
                let decoder = JSONDecoder()
                return try decoder.decode([SpeechPracticeRecord].self, from: data)
            } catch {
                print("Failed to load speech practice records: \(error)")
                return []
            }
        }
        return []
    }
} 