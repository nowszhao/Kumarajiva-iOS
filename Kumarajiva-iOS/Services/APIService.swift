import Foundation

enum APIError: Error {
    case invalidURL
    case invalidResponse
    case networkError(Error)
    case decodingError(Error)
    case unauthorized
}

class APIService {
    static let shared = APIService()
     private let baseURL = "http://47.121.117.100:3000/api"
//    private let baseURL = "http://127.0.0.1:3000/api"

    private let authService = AuthService.shared
    
    private init() {}
    
    func getTodayWords() async throws -> [Word] {
//        print("📝 Getting today's words...")
        let url = "\(baseURL)/review/today"
        return try await get(url)
    }
    
    func getQuiz(word: String) async throws -> Quiz {
        let url = "\(baseURL)/review/quiz"
        return try await post(url, body: ["word": word])
    }
    
    func submitReview(word: String, result: Bool) async throws -> ReviewResult {
        let url = "\(baseURL)/review/record"
        return try await post(url, body: [
            "word": word,
            "result": result
        ])
    }
    
    func getProgress() async throws -> Progress {
        let url = "\(baseURL)/review/progress"
        return try await get(url)
    }
    
    func resetProgress() async throws -> Progress {
        let url = "\(baseURL)/review/reset"
        return try await post(url, body: [:])
    }
    
    func getHistory(params: [String: Any]) async throws -> ReviewHistoryResponse {
        var urlComponents = URLComponents(string: "\(baseURL)/review/history")!
        urlComponents.queryItems = params.map { key, value in
            URLQueryItem(name: key, value: String(describing: value))
        }
        
        guard let url = urlComponents.url else {
            throw APIError.invalidURL
        }
        
        return try await getRaw(url.absoluteString)
    }
    
    func updateProgress(currentWordIndex: Int, completed: Int, correct: Int) async throws -> Bool {
        let url = "\(baseURL)/review/progress"
        let response: SimpleResponse = try await postRaw(url, body: [
            "current_word_index": currentWordIndex,
            "completed": completed,
            "correct": correct
        ])
        return response.success
    }
    
    func getStats() async throws -> Stats {
        let url = "\(baseURL)/review/stats"
        return try await get(url)
    }
    
    private func get<T: Decodable>(_ url: String) async throws -> T {
        try await request(.get, url: url)
    }
    
    private func post<T: Decodable>(_ url: String, body: [String: Any]) async throws -> T {
        try await request(.post, url: url, body: body)
    }
    
    private func postRaw<T: Decodable>(_ url: String, body: [String: Any]) async throws -> T {
        guard let url = URL(string: url) else {
            throw APIError.invalidURL
        }
        print("\n\n#################start###################")
        print("📦 (Raw) Request url: \(url)")
        var request = URLRequest(url: url)
        request.httpMethod = HTTPMethod.post.rawValue
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        // 添加认证头
        let authHeaders = authService.getAuthHeaders()
        for (key, value) in authHeaders {
            request.setValue(value, forHTTPHeaderField: key)
        }
        
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        print("📦 (Raw) Request body: \(body)")
        
        let (data, response) = try await URLSession.shared.data(for: request)
        print("📥 (Raw) Response received")
        if let httpResponse = response as? HTTPURLResponse {
            print("📊 (Raw) Status code: \(httpResponse.statusCode)")
            
            // 检查认证状态
            if httpResponse.statusCode == 401 {
                throw APIError.unauthorized
            }
        }
        
        print("#################end###################\n\n")
        
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try decoder.decode(T.self, from: data)
    }
    
    private func request<T: Decodable>(_ method: HTTPMethod, url: String, body: [String: Any]? = nil) async throws -> T {
        guard let url = URL(string: url) else {
            throw APIError.invalidURL
        }
        print("\n\n#################start###################")
        print("📦 Request url: \(url)")
        var request = URLRequest(url: url)
        request.httpMethod = method.rawValue
        
        // 添加认证头
        let authHeaders = authService.getAuthHeaders()
        for (key, value) in authHeaders {
            request.setValue(value, forHTTPHeaderField: key)
        }
        
        if let body = body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
            print("📦 Request body: \(body)")
        }
        
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            
            print("📥 Response received")
            if let httpResponse = response as? HTTPURLResponse {
                print("📊 Status code: \(httpResponse.statusCode)")
                
                // 检查认证状态
                if httpResponse.statusCode == 401 {
                    throw APIError.unauthorized
                }
            }
            
            if let responseString = String(data: data, encoding: .utf8) {
                print("📦 Response data: \(responseString)")
            }
            
            guard let httpResponse = response as? HTTPURLResponse,
                  (200...299).contains(httpResponse.statusCode) else {
                throw APIError.invalidResponse
            }
            
            do {
                let decoder = JSONDecoder()
                decoder.keyDecodingStrategy = .convertFromSnakeCase
                let response = try decoder.decode(APIResponse<T>.self, from: data)
                print("✅ Successfully decoded response")
                
                print("#################end###################\n\n")

                return response.data
            } catch {
                print("❌ Decoding error: \(error)")
                throw APIError.decodingError(error)
            }
        } catch {
            print("❌ Network error: \(error)")
            throw APIError.networkError(error)
        }
        
    }
    
    private func getRaw<T: Decodable>(_ url: String) async throws -> T {
        guard let url = URL(string: url) else {
            throw APIError.invalidURL
        }
        
        print("\n\n#################start###################")
        print("📦 Request url: \(url)")
        
        var request = URLRequest(url: url)
        request.httpMethod = HTTPMethod.get.rawValue
        
        // 添加认证头
        let authHeaders = authService.getAuthHeaders()
        for (key, value) in authHeaders {
            request.setValue(value, forHTTPHeaderField: key)
        }
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        print("📥 Response received")
        if let httpResponse = response as? HTTPURLResponse {
            print("📊 Status code: \(httpResponse.statusCode)")
            
            // 检查认证状态
            if httpResponse.statusCode == 401 {
                throw APIError.unauthorized
            }
        }
        
        if let responseString = String(data: data, encoding: .utf8) {
            print("📦 Response data: \(responseString)")
        }
        
        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw APIError.invalidResponse
        }
        
        do {
            let decoder = JSONDecoder()
            let response = try decoder.decode(T.self, from: data)
            print("✅ Successfully decoded response")
            
            print("#################end###################\n\n")
            return response
        } catch {
            print("❌ Decoding error: \(error)")
            throw APIError.decodingError(error)
        }
    }
    
    private enum HTTPMethod: String {
        case get = "GET"
        case post = "POST"
    }
}

struct APIResponse<T: Decodable>: Decodable {
    let success: Bool
    let data: T
}

struct SimpleResponse: Decodable {
    let success: Bool
}

struct HistoryResponse: Codable {
    let success: Bool
    let total: Int?
    let data: [History]
    let limit: Int?
    let offset: Int?
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        
        success = try container.decode(Bool.self, forKey: .success)
        data = try container.decode([History].self, forKey: .data)
        
        total = try container.decodeIfPresent(Int.self, forKey: .total)
        limit = try container.decodeIfPresent(Int.self, forKey: .limit)
        offset = try container.decodeIfPresent(Int.self, forKey: .offset)
    }
    
    enum CodingKeys: String, CodingKey {
        case success, total, data, limit, offset
    }
} 
