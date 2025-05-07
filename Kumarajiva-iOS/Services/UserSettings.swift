import Foundation

class UserSettings {
    static let shared = UserSettings()
    
    private let defaults = UserDefaults.standard
    private let playbackModeKey = "playback_mode"
    private let ttsServiceTypeKey = "tts_service_type"
    
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
} 