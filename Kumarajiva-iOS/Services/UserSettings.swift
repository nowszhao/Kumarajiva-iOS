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
    private let llmCookieKey = "llm_cookie"
    
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
    
    /// LLM服务Cookie
    var llmCookie: String {
        get {
            if let cookie = defaults.string(forKey: llmCookieKey), !cookie.isEmpty {
                return cookie
            }
            // 返回默认Cookie
            return "_qimei_h38=d941369c80e2f1043d10ddcf0300000e819613; hy_source=web; hy_user=changhozhao; web_uid=7ebc4878-f078-4d89-ae9e-2fc868d10f99; _ga_6WSZ0YS5ZQ=GS2.1.s1753184540$o1$g0$t1753184619$j60$l0$h0; _qimei_fingerprint=5870c36ba01ee6a5ca3aeafe20c22f40; qcloud_visitId=2eaf634d438b705087d882ad2d99a317; _gcl_au=1.1.565999112.1759992206; qcstats_seo_keywords=%E5%93%81%E7%89%8C%E8%AF%8D-%E5%93%81%E7%89%8C%E8%AF%8D-%E7%99%BB%E5%BD%95; x_host_key_access_https=84e11c3e69a076f7c5c8845d822c294e8ed1feda_s; qcloud_from=qcloud.google.seo-1760408488757; x-client-ssid=2f642415:0199e20921f0:01a45b; _ga=GA1.1.1255136171.1753184540; _ga_RPMZTEBERQ=GS2.1.s1760441059$o2$g0$t1760441059$j60$l0$h0; sensorsdata2015jssdkcross=%7B%22distinct_id%22%3A%22100011415527%22%2C%22first_id%22%3A%22197f32a3767648-04d54c57ee9509-17525636-1930176-197f32a37692cea%22%2C%22props%22%3A%7B%22%24latest_traffic_source_type%22%3A%22%E7%9B%B4%E6%8E%A5%E6%B5%81%E9%87%8F%22%7D%2C%22identities%22%3A%22eyIkaWRlbnRpdHlfY29va2llX2lkIjoiMTk3ZjMyYTM3Njc2NDgtMDRkNTRjNTdlZTk1MDktMTc1MjU2MzYtMTkzMDE3Ni0xOTdmMzJhMzc2OTJjZWEiLCIkaWRlbnRpdHlfbG9naW5faWQiOiIxMDAwMTE0MTU1MjcifQ%3D%3D%22%2C%22history_login_id%22%3A%7B%22name%22%3A%22%24identity_login_id%22%2C%22value%22%3A%22100011415527%22%7D%2C%22%24device_id%22%3A%22197f32a3ee31b63-0bbe0d10394f6f-17525636-1930176-197f32a3ee431c4%22%7D; _qimei_i_1=7ff255d69c5e51d8c79ead385bd171b6f6eea0f2465a03d6e0dc7e582593206c6163629d3980e4ddd59ffbfd; hy_token=8tE8bq6InCxff5mUqQZfc9aGHP6NPD80Cr/k258SiLJ9CYW8HiMzU5pREYyvnbvjeMlQugP5sjBBf6Z6HkeKPmw70gyim1uF7yzAGG5SktN5elniDcbIk281Qd3t9wBwmYiBi9omgQ/TZ8dmzLOH7OUJZkQAHF3eSZP9KHAu72idMXpzhtXSQZx/JRmqKbxikn5qEnjU6Wnz2FUf+tDgZnD1YIWNxj8u0epPps7+OmHolduZWY3uXka8keS8tgTXtH8r1xKIcvB2Pc2r4Hzqjk7c5S1Ozg5BrDv4YYkqFcqK4M50jWj4vTsl6YDAteITBfsDVcKB4sUB206pJD3hMNRvuBO2nYWY9oWQn6llh4lteaSfmc8paIaPhWRvAXUNCnZHTntjuSBHUTeZLZNJEaeq5pj606l88wkOkTkVwJ89pyL9OviG83tU3jDlWe9J+2Ip6yQWb8JjDxdAZf2d3Yt9V2o3E8DzmlXGiORzsQiJhZTSDdA5EhhvOIB8Ihr9nJ9P6pZyB3ehKbs8FHlh1I4r9COcJUwl29MyIIHPcEvRgRbU2DluLW0NCDkls9AqWiM3omHndFTyGvj60opE0JbUp6emr6AC3f2E0sSmn//bKdbBU3dFu7MxnT5avXel;"
        }
        set {
            defaults.set(newValue, forKey: llmCookieKey)
        }
    }
}