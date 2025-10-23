import Foundation
import Combine

/// LLM Service for handling API communication with LLM servers
class LLMService: ObservableObject {
    static let shared = LLMService()

    // Published properties for observing state
    @Published var isLoading: Bool = false
    @Published var lastError: String? = nil

    // Default constant values
    private let defaultAgentId = "naQivTmsDa"
    private let defaultModel = "gpt_175B_0404"
    private let defaultCookie = "_qimei_h38=d941369c80e2f1043d10ddcf0300000e819613; hy_source=web; hy_user=changhozhao; web_uid=7ebc4878-f078-4d89-ae9e-2fc868d10f99; _ga_6WSZ0YS5ZQ=GS2.1.s1753184540$o1$g0$t1753184619$j60$l0$h0; _qimei_fingerprint=5870c36ba01ee6a5ca3aeafe20c22f40; qcloud_visitId=2eaf634d438b705087d882ad2d99a317; _gcl_au=1.1.565999112.1759992206; qcstats_seo_keywords=%E5%93%81%E7%89%8C%E8%AF%8D-%E5%93%81%E7%89%8C%E8%AF%8D-%E7%99%BB%E5%BD%95; x_host_key_access_https=84e11c3e69a076f7c5c8845d822c294e8ed1feda_s; qcloud_from=qcloud.google.seo-1760408488757; x-client-ssid=2f642415:0199e20921f0:01a45b; _ga=GA1.1.1255136171.1753184540; _ga_RPMZTEBERQ=GS2.1.s1760441059$o2$g0$t1760441059$j60$l0$h0; sensorsdata2015jssdkcross=%7B%22distinct_id%22%3A%22100011415527%22%2C%22first_id%22%3A%22197f32a3767648-04d54c57ee9509-17525636-1930176-197f32a37692cea%22%2C%22props%22%3A%7B%22%24latest_traffic_source_type%22%3A%22%E7%9B%B4%E6%8E%A5%E6%B5%81%E9%87%8F%22%7D%2C%22identities%22%3A%22eyIkaWRlbnRpdHlfY29va2llX2lkIjoiMTk3ZjMyYTM3Njc2NDgtMDRkNTRjNTdlZTk1MDktMTc1MjU2MzYtMTkzMDE3Ni0xOTdmMzJhMzc2OTJjZWEiLCIkaWRlbnRpdHlfbG9naW5faWQiOiIxMDAwMTE0MTU1MjcifQ%3D%3D%22%2C%22history_login_id%22%3A%7B%22name%22%3A%22%24identity_login_id%22%2C%22value%22%3A%22100011415527%22%7D%2C%22%24device_id%22%3A%22197f32a3ee31b63-0bbe0d10394f6f-17525636-1930176-197f32a3ee431c4%22%7D; _qimei_i_1=7ff255d69c5e51d8c79ead385bd171b6f6eea0f2465a03d6e0dc7e582593206c6163629d3980e4ddd59ffbfd; hy_token=8tE8bq6InCxff5mUqQZfc9aGHP6NPD80Cr/k258SiLJ9CYW8HiMzU5pREYyvnbvjeMlQugP5sjBBf6Z6HkeKPmw70gyim1uF7yzAGG5SktN5elniDcbIk281Qd3t9wBwmYiBi9omgQ/TZ8dmzLOH7OUJZkQAHF3eSZP9KHAu72idMXpzhtXSQZx/JRmqKbxikn5qEnjU6Wnz2FUf+tDgZnD1YIWNxj8u0epPps7+OmHolduZWY3uXka8keS8tgTXtH8r1xKIcvB2Pc2r4Hzqjk7c5S1Ozg5BrDv4YYkqFcqK4M50jWj4vTsl6YDAteITBfsDVcKB4sUB206pJD3hMNRvuBO2nYWY9oWQn6llh4lteaSfmc8paIaPhWRvAXUNCnZHTntjuSBHUTeZLZNJEaeq5pj606l88wkOkTkVwJ89pyL9OviG83tU3jDlWe9J+2Ip6yQWb8JjDxdAZf2d3Yt9V2o3E8DzmlXGiORzsQiJhZTSDdA5EhhvOIB8Ihr9nJ9P6pZyB3ehKbs8FHlh1I4r9COcJUwl29MyIIHPcEvRgRbU2DluLW0NCDkls9AqWiM3omHndFTyGvj60opE0JbUp6emr6AC3f2E0sSmn//bKdbBU3dFu7MxnT5avXel;" // Replace with your actual default cookie

    // Private properties
    private var currentConversationId: String? = nil
    private var isConversationValid: Bool = false
     private let baseURL = "http://47.121.117.100:3000/api/llm"
//    private let baseURL = "http://127.0.0.1:3000/api/llm"

    private var cancellables = Set<AnyCancellable>()

