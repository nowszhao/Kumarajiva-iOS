import Foundation
import Combine
import CommonCrypto

@MainActor
class AliyunDriveService: ObservableObject {
    static let shared = AliyunDriveService()
    
    // MARK: - Published Properties
    @Published var drives: [AliyunDrive] = []
    @Published var isLoading = false
    @Published var errorMessage: String?
    
    // MARK: - Private Properties
    private let persistentStorage = PersistentStorageManager.shared
    private let apiBase = "https://openapi.alipan.com"  // 统一使用 openapi.alipan.com
    
    // 阿里云盘开放平台配置 (需要在阿里云盘开放平台申请)
    let clientId = "717cbc119af349399f525555efb434e1"  // 从 main.js 获取
    let clientSecret = "0743bd65f7384d5c878f564de7d7276a"
    
    // Token 管理
    private var accessToken: String? {
        get { KeychainHelper.get(key: "aliyun_access_token", service: "com.kumarajiva.ios") }
        set {
            if let token = newValue {
                KeychainHelper.save(key: "aliyun_access_token", value: token, service: "com.kumarajiva.ios")
            } else {
                KeychainHelper.delete(key: "aliyun_access_token", service: "com.kumarajiva.ios")
            }
        }
    }
    
    private var refreshToken: String? {
        get { KeychainHelper.get(key: "aliyun_refresh_token", service: "com.kumarajiva.ios") }
        set {
            if let token = newValue {
                KeychainHelper.save(key: "aliyun_refresh_token", value: token, service: "com.kumarajiva.ios")
            } else {
                KeychainHelper.delete(key: "aliyun_refresh_token", service: "com.kumarajiva.ios")
            }
        }
    }
    
    // Token 过期时间（存储为时间戳）
    private var tokenExpiresAt: Date? {
        get {
            if let timestamp = KeychainHelper.get(key: "aliyun_token_expires_at", service: "com.kumarajiva.ios"),
               let timeInterval = TimeInterval(timestamp) {
                return Date(timeIntervalSince1970: timeInterval)
            }
            return nil
        }
        set {
            if let date = newValue {
                let timestamp = String(date.timeIntervalSince1970)
                KeychainHelper.save(key: "aliyun_token_expires_at", value: timestamp, service: "com.kumarajiva.ios")
            } else {
                KeychainHelper.delete(key: "aliyun_token_expires_at", service: "com.kumarajiva.ios")
            }
        }
    }
    
    // 检查 Token 是否即将过期（提前 5 分钟刷新）
    private var isTokenExpiringSoon: Bool {
        guard let expiresAt = tokenExpiresAt else { return true }
        let fiveMinutesFromNow = Date().addingTimeInterval(5 * 60)
        return expiresAt < fiveMinutesFromNow
    }
    
    private init() {
        loadDrives()
        print("☁️ [AliyunDrive] 服务初始化完成，云盘数量: \(drives.count)")
    }
    
    // MARK: - PKCE 辅助方法
    
    /// 生成 Code Verifier（43-128位随机字符串）
    func generateCodeVerifier() -> String {
        var buffer = [UInt8](repeating: 0, count: 32)
        _ = SecRandomCopyBytes(kSecRandomDefault, buffer.count, &buffer)
        return Data(buffer).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
            .trimmingCharacters(in: .whitespaces)
    }
    
    /// 生成 Code Challenge（SHA256哈希后的Code Verifier）
    func generateCodeChallenge(from verifier: String) -> String {
        guard let data = verifier.data(using: .utf8) else {
            return ""
        }
        
        var hash = [UInt8](repeating: 0, count: Int(CC_SHA256_DIGEST_LENGTH))
        data.withUnsafeBytes {
            _ = CC_SHA256($0.baseAddress, CC_LONG(data.count), &hash)
        }
        
        return Data(hash).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
            .trimmingCharacters(in: .whitespaces)
    }
    
    // MARK: - OAuth 登录流程
    
    /// 获取二维码用于登录
    func getQRCode() async throws -> AliyunQRCodeResponse {
        print("☁️ [AliyunDrive] 开始获取登录二维码")
        
        let url = URL(string: "\(apiBase)/oauth/authorize/qrcode")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let body: [String: Any] = [
            "client_id": clientId,
            "client_secret": clientSecret,
            "scopes": [
                "user:base",
                "file:all:read",
                "file:all:write"
            ],
            "width": 300,
            "height": 300
        ]
        
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw AliyunDriveError.invalidResponse
        }
        
