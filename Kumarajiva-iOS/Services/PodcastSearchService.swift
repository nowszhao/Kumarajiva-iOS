import Foundation

// MARK: - 搜索结果模型
struct PodcastSearchResult: Identifiable, Codable {
    var id: String { url } // 使用url作为id，避免Codable问题
    let title: String
    let url: String
    let description: String
    let author: String
    let image: String
    
    var imageURL: URL? {
        URL(string: image)
    }
}

struct PodcastSearchResponse: Codable {
    let success: Bool
    let data: [PodcastSearchResult]
}

// MARK: - 播客搜索服务
@MainActor
class PodcastSearchService: ObservableObject {
    static let shared = PodcastSearchService()
    
    @Published var searchResults: [PodcastSearchResult] = []
    @Published var isSearching = false
    @Published var errorMessage: String?
    
    private let baseURL = "https://castos.com/wp-admin/admin-ajax.php"
    
    private init() {}
    
    func searchPodcasts(query: String) async {
        guard !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            searchResults = []
            return
        }
        
        isSearching = true
        errorMessage = nil
        
        do {
            let results = try await performSearch(query: query)
            searchResults = results
        } catch {
            errorMessage = error.localizedDescription
            searchResults = []
        }
        
        isSearching = false
    }
    
    private func performSearch(query: String) async throws -> [PodcastSearchResult] {
        guard let url = URL(string: baseURL) else {
            throw PodcastSearchError.invalidURL
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        
        // 构建表单数据
        let boundary = UUID().uuidString
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        
        var bodyData = Data()
        
        // 添加search参数
        bodyData.append("--\(boundary)\r\n".data(using: .utf8)!)
        bodyData.append("Content-Disposition: form-data; name=\"search\"\r\n\r\n".data(using: .utf8)!)
        bodyData.append("\(query)\r\n".data(using: .utf8)!)
        
        // 添加action参数
        bodyData.append("--\(boundary)\r\n".data(using: .utf8)!)
        bodyData.append("Content-Disposition: form-data; name=\"action\"\r\n\r\n".data(using: .utf8)!)
        bodyData.append("feed_url_lookup_search\r\n".data(using: .utf8)!)
        
        // 结束边界
        bodyData.append("--\(boundary)--\r\n".data(using: .utf8)!)
        
        request.httpBody = bodyData
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw PodcastSearchError.networkError
        }
        
        do {
            let searchResponse = try JSONDecoder().decode(PodcastSearchResponse.self, from: data)
            
            if searchResponse.success {
                return searchResponse.data
            } else {
                throw PodcastSearchError.searchFailed
            }
        } catch {
            print("🔍 [Search] JSON解析错误: \(error)")
            print("🔍 [Search] 响应数据: \(String(data: data, encoding: .utf8) ?? "无法解析")")
            throw PodcastSearchError.parseError
        }
    }
    
    func clearResults() {
        searchResults = []
        errorMessage = nil
    }
}

// MARK: - 错误类型
enum PodcastSearchError: LocalizedError {
    case invalidURL
    case networkError
    case parseError
    case searchFailed
    
    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "无效的搜索地址"
        case .networkError:
            return "网络连接失败"
        case .parseError:
            return "数据解析失败"
        case .searchFailed:
            return "搜索失败"
        }
    }
} 