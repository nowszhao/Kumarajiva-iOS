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
    
    // MARK: - Vocabulary API
    
    func getVocabularyList() async throws -> [VocabularyItem] {
        let url = "\(baseURL)/vocab"
        print("🔍 [Vocab] 开始获取生词列表...")
        print("🔍 [Vocab] 请求URL: \(url)")
        
        do {
            // 使用标准的request方法
            let vocabularies: [VocabularyItem] = try await get(url)
            print("🔍 [Vocab] 成功获取生词列表，生词数量: \(vocabularies.count)")
            let sortedData = vocabularies.sorted { $0.timestamp > $1.timestamp }
            print("🔍 [Vocab] 排序完成，返回数据")
            return sortedData
        } catch {
            print("🔍 [Vocab] 获取生词列表失败: \(error)")
            throw error
        }
    }
    
    func deleteVocabulary(word: String) async throws -> Bool {
        let url = "\(baseURL)/vocab/\(word.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? word)"
        let response: SimpleResponse = try await deleteRequest(url)
        return response.success
    }
    
    func updateVocabulary(_ vocabulary: VocabularyItem) async throws -> Bool {
        let word = vocabulary.word.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? vocabulary.word
        let url = "\(baseURL)/vocab/\(word)"
        print("🔄 [Update] 开始更新单词: \(vocabulary.word)")
        print("🔄 [Update] 请求URL: \(url)")
        
        let updateData = VocabularyUpdateData(
            word: vocabulary.word,
            definitions: vocabulary.definitions,
            pronunciation: vocabulary.pronunciation ?? [:],
            memoryMethod: vocabulary.memoryMethod,
            mastered: vocabulary.mastered > 0,
            timestamp: vocabulary.timestamp
        )
        
        do {
            let response: UpdateVocabularyResponse = try await putWithEncoder(url, body: updateData)
            print("🔄 [Update] 更新成功: \(response.success)")
            return response.success
        } catch {
            print("🔄 [Update] 更新失败: \(error)")
            throw error
        }
    }
    
    func importVocabularies(_ request: VocabularyImportRequest) async throws -> Bool {
        let url = "\(baseURL)/vocab/import"
        print("📦 Request url: \(url)")
        
        // 打印请求体以便调试
        if let jsonData = try? JSONEncoder().encode(request),
           let jsonString = String(data: jsonData, encoding: .utf8) {
            print("📦 Request body: \(jsonString)")
        }
        
        let response: SimpleResponse = try await postWithEncoder(url, body: request)
        return response.success
    }
    
    private func get<T: Decodable>(_ url: String) async throws -> T {
        try await request(.get, url: url)
    }
    
    private func post<T: Decodable>(_ url: String, body: [String: Any]) async throws -> T {
        try await request(.post, url: url, body: body)
    }
    
    private func deleteRequest<T: Decodable>(_ url: String) async throws -> T {
        try await request(.delete, url: url)
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
    
    private func postWithEncoder<T: Decodable, U: Codable>(_ url: String, body: U) async throws -> T {
        guard let url = URL(string: url) else {
            throw APIError.invalidURL
        }
        print("\n\n#################start###################")
        print("📦 Request url: \(url)")
        var request = URLRequest(url: url)
        request.httpMethod = HTTPMethod.post.rawValue
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        // 添加认证头
        let authHeaders = authService.getAuthHeaders()
        for (key, value) in authHeaders {
            request.setValue(value, forHTTPHeaderField: key)
        }
        
        // 使用JSONEncoder编码Codable对象
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        request.httpBody = try encoder.encode(body)
        
        if let bodyData = request.httpBody,
           let bodyString = String(data: bodyData, encoding: .utf8) {
            print("📦 Request body: \(bodyString)")
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
                print("📦 Response data: \(responseString.size())")
            }
            
            guard let httpResponse = response as? HTTPURLResponse,
                  (200...299).contains(httpResponse.statusCode) else {
                throw APIError.invalidResponse
            }
            
            do {
                let decoder = JSONDecoder()
                decoder.keyDecodingStrategy = .convertFromSnakeCase
                
                // 先尝试打印原始数据以便调试
//                if let jsonObject = try? JSONSerialization.jsonObject(with: data, options: []),
//                   let prettyData = try? JSONSerialization.data(withJSONObject: jsonObject, options: .prettyPrinted),
//                   let prettyString = String(data: prettyData, encoding: .utf8) {
//                    print("📦 Pretty JSON:\n\(prettyString)")
//                }
                
                let response = try decoder.decode(T.self, from: data)
                print("✅ Successfully decoded response")
                
                print("#################end###################\n\n")

                return response
            } catch {
                print("❌ Decoding error: \(error)")
                
                // 打印更详细的错误信息
                if let decodingError = error as? DecodingError {
                    switch decodingError {
                    case .typeMismatch(let type, let context):
                        print("❌ Type mismatch: expected \(type), context: \(context)")
                    case .valueNotFound(let type, let context):
                        print("❌ Value not found: \(type), context: \(context)")
                    case .keyNotFound(let key, let context):
                        print("❌ Key not found: \(key), context: \(context)")
                    case .dataCorrupted(let context):
                        print("❌ Data corrupted: \(context)")
                    @unknown default:
                        print("❌ Unknown decoding error")
                    }
                }
                
                throw APIError.decodingError(error)
            }
        } catch {
            print("❌ Network error: \(error)")
            throw APIError.networkError(error)
        }
    }
    
    private func putWithEncoder<T: Decodable, U: Codable>(_ url: String, body: U) async throws -> T {
        guard let url = URL(string: url) else {
            throw APIError.invalidURL
        }
        print("\n\n#################start###################")
        print("📦 PUT Request url: \(url)")
        var request = URLRequest(url: url)
        request.httpMethod = HTTPMethod.put.rawValue
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        // 添加认证头
        let authHeaders = authService.getAuthHeaders()
        for (key, value) in authHeaders {
            request.setValue(value, forHTTPHeaderField: key)
        }
        
        // 使用JSONEncoder编码Codable对象
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        request.httpBody = try encoder.encode(body)
        
        if let bodyData = request.httpBody,
           let bodyString = String(data: bodyData, encoding: .utf8) {
            print("📦 PUT Request body: \(bodyString)")
        }
        
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            
            print("📥 PUT Response received")
            if let httpResponse = response as? HTTPURLResponse {
                print("📊 PUT Status code: \(httpResponse.statusCode)")
                
                // 检查认证状态
                if httpResponse.statusCode == 401 {
                    throw APIError.unauthorized
                }
            }
            
            if let responseString = String(data: data, encoding: .utf8) {
                print("📦 PUT Response data: \(responseString)")
            }
            
            guard let httpResponse = response as? HTTPURLResponse,
                  (200...299).contains(httpResponse.statusCode) else {
                throw APIError.invalidResponse
            }
            
            do {
                let decoder = JSONDecoder()
                decoder.keyDecodingStrategy = .convertFromSnakeCase
                
                let response = try decoder.decode(T.self, from: data)
                print("✅ Successfully decoded PUT response")
                
                print("#################end###################\n\n")

                return response
            } catch {
                print("❌ PUT Decoding error: \(error)")
                throw APIError.decodingError(error)
            }
        } catch {
            print("❌ PUT Network error: \(error)")
            throw APIError.networkError(error)
        }
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
                print("📦 Response data: \(responseString.size())")
            }
            
            guard let httpResponse = response as? HTTPURLResponse,
                  (200...299).contains(httpResponse.statusCode) else {
                throw APIError.invalidResponse
            }
            
            do {
                let decoder = JSONDecoder()
                decoder.keyDecodingStrategy = .convertFromSnakeCase
                
                // 先尝试打印原始数据以便调试
//                if let jsonObject = try? JSONSerialization.jsonObject(with: data, options: []),
//                   let prettyData = try? JSONSerialization.data(withJSONObject: jsonObject, options: .prettyPrinted),
//                   let prettyString = String(data: prettyData, encoding: .utf8) {
//                    print("📦 Pretty JSON:\n\(prettyString)")
//                }
                
                let response = try decoder.decode(APIResponse<T>.self, from: data)
                print("✅ Successfully decoded response")
                
                print("#################end###################\n\n")

                return response.data
            } catch {
                print("❌ Decoding error: \(error)")
                
                // 打印更详细的错误信息
                if let decodingError = error as? DecodingError {
                    switch decodingError {
                    case .typeMismatch(let type, let context):
                        print("❌ Type mismatch: expected \(type), context: \(context)")
                    case .valueNotFound(let type, let context):
                        print("❌ Value not found: \(type), context: \(context)")
                    case .keyNotFound(let key, let context):
                        print("❌ Key not found: \(key), context: \(context)")
                    case .dataCorrupted(let context):
                        print("❌ Data corrupted: \(context)")
                    @unknown default:
                        print("❌ Unknown decoding error")
                    }
                }
                
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
            print("📦 Response data: \(responseString.size())")
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
        case delete = "DELETE"
        case put = "PUT"
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

// MARK: - Vocabulary Models

struct VocabularyItem: Codable, Identifiable, Equatable {
    let word: String
    let definitions: [VocabularyDefinition]
    let memoryMethod: String?
    let pronunciation: [String: String]?
    let mastered: Int
    let timestamp: Int64
    let userId: Int?
    let isNewlyAdded: Bool?  // 标记是否是新添加的生词
    
    var id: String { word }
    
    // For local changes tracking - not encoded
    var isLocallyModified: Bool = false
    var isLocallyDeleted: Bool = false
    
    // Computed property to get American pronunciation
    var americanPronunciation: String? {
        pronunciation?["American"]
    }
    
    // Computed property to get British pronunciation
    var britishPronunciation: String? {
        pronunciation?["British"]
    }
    
    // MARK: - Equatable Implementation
    static func == (lhs: VocabularyItem, rhs: VocabularyItem) -> Bool {
        return lhs.word == rhs.word &&
               lhs.definitions == rhs.definitions &&
               lhs.memoryMethod == rhs.memoryMethod &&
               lhs.pronunciation == rhs.pronunciation &&
               lhs.mastered == rhs.mastered &&
               lhs.timestamp == rhs.timestamp &&
               lhs.userId == rhs.userId &&
               lhs.isNewlyAdded == rhs.isNewlyAdded &&
               lhs.isLocallyModified == rhs.isLocallyModified &&
               lhs.isLocallyDeleted == rhs.isLocallyDeleted
    }
    
    enum CodingKeys: String, CodingKey {
        case word, definitions, pronunciation, mastered, timestamp
        case memoryMethod
        case userId = "user_id"
        case isNewlyAdded = "is_newly_added"
    }
    
    // Custom decoder to handle both string and dictionary formats for pronunciation
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        
        word = try container.decode(String.self, forKey: .word)
        definitions = try container.decode([VocabularyDefinition].self, forKey: .definitions)
        memoryMethod = try container.decodeIfPresent(String.self, forKey: .memoryMethod)
        mastered = try container.decode(Int.self, forKey: .mastered)
        timestamp = try container.decode(Int64.self, forKey: .timestamp)
        userId = try container.decodeIfPresent(Int.self, forKey: .userId)
        isNewlyAdded = try container.decodeIfPresent(Bool.self, forKey: .isNewlyAdded)
        
        
//        print("memoryMethod:",memoryMethod)
//        print("userId:",userId)
//        print("definitions:",definitions)
        
        // Handle pronunciation field - can be either string JSON or dictionary
        if let pronunciationDict = try? container.decode([String: String].self, forKey: .pronunciation) {
            // If it's already a dictionary, use it directly
            pronunciation = pronunciationDict
        } else if let pronunciationString = try? container.decode(String.self, forKey: .pronunciation) {
            // If it's a string, try to parse it as JSON
            if let pronunciationData = pronunciationString.data(using: .utf8),
               let pronunciationDict = try? JSONDecoder().decode([String: String].self, from: pronunciationData) {
                pronunciation = pronunciationDict
            } else {
                // If JSON parsing fails, treat as American pronunciation
                pronunciation = ["American": pronunciationString]
            }
        } else {
            // Fallback to nil pronunciation
            pronunciation = nil
        }
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(word, forKey: .word)
        try container.encode(definitions, forKey: .definitions)
        try container.encodeIfPresent(memoryMethod, forKey: .memoryMethod)
        try container.encodeIfPresent(pronunciation, forKey: .pronunciation)
        try container.encode(mastered, forKey: .mastered)
        try container.encode(timestamp, forKey: .timestamp)
        try container.encodeIfPresent(userId, forKey: .userId)
        try container.encodeIfPresent(isNewlyAdded, forKey: .isNewlyAdded)
        // Don't encode local state properties
    }
    
    init(from difficult: DifficultVocabulary) {
        self.word = difficult.vocabulary
        self.definitions = [VocabularyDefinition(pos: difficult.partOfSpeech, meaning: difficult.chineseMeaning)]
        self.memoryMethod = difficult.chineseEnglishSentence
        self.pronunciation = ["American": difficult.phonetic]
        self.mastered = 0
        self.timestamp = Int64(Date().timeIntervalSince1970 * 1000)  // 转换为毫秒
        self.userId = nil
        self.isNewlyAdded = true
        self.isLocallyModified = true
        self.isLocallyDeleted = false
    }
    
    init(
        word: String,
        definitions: [VocabularyDefinition],
        memoryMethod: String? = nil,
        pronunciation: [String: String]? = nil,
        mastered: Int = 0,
        timestamp: Int64,
        userId: Int? = nil,
        isNewlyAdded: Bool? = nil
    ) {
        self.word = word
        self.definitions = definitions
        self.memoryMethod = memoryMethod
        self.pronunciation = pronunciation
        self.mastered = mastered
        self.timestamp = timestamp
        self.userId = userId
        self.isNewlyAdded = isNewlyAdded
        self.isLocallyModified = false
        self.isLocallyDeleted = false
    }
}