        guard httpResponse.statusCode == 200 else {
            print("❌ [AliyunDrive] 获取二维码失败，状态码: \(httpResponse.statusCode)")
            throw AliyunDriveError.networkError(statusCode: httpResponse.statusCode)
        }
        
        let qrCodeResponse = try JSONDecoder().decode(AliyunQRCodeResponse.self, from: data)
        print("✅ [AliyunDrive] 二维码获取成功，SID: \(qrCodeResponse.sid)")
        
        return qrCodeResponse
    }
    
    /// 检查二维码状态
    func checkQRCodeStatus(sid: String) async throws -> AliyunQRCodeStatusResponse {
        let url = URL(string: "\(apiBase)/oauth/qrcode/\(sid)/status")!
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw AliyunDriveError.invalidResponse
        }
        
        guard httpResponse.statusCode == 200 else {
            throw AliyunDriveError.networkError(statusCode: httpResponse.statusCode)
        }
        
        let statusResponse = try JSONDecoder().decode(AliyunQRCodeStatusResponse.self, from: data)
        return statusResponse
    }
    
    /// 使用授权码获取 Access Token（支持 PKCE 和 client_secret 两种模式）
    func getAccessToken(authCode: String, codeVerifier: String? = nil) async throws {
        print("☁️ [AliyunDrive] 使用授权码获取 Access Token")
        
        let url = URL(string: "\(apiBase)/oauth/access_token")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        
        // 构建请求参数
        var queryItems = [
            URLQueryItem(name: "client_id", value: clientId),
            URLQueryItem(name: "grant_type", value: "authorization_code"),
            URLQueryItem(name: "code", value: authCode)
        ]
        
        // 优先使用 client_secret（机密客户端模式）
        // 如果没有 client_secret，则使用 code_verifier（PKCE 公开客户端模式）
        if !clientSecret.isEmpty {
            print("🔐 [AliyunDrive] 使用 client_secret 模式")
            queryItems.append(URLQueryItem(name: "client_secret", value: clientSecret))
        } else if let verifier = codeVerifier {
            print("🔐 [AliyunDrive] 使用 PKCE 模式")
            print("🔐 [AliyunDrive] Code Verifier 长度: \(verifier.count)")
            queryItems.append(URLQueryItem(name: "code_verifier", value: verifier))
        } else {
            throw AliyunDriveError.invalidResponse
        }
        
        var components = URLComponents()
        components.queryItems = queryItems
        
        // 获取表单编码的字符串
        if let query = components.percentEncodedQuery {
            request.httpBody = query.data(using: .utf8)
            print("🔐 [AliyunDrive] 请求体: \(query)")
        }
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw AliyunDriveError.invalidResponse
        }
        
        guard httpResponse.statusCode == 200 else {
            print("❌ [AliyunDrive] 获取 Token 失败，状态码: \(httpResponse.statusCode)")
            if let errorString = String(data: data, encoding: .utf8) {
                print("❌ [AliyunDrive] 错误详情: \(errorString)")
            }
            throw AliyunDriveError.networkError(statusCode: httpResponse.statusCode)
        }
        
        let tokenResponse = try JSONDecoder().decode(AliyunTokenResponse.self, from: data)
        
        // 保存 Token 和过期时间
        self.accessToken = tokenResponse.accessToken
        self.refreshToken = tokenResponse.refreshToken
        self.tokenExpiresAt = Date().addingTimeInterval(TimeInterval(tokenResponse.expiresIn))
        
        print("✅ [AliyunDrive] Token 获取成功并已保存，有效期至: \(self.tokenExpiresAt?.formatted() ?? "未知")")
    }
    
    /// 刷新 Access Token
    func refreshAccessToken() async throws {
        guard let refreshToken = self.refreshToken else {
            throw AliyunDriveError.noRefreshToken
        }
        
        print("☁️ [AliyunDrive] 刷新 Access Token")
        
        let url = URL(string: "\(apiBase)/oauth/access_token")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let body: [String: Any] = [
            "client_id": clientId,
            "client_secret": clientSecret,
            "grant_type": "refresh_token",
            "refresh_token": refreshToken
        ]
        
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw AliyunDriveError.invalidResponse
        }
        
        guard httpResponse.statusCode == 200 else {
            throw AliyunDriveError.networkError(statusCode: httpResponse.statusCode)
        }
        
        let tokenResponse = try JSONDecoder().decode(AliyunTokenResponse.self, from: data)
        
        // 更新 Token 和过期时间
        self.accessToken = tokenResponse.accessToken
        self.refreshToken = tokenResponse.refreshToken
        self.tokenExpiresAt = Date().addingTimeInterval(TimeInterval(tokenResponse.expiresIn))
        
        print("✅ [AliyunDrive] Token 刷新成功，有效期至: \(self.tokenExpiresAt?.formatted() ?? "未知")")
    }
    
    // MARK: - 云盘操作
    
    /// 添加云盘账号
    func addDrive() async throws {
        guard let token = accessToken else {
            throw AliyunDriveError.notAuthenticated
        }
        
        print("☁️ [AliyunDrive] 开始添加云盘账号")
        isLoading = true
        errorMessage = nil
        
        do {
            // 1. 获取用户信息（包含 driveId）
            let userInfo = try await getUserInfo(token: token)
            
            // 2. 获取云盘容量信息
            let spaceInfo = try await getDriveSpaceInfo(token: token)
            
            // 3. 创建 AliyunDrive 对象（不再自动扫描，改为文件浏览器模式）
            let drive = AliyunDrive(
                driveId: userInfo.resourceDriveId!,
                userId: userInfo.userId,
                nickname: userInfo.nickName,
                avatar: userInfo.avatar,
                totalSize: spaceInfo.personalSpaceInfo.totalSize,
                usedSize: spaceInfo.personalSpaceInfo.usedSize,
                mediaFiles: []  // 使用文件浏览器，不需要预加载
            )
            
            // 5. 检查是否已存在
            if drives.contains(where: { $0.driveId == drive.driveId }) {
                throw AliyunDriveError.alreadyAdded
            }
            
            // 6. 添加并保存
            drives.append(drive)
            saveDrives()
            
            print("✅ [AliyunDrive] 云盘添加成功: \(drive.nickname)")
            print("📊 [AliyunDrive] 媒体文件统计 - 视频: \(drive.videoCount), 音频: \(drive.audioCount)")
            
            isLoading = false
        } catch {
            isLoading = false
            errorMessage = error.localizedDescription
            print("❌ [AliyunDrive] 添加云盘失败: \(error)")
            throw error
        }
    }
    
    /// 获取用户信息
    private func getUserInfo(token: String) async throws -> AliyunUserInfoResponse {
        let url = URL(string: "\(apiBase)/adrive/v1.0/user/getDriveInfo")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw AliyunDriveError.invalidResponse
        }
        
        guard httpResponse.statusCode == 200 else {
            print("❌ [AliyunDrive] 获取用户信息失败，状态码: \(httpResponse.statusCode)")
            if let responseString = String(data: data, encoding: .utf8) {
                print("❌ [AliyunDrive] 响应内容: \(responseString)")
            }
            throw AliyunDriveError.networkError(statusCode: httpResponse.statusCode)
        }
        
        // 打印响应内容用于调试
        if let responseString = String(data: data, encoding: .utf8) {
            print("📥 [AliyunDrive] 用户信息响应: \(responseString)")
        }
        
        do {
            let userInfo = try JSONDecoder().decode(AliyunUserInfoResponse.self, from: data)
            return userInfo
        } catch {
            print("❌ [AliyunDrive] 解析用户信息失败: \(error)")
            if let responseString = String(data: data, encoding: .utf8) {
                print("❌ [AliyunDrive] 原始响应: \(responseString)")
            }
            throw error
        }
    }
    
    /// 获取云盘容量信息
    private func getDriveSpaceInfo(token: String) async throws -> AliyunDriveSpaceInfoResponse {
        let url = URL(string: "\(apiBase)/adrive/v1.0/user/getSpaceInfo")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw AliyunDriveError.invalidResponse
        }
        
        guard httpResponse.statusCode == 200 else {
            print("❌ [AliyunDrive] 获取云盘容量信息失败，状态码: \(httpResponse.statusCode)")
            if let responseString = String(data: data, encoding: .utf8) {
                print("❌ [AliyunDrive] 响应内容: \(responseString)")
            }
            throw AliyunDriveError.networkError(statusCode: httpResponse.statusCode)
        }
        
        // 打印响应内容用于调试
        if let responseString = String(data: data, encoding: .utf8) {
            print("📥 [AliyunDrive] 云盘容量信息响应: \(responseString)")
        }
        
        do {
            let spaceInfo = try JSONDecoder().decode(AliyunDriveSpaceInfoResponse.self, from: data)
            return spaceInfo
        } catch {
            print("❌ [AliyunDrive] 解析云盘容量信息失败: \(error)")
            if let responseString = String(data: data, encoding: .utf8) {
                print("❌ [AliyunDrive] 原始响应: \(responseString)")
            }
            throw error
        }
    }
    
    /// 扫描媒体文件
    private func scanMediaFiles(driveId: String, parentFileId: String = "root", token: String) async throws -> [AliyunMediaFile] {
        print("☁️ [AliyunDrive] 扫描媒体文件，文件夹: \(parentFileId)")
        
        var allMediaFiles: [AliyunMediaFile] = []
        var marker: String? = nil
        
        repeat {
            let response = try await listFilesInternal(driveId: driveId, parentFileId: parentFileId, marker: marker, token: token)
            
            for item in response.items {
                if item.type == "folder" {
                    // 递归扫描子文件夹
                    let subFiles = try await scanMediaFiles(driveId: driveId, parentFileId: item.fileId, token: token)
                    allMediaFiles.append(contentsOf: subFiles)
                } else if item.category == "video" || item.category == "audio" {
                    // 添加媒体文件
                    let duration = parseDuration(item.videoMediaMetadata?.duration)
                    
                    let mediaFile = AliyunMediaFile(
                        fileId: item.fileId,
                        driveId: driveId,
                        parentFileId: parentFileId,
                        name: item.name,
                        type: item.category == "video" ? .video : .audio,
                        size: item.size ?? 0,  // 文件夹为 null，使用 0
                        duration: duration,
                        thumbnailURL: item.thumbnail,
                        category: item.category,
                        createdAt: parseDate(item.createdAt) ?? Date(),
                        updatedAt: parseDate(item.updatedAt) ?? Date()
                    )
                    allMediaFiles.append(mediaFile)
                }
            }
            
            marker = response.nextMarker
        } while marker != nil
        
        print("✅ [AliyunDrive] 扫描完成，找到 \(allMediaFiles.count) 个媒体文件")
        return allMediaFiles
    }
    
    // MARK: - 文件浏览
    
    /// 确保 Token 有效（如果即将过期则自动刷新）
    private func ensureValidToken() async throws {
        // 如果没有 access token，抛出未认证错误
        guard accessToken != nil else {
            throw AliyunDriveError.notAuthenticated
        }
        
        // 如果 Token 即将过期（提前 5 分钟），主动刷新
        if isTokenExpiringSoon {
            print("⏰ [AliyunDrive] Token 即将过期，主动刷新...")
            try await refreshAccessToken()
        }
    }
    
    /// 列出指定文件夹的文件（公开方法，供文件浏览器使用）
    func listFiles(driveId: String, parentFileId: String) async throws -> [AliyunFileItem] {
        // 确保 Token 有效
        try await ensureValidToken()
        
        guard let token = accessToken else {
            throw AliyunDriveError.notAuthenticated
        }
        
        var allItems: [AliyunFileItem] = []
        var marker: String? = nil
        
        // 处理分页
        repeat {
            let response = try await listFilesInternal(
                driveId: driveId,
                parentFileId: parentFileId,
                marker: marker,
                token: token
            )
            allItems.append(contentsOf: response.items)
            marker = response.nextMarker
        } while marker != nil && !marker!.isEmpty
        
        return allItems
    }
    
    /// 列出文件（内部方法）
    private func listFilesInternal(driveId: String, parentFileId: String, marker: String? = nil, token: String) async throws -> AliyunFileListResponse {
        let url = URL(string: "\(apiBase)/adrive/v1.0/openFile/list")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        var body: [String: Any] = [
            "drive_id": driveId,
            "parent_file_id": parentFileId,
            "limit": 100,
            "order_by": "name",
            "order_direction": "ASC"
        ]
        
        if let marker = marker {
            body["marker"] = marker
        }
        
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw AliyunDriveError.invalidResponse
        }
        
        guard httpResponse.statusCode == 200 else {
            print("❌ [AliyunDrive] 列出文件失败，状态码: \(httpResponse.statusCode)")
            if let responseString = String(data: data, encoding: .utf8) {
                print("❌ [AliyunDrive] 响应内容: \(responseString)")
            }
            throw AliyunDriveError.networkError(statusCode: httpResponse.statusCode)
        }
        
        // 打印响应内容用于调试
        if let responseString = String(data: data, encoding: .utf8) {
            print("📥 [AliyunDrive] 文件列表响应: \(responseString.prefix(500))...")
        }
        
        do {
            let fileListResponse = try JSONDecoder().decode(AliyunFileListResponse.self, from: data)
            print("✅ [AliyunDrive] 成功解析文件列表，文件数: \(fileListResponse.items.count)")
            return fileListResponse
        } catch {
            print("❌ [AliyunDrive] 解析文件列表失败: \(error)")
            if let responseString = String(data: data, encoding: .utf8) {
                print("❌ [AliyunDrive] 原始响应: \(responseString)")
            }
            throw error
        }
    }
    
    // MARK: - 播放相关
    
    /// 获取播放 URL（支持 AliyunFileItem）
    func getPlayURL(driveId: String, fileId: String, fileName: String) async throws -> String {
        // 确保 Token 有效
        try await ensureValidToken()
        
        guard let token = accessToken else {
            throw AliyunDriveError.notAuthenticated
        }
        
        print("☁️ [AliyunDrive] 获取播放URL: \(fileName)")
        
        let url = URL(string: "\(apiBase)/adrive/v1.0/openFile/getVideoPreviewPlayInfo")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let body: [String: Any] = [
            "drive_id": driveId,
            "file_id": fileId,
            "category": "live_transcoding",
            "with_play_cursor": true
        ]
        
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw AliyunDriveError.invalidResponse
        }
        
        guard httpResponse.statusCode == 200 else {
            throw AliyunDriveError.networkError(statusCode: httpResponse.statusCode)
        }
        
        let playInfoResponse = try JSONDecoder().decode(AliyunVideoPlayInfoResponse.self, from: data)
        
        guard let playURL = playInfoResponse.videoPreviewPlayInfo.liveTranscodingTaskList.first?.url else {
            throw AliyunDriveError.noPlayURL
        }
        
        print("✅ [AliyunDrive] 播放URL获取成功")
        return playURL
    }
    
    /// 获取播放 URL（兼容旧代码）
    func getPlayURL(for file: AliyunMediaFile) async throws -> String {
        return try await getPlayURL(driveId: file.driveId, fileId: file.fileId, fileName: file.name)
    }
    
    /// 查找字幕文件
    func findSubtitleFiles(for mediaFile: AliyunMediaFile) async throws -> [AliyunSubtitleFile] {
        // 确保 Token 有效
        try await ensureValidToken()
        
        guard let token = accessToken else {
            throw AliyunDriveError.notAuthenticated
        }
        
        print("☁️ [AliyunDrive] 查找字幕文件: \(mediaFile.name)")
        
        // 1. 获取同目录所有文件
        let response = try await listFilesInternal(driveId: mediaFile.driveId, parentFileId: mediaFile.parentFileId, token: token)
        let files = response
        
        // 2. 匹配字幕文件
        let mediaBaseName = (mediaFile.name as NSString).deletingPathExtension
        let subtitleFiles = files.items.compactMap { item -> (file: AliyunSubtitleFile, matchScore: Int)? in
            guard item.type == "file" else { return nil }
            
            let ext = (item.name as NSString).pathExtension.lowercased()
            guard let format = AliyunSubtitleFile.SubtitleFormat(rawValue: ext) else { return nil }
            
            let itemBaseName = (item.name as NSString).deletingPathExtension
            
            // 计算匹配分数
            var matchScore = 0
            
            // 完全匹配 (最高优先级)
            if itemBaseName == mediaBaseName {
                matchScore = 100
            }
            // 包含媒体文件名
            else if itemBaseName.contains(mediaBaseName) {
                matchScore = 50
            }
            // 媒体文件名包含字幕文件名 (处理简短命名)
            else if mediaBaseName.contains(itemBaseName) && itemBaseName.count > 5 {
                matchScore = 30
            }
            // 不匹配
            else {
                return nil
            }
            
            let subtitleFile = AliyunSubtitleFile(
                fileId: item.fileId,
                driveId: mediaFile.driveId,
                name: item.name,
                format: format,
                size: item.size ?? 0
            )
            
            return (subtitleFile, matchScore)
        }
        
        // 3. 按匹配分数和格式优先级排序
        let sortedSubtitles = subtitleFiles
            .sorted { first, second in
                // 先按匹配分数排序
                if first.matchScore != second.matchScore {
                    return first.matchScore > second.matchScore
                }
                // 匹配分数相同时按格式优先级排序
                return first.file.format.priority > second.file.format.priority
            }
            .map { $0.file }
        
        if !sortedSubtitles.isEmpty {
            print("✅ [AliyunDrive] 找到 \(sortedSubtitles.count) 个字幕文件:")
            for (index, subtitle) in sortedSubtitles.prefix(3).enumerated() {
                print("   \(index + 1). \(subtitle.name) (\(subtitle.format.displayName))")
            }
        } else {
            print("⚠️ [AliyunDrive] 未找到匹配的字幕文件")
        }
        
        return sortedSubtitles
    }
    
    /// 下载并解析字幕
    func loadSubtitle(file: AliyunSubtitleFile) async throws -> [Subtitle] {
        // 确保 Token 有效
        try await ensureValidToken()
        
        guard let token = accessToken else {
            throw AliyunDriveError.notAuthenticated
        }
        
        print("☁️ [AliyunDrive] 加载字幕: \(file.name)")
        
        // 1. 获取下载 URL
        let downloadURL = try await getDownloadURL(driveId: file.driveId, fileId: file.fileId, token: token)
        
        // 2. 下载字幕内容
        let (data, _) = try await URLSession.shared.data(from: URL(string: downloadURL)!)
        
        // 3. 尝试多种编码解析
        var content: String?
        
        // 定义要尝试的编码列表
        let encodings: [String.Encoding] = [
            .utf8,
            .utf16,
            .isoLatin1,
            .ascii,
            .windowsCP1252,
            .init(rawValue: CFStringConvertEncodingToNSStringEncoding(CFStringEncoding(CFStringEncodings.GB_18030_2000.rawValue))), // GB18030
            .init(rawValue: CFStringConvertEncodingToNSStringEncoding(CFStringEncoding(CFStringEncodings.dosChineseSimplif.rawValue))), // GBK
            .init(rawValue: CFStringConvertEncodingToNSStringEncoding(CFStringEncoding(CFStringEncodings.EUC_CN.rawValue))), // GB2312
        ]
        
        // 尝试每种编码
        for encoding in encodings {
            if let decodedContent = String(data: data, encoding: encoding) {
                content = decodedContent
                print("✅ [AliyunDrive] 字幕编码识别成功: \(encoding)")
                break
            }
        }
        
        guard let subtitleContent = content else {
            print("❌ [AliyunDrive] 所有编码尝试失败，数据大小: \(data.count) bytes")
            print("❌ [AliyunDrive] 数据前100字节: \(data.prefix(100).map { String(format: "%02x", $0) }.joined())")
            throw AliyunDriveError.invalidSubtitleEncoding
        }
        
        // 4. 调试：打印字幕内容前500字符
        print("📝 [AliyunDrive] 字幕内容预览（前500字符）:")
        print(subtitleContent.prefix(500))
        print("📝 [AliyunDrive] 字幕总长度: \(subtitleContent.count) 字符")
        
        // 5. 根据格式解析
        let subtitles: [Subtitle]
        switch file.format {
        case .ass, .ssa:
            subtitles = try ASSParser.parseASS(content: subtitleContent)
        case .srt:
            subtitles = try SubtitleParser.parseSRT(content: subtitleContent)
        case .vtt:
            subtitles = try SubtitleParser.parseVTT(content: subtitleContent)
        }
        
        print("✅ [AliyunDrive] 字幕解析成功，共 \(subtitles.count) 条")
        return subtitles
    }
    
    /// 获取下载 URL
    private func getDownloadURL(driveId: String, fileId: String, token: String) async throws -> String {
        let url = URL(string: "\(apiBase)/adrive/v1.0/openFile/getDownloadUrl")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let body: [String: Any] = [
            "drive_id": driveId,
            "file_id": fileId
        ]
        
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw AliyunDriveError.invalidResponse
        }
        
        guard httpResponse.statusCode == 200 else {
            throw AliyunDriveError.networkError(statusCode: httpResponse.statusCode)
        }
        
        let downloadResponse = try JSONDecoder().decode(AliyunDownloadURLResponse.self, from: data)
        return downloadResponse.url
    }
    
    /// 删除云盘
    func removeDrive(_ drive: AliyunDrive) throws {
        print("☁️ [AliyunDrive] 删除云盘: \(drive.nickname)")
        drives.removeAll { $0.driveId == drive.driveId }
        saveDrives()
    }
    
    /// 刷新云盘数据
    func refreshDrive(_ drive: AliyunDrive) async throws {
        guard let token = accessToken else {
            throw AliyunDriveError.notAuthenticated
        }
        
        print("☁️ [AliyunDrive] 刷新云盘数据: \(drive.nickname)")
        isLoading = true
        
        do {
            // 重新扫描媒体文件
            let mediaFiles = try await scanMediaFiles(driveId: drive.driveId, token: token)
            
            // 更新云盘信息
            if let index = drives.firstIndex(where: { $0.driveId == drive.driveId }) {
                drives[index].mediaFiles = mediaFiles
                drives[index].updatedAt = Date()
                saveDrives()
            }
            
            isLoading = false
            print("✅ [AliyunDrive] 云盘刷新成功")
        } catch {
            isLoading = false
            throw error
        }
    }
    
    /// 强制重新加载所有数据
    func forceReloadData() async {
        print("☁️ [AliyunDrive] 强制重新加载数据")
        
        for drive in drives {
            do {
                try await refreshDrive(drive)
            } catch {
                print("❌ [AliyunDrive] 刷新云盘失败: \(drive.nickname), 错误: \(error)")
            }
        }
    }
    
    /// 登出
    func logout() {
        print("☁️ [AliyunDrive] 登出")
        accessToken = nil
        refreshToken = nil
        drives.removeAll()
        saveDrives()
    }
    
    // MARK: - 数据持久化
    
    private func loadDrives() {
        do {
            drives = try persistentStorage.loadAliyunDrives()
            print("☁️ [AliyunDrive] 成功加载 \(drives.count) 个云盘")
        } catch {
            print("❌ [AliyunDrive] 加载云盘失败: \(error)")
            drives = []
        }
    }
    
    private func saveDrives() {
        do {
            try persistentStorage.saveAliyunDrives(drives)
            print("☁️ [AliyunDrive] 云盘数据保存成功")
        } catch {
            print("❌ [AliyunDrive] 云盘数据保存失败: \(error)")
            errorMessage = "保存数据失败: \(error.localizedDescription)"
        }
    }
    
    // MARK: - 辅助方法
    
    private func parseDuration(_ durationString: String?) -> TimeInterval {
        guard let durationString = durationString else { return 0 }
        return TimeInterval(durationString) ?? 0
    }
    
    private func parseDate(_ dateString: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        return formatter.date(from: dateString)
    }
}

