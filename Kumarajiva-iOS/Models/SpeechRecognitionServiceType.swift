import Foundation

enum SpeechRecognitionServiceType: Int, CaseIterable {
    case nativeSpeech
    case whisperKit
    
    var title: String {
        switch self {
        case .nativeSpeech: return "系统原生识别"
        case .whisperKit: return "WhisperKit语音识别"
        }
    }
    
    var description: String {
        switch self {
        case .nativeSpeech: return "iOS系统自带语音识别"
        case .whisperKit: return "基于WhisperKit的更高精度AI语音识别"
        }
    }
}

enum WhisperModelSize: String, CaseIterable {
    case tiny = "openai_whisper-tiny.en"
    case base = "openai_whisper-base.en"
    case small = "openai_whisper-small.en_217MB"
    case large = "openai_whisper-large-v3-v20240930_turbo_632MB"
    
    var title: String {
        switch self {
        case .tiny: return "Tiny（最小）"
        case .base: return "Base（基本）"
        case .small: return "Small（小型）"
        case .large: return "Large（大型）"
        }
    }
    
    var description: String {
        switch self {
        case .tiny: return "体积最小，耗能最低，识别速度最快，准确率一般"
        case .base: return "体积较小，识别速度快，准确率尚可" 
        case .small: return "体积适中，识别速度较快，准确率良好"
        case .large: return "体积最大，识别速度最慢，准确率最高"
        }
    }
    
    var modelSize: Int {
        switch self {
        case .tiny: return 75    // 约75MB
        case .base: return 142   // 约142MB
        case .small: return 217  // 约476MB
        case .large: return 632 // 约3GB
        }
    }
} 