    // Custom URLSession with extended timeout for LLM requests
    private lazy var urlSession: URLSession = {
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 300 // 2 minutes for individual request
        configuration.timeoutIntervalForResource = 600 // 5 minutes for entire resource
        configuration.waitsForConnectivity = true
        return URLSession(configuration: configuration)
    }()

    // API Response Structures
    struct CreateConversationResponse: Codable {
        let success: Bool
        let data: ConversationData

        struct ConversationData: Codable {
            let id: String
        }
    }

    struct ChatResponse: Codable {
        let success: Bool
        let data: MessageData

        struct MessageData: Codable {
            let messageId: String
            let content: String
        }
    }

    /// Request models
    struct CreateConversationRequest: Codable {
        let agentId: String
        let cookie: String
    }

    struct ChatRequest: Codable {
        let prompt: String
        let agentId: String
        let model: String
        let cookie: String
    }

    private init() {
        // Private initializer for singleton
    }

    /// Ensure a valid conversation exists or create a new one
    /// - Parameters:
    ///   - agentId: The agent ID to use (optional, uses default if nil)
    ///   - cookie: Authentication cookie (optional, uses default if nil)
    /// - Returns: A valid conversation ID
    private func ensureValidConversation(agentId: String? = nil, cookie: String? = nil) async throws -> String {
        let finalAgentId = agentId ?? defaultAgentId
        let finalCookie = cookie ?? defaultCookie

        // If we have a conversation ID and it's considered valid, return it
        if let id = currentConversationId, isConversationValid {
            return id
        }

        // Otherwise create a new conversation
        let newId = try await createConversation(agentId: finalAgentId, cookie: finalCookie)
        currentConversationId = newId
        isConversationValid = true
        return newId
    }

    /// Create a new conversation
    /// - Parameters:
    ///   - agentId: The agent ID to use (optional, uses default if nil)
    ///   - cookie: Authentication cookie (optional, uses default if nil)
    /// - Returns: The new conversation ID
    private func createConversation(agentId: String? = nil, cookie: String? = nil) async throws -> String {
        print("🤖 [LLM] 创建新对话...")

        let finalAgentId = agentId ?? defaultAgentId
        let finalCookie = cookie ?? defaultCookie

        let url = URL(string: "\(baseURL)/conversation/create")!
        print("🤖 [LLM] 创建对话URL: \(url)")

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")

        let requestBody = CreateConversationRequest(agentId: finalAgentId, cookie: finalCookie)
        request.httpBody = try JSONEncoder().encode(requestBody)

        print("🤖 [LLM] 发送创建对话请求...")
        let (data, response) = try await urlSession.data(for: request)
        print("🤖 [LLM] 创建对话响应大小: \(data.count) 字节")

        guard let httpResponse = response as? HTTPURLResponse else {
            print("🤖 [LLM] 创建对话：无效的HTTP响应")
            throw NSError(domain: "LLMService", code: 1000, userInfo: [NSLocalizedDescriptionKey: "Invalid response"])
        }

        print("🤖 [LLM] 创建对话HTTP状态码: \(httpResponse.statusCode)")

        if httpResponse.statusCode != 200 {
            if let responseString = String(data: data, encoding: .utf8) {
                print("🤖 [LLM] 创建对话错误响应: \(responseString)")
            }
            throw NSError(domain: "LLMService", code: httpResponse.statusCode, userInfo: [NSLocalizedDescriptionKey: "Failed to create conversation: HTTP \(httpResponse.statusCode)"])
        }

        if let responseString = String(data: data, encoding: .utf8) {
            print("🤖 [LLM] 创建对话响应内容: \(responseString)")
        }

        let createResponse = try JSONDecoder().decode(CreateConversationResponse.self, from: data)
        print("🤖 [LLM] 创建对话解析成功，success: \(createResponse.success)")

        guard createResponse.success else {
            print("🤖 [LLM] 创建对话API返回success=false")
            throw NSError(domain: "LLMService", code: 1001, userInfo: [NSLocalizedDescriptionKey: "Failed to create conversation: API returned success=false"])
        }

        print("🤖 [LLM] 新对话创建成功，ID: \(createResponse.data.id)")
        return createResponse.data.id
    }

