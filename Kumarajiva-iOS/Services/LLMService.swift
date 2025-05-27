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
    private let defaultCookie = "_qimei_uuid42=193010b053510040bdbe959987347987350c2698a9; hy_source=web; _qimei_fingerprint=579ad3031f0737dafe77266cbcb409d8; _qimei_i_3=66c04685c60e02dac5c4fe615b8626e3f2b8f6a04409578be2de7b5e2e93753e626a3f973989e2a0d790; _qimei_h38=72e5991abdbe9599873479870300000f019301; hy_user=changhozhao; hy_token=ybUPT4mXukWon0h18MPy9Z9z/kUm76vaMMrI/RwMoSEjdtz7lJl8vPi66lDYZhkX; _qimei_i_1=4cde5185970f55d2c896af620fd626e9f2e7adf915580785bd872f582593206c616361953980e1dcd784a1e7; hy_source=web; hy_token=ybUPT4mXukWon0h18MPy9Z9z/kUm76vaMMrI/RwMoSEjdtz7lJl8vPi66lDYZhkX; hy_user=changhozhao" // Replace with your actual default cookie
    
    // Private properties
    private var currentConversationId: String? = nil
    private var isConversationValid: Bool = false
     private let baseURL = "http://47.121.117.100:3000/api/llm"
//    private let baseURL = "http://127.0.0.1:3000/api/llm"

    private var cancellables = Set<AnyCancellable>()
    
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
        let (data, response) = try await URLSession.shared.data(for: request)
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
        print("🤖 [LLM] 提示词长度: \(prompt.count) 字符")
        
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
            let (data, response) = try await URLSession.shared.data(for: request)
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
