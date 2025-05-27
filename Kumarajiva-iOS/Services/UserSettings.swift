import Foundation

class UserSettings {
    static let shared = UserSettings()
    
    private let defaults = UserDefaults.standard
    private let playbackModeKey = "playback_mode"
    private let ttsServiceTypeKey = "tts_service_type"
    private let speechRecognitionServiceTypeKey = "speech_recognition_service_type"
    private let whisperModelSizeKey = "whisper_model_size"
    private let playbackSpeedKey = "playback_speed"
    private let autoLoadWhisperModelKey = "auto_load_whisper_model"
    private let allowCellularDownloadKey = "allow_cellular_download"
    
    private init() {}
    
    var playbackMode: PlaybackMode {
        get {
            PlaybackMode(rawValue: defaults.integer(forKey: playbackModeKey)) ?? .wordOnly
        }
        set {
            defaults.set(newValue.rawValue, forKey: playbackModeKey)
        }
    }
    
    var ttsServiceType: TTSServiceType {
        get {
            TTSServiceType(rawValue: defaults.integer(forKey: ttsServiceTypeKey)) ?? .edgeTTS
        }
        set {
            defaults.set(newValue.rawValue, forKey: ttsServiceTypeKey)
        }
    }
    
    var speechRecognitionServiceType: SpeechRecognitionServiceType {
        get {
            SpeechRecognitionServiceType(rawValue: defaults.integer(forKey: speechRecognitionServiceTypeKey)) ?? .nativeSpeech
        }
        set {
            defaults.set(newValue.rawValue, forKey: speechRecognitionServiceTypeKey)
        }
    }
    
    var whisperModelSize: WhisperModelSize {
        get {
            if let storedValue = defaults.string(forKey: whisperModelSizeKey),
               let modelSize = WhisperModelSize(rawValue: storedValue) {
                return modelSize
            }
            return .small
        }
        set {
            defaults.set(newValue.rawValue, forKey: whisperModelSizeKey)
        }
    }
    
    var playbackSpeed: Float {
        get {
            let speed = defaults.float(forKey: playbackSpeedKey)
            return speed > 0 ? speed : 1.0
        }
        set {
            defaults.set(newValue, forKey: playbackSpeedKey)
        }
    }
    
    /// 是否自动加载WhisperKit模型
    var autoLoadWhisperModel: Bool {
        get {
            // 默认为true，提供更好的用户体验
            if defaults.object(forKey: autoLoadWhisperModelKey) == nil {
                return true
            }
            return defaults.bool(forKey: autoLoadWhisperModelKey)
        }
        set {
            defaults.set(newValue, forKey: autoLoadWhisperModelKey)
        }
    }
    
    /// 是否允许使用蜂窝网络下载模型
    var allowCellularDownload: Bool {
        get {
            // 默认为false，避免消耗用户流量
            return defaults.bool(forKey: allowCellularDownloadKey)
        }
        set {
            defaults.set(newValue, forKey: allowCellularDownloadKey)
        }
    }
}