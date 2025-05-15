import Foundation

class UserSettings {
    static let shared = UserSettings()
    
    private let defaults = UserDefaults.standard
    private let playbackModeKey = "playback_mode"
    private let ttsServiceTypeKey = "tts_service_type"
    private let speechRecognitionServiceTypeKey = "speech_recognition_service_type"
    private let whisperModelSizeKey = "whisper_model_size"
    private let playbackSpeedKey = "playback_speed"
    
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
}