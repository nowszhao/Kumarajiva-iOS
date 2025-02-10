import Foundation

class UserSettings {
    static let shared = UserSettings()
    
    private let defaults = UserDefaults.standard
    private let playbackModeKey = "playback_mode"
    
    private init() {}
    
    var playbackMode: PlaybackMode {
        get {
            PlaybackMode(rawValue: defaults.integer(forKey: playbackModeKey)) ?? .wordOnly
        }
        set {
            defaults.set(newValue.rawValue, forKey: playbackModeKey)
        }
    }
} 