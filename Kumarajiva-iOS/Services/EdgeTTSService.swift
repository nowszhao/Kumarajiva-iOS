import Foundation
import AVFoundation
import CryptoKit

class EdgeTTSService {
    static let shared = EdgeTTSService()
    
    private let apiUrl = "http://47.121.117.100:5050/tts"
    private let cacheDirectory: URL
    private var audioCache = [String: URL]()
    
    private init() {
        // Create cache directory in the app's shared container that is accessible via Files app
        let containerURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let edgeTTSDirectory = containerURL.appendingPathComponent("KumarajivaEdgeTTS", isDirectory: true)
        cacheDirectory = edgeTTSDirectory
        
        do {
            // Create directory if it doesn't exist
            if !FileManager.default.fileExists(atPath: cacheDirectory.path) {
                try FileManager.default.createDirectory(at: cacheDirectory, 
                                                       withIntermediateDirectories: true, 
                                                       attributes: nil)
            }
            
            // Make directory visible in Files app
            var resourceValues = URLResourceValues()
            resourceValues.isExcludedFromBackup = false
            var mutableURL = cacheDirectory as URL
            try mutableURL.setResourceValues(resourceValues)
            
            // Load existing cache entries
            loadCacheEntries()
        } catch {
            print("Failed to create cache directory: \(error)")
        }
    }
    
    private func loadCacheEntries() {
        do {
            let fileURLs = try FileManager.default.contentsOfDirectory(at: cacheDirectory, includingPropertiesForKeys: nil)
            
            for fileURL in fileURLs {
                if fileURL.pathExtension == "mp3" {
                    // 提取文件名中的哈希部分（最后8个字符）作为缓存键
                    let fileName = fileURL.deletingPathExtension().lastPathComponent
                    if let lastUnderscoreIndex = fileName.lastIndex(of: "_") {
                        let hashPart = fileName.suffix(from: lastUnderscoreIndex).dropFirst()
                        audioCache[String(hashPart)] = fileURL
                    }
                }
            }
            
            print("Loaded \(audioCache.count) cached TTS files")
        } catch {
            print("Failed to load cache entries: \(error)")
        }
    }
    
    private func cacheKeyForText(_ text: String, voice: String, rate: String) -> String {
        // Create a unique cache key based on the text, voice and rate
        let key = "\(text)_\(voice)_\(rate)"
        
        // Use SHA-256 to create a fixed-length hash
        if let data = key.data(using: .utf8) {
            let hash = SHA256.hash(data: data)
            // Convert to hex string, limited to 32 characters
            return hash.compactMap { String(format: "%02x", $0) }.joined()
        }
        
        // Fallback in case of encoding issues
        return "fallback_\(Date().timeIntervalSince1970)"
    }
    
    func synthesize(text: String, voice: String = "en-US-AndrewMultilingualNeural", rate: String = "-15%", completion: @escaping (URL?) -> Void) {
        // Limit text length to 500 characters to prevent issues with very long texts
        let limitedText = text.count > 500 ? String(text.prefix(500)) + "..." : text
        let cacheKey = cacheKeyForText(limitedText, voice: voice, rate: rate)
        
        // Check if we have this audio cached
        if let cachedFileURL = audioCache[cacheKey] {
            print("Using cached audio for: \(limitedText)")
            completion(cachedFileURL)
            return
        }
        
        // Prepare API request
        guard let url = URL(string: apiUrl) else {
            completion(nil)
            return
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let params: [String: Any] = [
            "text": limitedText,
            "rate": rate,
            "voice": voice
        ]
        
        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: params)
        } catch {
            print("Failed to serialize request: \(error)")
            completion(nil)
            return
        }
        
        // Execute request
        let task = URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            guard let self = self,
                  let data = data, error == nil,
                  let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200 else {
                print("TTS API error: \(error?.localizedDescription ?? "Unknown error")")
                completion(nil)
                return
            }
            
            // Create a more readable filename without timestamp to ensure cache consistency
            let displayableText = String(limitedText.prefix(20))
                .replacingOccurrences(of: " ", with: "_")
                .replacingOccurrences(of: "/", with: "_")
                .replacingOccurrences(of: ":", with: "_")
            
            // Save to cache with a more user-friendly name (use hash as part of filename for uniqueness)
            // 使用cacheKey的前8个字符作为文件名的一部分，确保缓存查找时能够匹配
            let hashPart = cacheKey.prefix(8)
            let fileURL = self.cacheDirectory.appendingPathComponent("\(displayableText)_\(hashPart).mp3")
            
            do {
                try data.write(to: fileURL)
                self.audioCache[cacheKey] = fileURL
                print("Cached audio for: \(limitedText)")
                completion(fileURL)
            } catch {
                print("Failed to write audio to cache: \(error)")
                completion(nil)
            }
        }
        
        task.resume()
    }
    
    func clearCache() {
        do {
            let fileURLs = try FileManager.default.contentsOfDirectory(at: cacheDirectory, includingPropertiesForKeys: nil)
            
            for fileURL in fileURLs {
                try FileManager.default.removeItem(at: fileURL)
            }
            
            audioCache.removeAll()
            print("TTS cache cleared")
        } catch {
            print("Failed to clear cache: \(error)")
        }
    }
}