    /// Send a chat message to the LLM
    /// - Parameters:
    ///   - prompt: The message to send
    ///   - agentId: The agent ID to use (optional, uses default if nil)
    ///   - model: The LLM model to use (optional, uses default if nil)
    ///   - cookie: Authentication cookie (optional, uses default if nil)
    /// - Returns: The response from the LLM
    func sendChatMessage(
        prompt: String,
        agentId: String? = nil,
        model: String? = nil,
        cookie: String? = nil
    ) async throws -> String {
        print("🤖 [LLM] 开始发送聊天消息")
        print("🤖 [LLM] 提示词 \(prompt)")

        let finalAgentId = agentId ?? defaultAgentId
        let finalModel = model ?? defaultModel
        let finalCookie = cookie ?? defaultCookie

        print("🤖 [LLM] 使用参数 - AgentID: \(finalAgentId), Model: \(finalModel)")
        print("🤖 [LLM] Cookie长度: \(finalCookie.count) 字符")

        isLoading = true
        defer { isLoading = false }

        do {
            var conversationId: String

            // Try to get a valid conversation ID or create a new one if needed
            do {
                print("🤖 [LLM] 确保有效对话...")
                conversationId = try await ensureValidConversation(agentId: finalAgentId, cookie: finalCookie)
                print("🤖 [LLM] 对话ID: \(conversationId)")
            } catch {
                print("🤖 [LLM] 确保对话失败，创建新对话: \(error)")
                // If ensuring a valid conversation fails, invalidate our current conversation and try once more
                isConversationValid = false
                currentConversationId = nil
                conversationId = try await createConversation(agentId: finalAgentId, cookie: finalCookie)
                print("🤖 [LLM] 新对话ID: \(conversationId)")
            }

            // Now send the chat message
            let url = URL(string: "\(baseURL)/chat/\(conversationId)")!
            print("🤖 [LLM] 请求URL: \(url)")

            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.addValue("application/json", forHTTPHeaderField: "Content-Type")

            let requestBody = ChatRequest(
                prompt: prompt,
                agentId: finalAgentId,
                model: finalModel,
                cookie: finalCookie
            )

            do {
            request.httpBody = try JSONEncoder().encode(requestBody)
                print("🤖 [LLM] 请求体大小: \(request.httpBody?.count ?? 0) 字节")
            } catch {
                print("🤖 [LLM] 编码请求体失败: \(error)")
                throw error
            }

            print("🤖 [LLM] 发送HTTP请求...")
            let (data, response) = try await urlSession.data(for: request)
            print("🤖 [LLM] 收到响应，数据大小: \(data.count) 字节")

            guard let httpResponse = response as? HTTPURLResponse else {
                print("🤖 [LLM] 无效的HTTP响应")
                throw NSError(domain: "LLMService", code: 1000, userInfo: [NSLocalizedDescriptionKey: "Invalid response"])
            }

            print("🤖 [LLM] HTTP状态码: \(httpResponse.statusCode)")

            if httpResponse.statusCode != 200 {
                // 打印响应内容以便调试
                if let responseString = String(data: data, encoding: .utf8) {
                    print("🤖 [LLM] 错误响应内容: \(responseString)")
                }

                // Mark conversation as potentially invalid if we get an error
                isConversationValid = false
                throw NSError(domain: "LLMService", code: httpResponse.statusCode, userInfo: [NSLocalizedDescriptionKey: "Failed to send message: HTTP \(httpResponse.statusCode)"])
            }

            // 打印原始响应内容
            if let responseString = String(data: data, encoding: .utf8) {
                print("🤖 [LLM] 原始响应内容: \(responseString)")
            }

            do {
            let chatResponse = try JSONDecoder().decode(ChatResponse.self, from: data)
                print("🤖 [LLM] JSON解析成功，success: \(chatResponse.success)")

            guard chatResponse.success else {
                    print("🤖 [LLM] API返回success=false")
                // Mark conversation as potentially invalid if API returns success=false
                isConversationValid = false
                throw NSError(domain: "LLMService", code: 1001, userInfo: [NSLocalizedDescriptionKey: "Failed to send message: API returned success=false"])
            }

                print("🤖 [LLM] 响应内容长度: \(chatResponse.data.content.count) 字符")
                print("🤖 [LLM] 响应内容预览: \(String(chatResponse.data.content.prefix(200)))...")

            return chatResponse.data.content
            } catch {
                print("🤖 [LLM] JSON解析失败: \(error)")
                throw error
            }
        } catch {
            print("🤖 [LLM] 发送消息失败: \(error)")
            lastError = error.localizedDescription
            throw error
        }
    }

    /// Reset the current conversation
    func resetConversation() {
        currentConversationId = nil
        isConversationValid = false
    }
}

// Example usage:
// Task {
//     do {
//         // Using defaults
//         let response = try await LLMService.shared.sendChatMessage(
//             prompt: "你叫什么名字？"
//         )
//
//         // Or with custom values
//         let customResponse = try await LLMService.shared.sendChatMessage(
//             prompt: "你叫什么名字？",
//             agentId: "customAgent",
//             model: "custom_model",
//             cookie: "custom_cookie"
//         )
//
//         print("LLM Response: \(response)")
//     } catch {
//         print("Error sending message: \(error.localizedDescription)")
//     }
// }
