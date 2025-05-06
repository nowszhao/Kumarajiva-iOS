enum PlaybackMode: Int, CaseIterable {
    case wordOnly
    case memoryOnly 
    case wordAndMemory
    case highestScoreSpeech
    
    var title: String {
        switch self {
        case .wordOnly: return "仅播放单词"
        case .memoryOnly: return "仅播放记忆方法"
        case .wordAndMemory: return "单词+记忆方法"
        case .highestScoreSpeech: return "口语最高得分录音"
        }
    }
} 