// MARK: - 错误类型
enum AliyunDriveError: LocalizedError {
    case notAuthenticated
    case noRefreshToken
    case invalidResponse
    case networkError(statusCode: Int)
    case noPlayURL
    case invalidSubtitleEncoding
    case alreadyAdded
    
    var errorDescription: String? {
        switch self {
        case .notAuthenticated:
            return "未登录阿里云盘，请先登录"
        case .noRefreshToken:
            return "无刷新令牌，请重新登录"
        case .invalidResponse:
            return "无效的服务器响应"
        case .networkError(let statusCode):
            return "网络错误，状态码: \(statusCode)"
        case .noPlayURL:
            return "无法获取播放地址"
        case .invalidSubtitleEncoding:
            return "字幕文件编码错误"
        case .alreadyAdded:
            return "该云盘已添加"
        }
    }
}

// MARK: - Keychain Helper
private class KeychainHelper {
    static func save(key: String, value: String, service: String) {
        let data = value.data(using: .utf8)!
        
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecValueData as String: data
        ]
        
        SecItemDelete(query as CFDictionary)
        SecItemAdd(query as CFDictionary, nil)
    }
    
    static func get(key: String, service: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        
        guard status == errSecSuccess,
              let data = result as? Data,
              let string = String(data: data, encoding: .utf8) else {
            return nil
        }
        
        return string
    }
    
    static func delete(key: String, service: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key
        ]
        
        SecItemDelete(query as CFDictionary)
    }
}
