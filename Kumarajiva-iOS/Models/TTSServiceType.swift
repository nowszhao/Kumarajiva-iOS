import Foundation

enum TTSServiceType: Int, CaseIterable {
    case edgeTTS
    case youdaoTTS
    
    var title: String {
        switch self {
        case .edgeTTS: return "Edge TTS"
        case .youdaoTTS: return "有道 TTS"
        }
    }
    
    var description: String {
        switch self {
        case .edgeTTS: return "微软 Edge 语音服务"
        case .youdaoTTS: return "有道词典语音服务"
        }
    }
} 