struct VocabularyDefinition: Codable, Equatable {
    let pos: String
    let meaning: String
}

// MARK: - Vocabulary Import Models (API格式)

struct VocabularyImportRequest: Codable {
    let vocabularies: [String: VocabularyImportData]
}

struct VocabularyImportData: Codable {
    let word: String
    let definitions: [VocabularyDefinition]
    let pronunciation: [String: String]?
    let memoryMethod: String?
    let mastered: Bool
    let timestamp: Int64
    
    enum CodingKeys: String, CodingKey {
        case word, definitions, pronunciation, mastered, timestamp
        case memoryMethod = "memory_method"
    }
}

// MARK: - Vocabulary Update Models

struct VocabularyUpdateData: Codable {
    let word: String
    let definitions: [VocabularyDefinition]
    let pronunciation: [String: String]
    let memoryMethod: String?
    let mastered: Bool
    let timestamp: Int64
    
    enum CodingKeys: String, CodingKey {
        case word, definitions, pronunciation, mastered, timestamp
        case memoryMethod = "memory_method"
    }
}

struct UpdateVocabularyResponse: Codable {
    let success: Bool
    let data: UpdateData
}

struct UpdateData: Codable {
    let success: Bool
    let changes: Int
}

// MARK: - Legacy Import Model (保持向后兼容)

struct VocabularyImportItem: Codable {
    let word: String
    let definitions: String
    let pronunciation: String?
    let memoryMethod: String?
    let mastered: Bool
    let timestamp: Int64
    let isNewlyAdded: Bool?  // 标记是否是新添加的生词
    
    enum CodingKeys: String, CodingKey {
        case word, definitions, pronunciation, mastered, timestamp
        case memoryMethod = "memory_method"
        case isNewlyAdded = "is_newly_added"
    }
} 
