import Foundation

// MARK: - User Model
struct User: Codable, Identifiable {
    let id: Int
    let username: String
    let email: String?
    let avatarUrl: String?
    let loginMethod: String
    let createdAt: TimeInterval
}

// MARK: - Authentication Response Models
struct AuthResponse: Codable {
    let success: Bool
    let data: AuthData
}

struct AuthData: Codable {
    let accessToken: String
    let refreshToken: String
    let tokenType: String
    let expiresIn: String
    let user: User
    let clientType: String
    
    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case refreshToken = "refresh_token"
        case tokenType = "token_type"
        case expiresIn = "expires_in"
        case user
        case clientType = "client_type"
    }
}

struct RefreshTokenResponse: Codable {
    let success: Bool
    let data: RefreshTokenData
}

struct RefreshTokenData: Codable {
    let accessToken: String
    let refreshToken: String
    let tokenType: String
    let expiresIn: String
    
    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case refreshToken = "refresh_token"
        case tokenType = "token_type"
        case expiresIn = "expires_in"
    }
}

struct AuthStatusResponse: Codable {
    let success: Bool
    let data: AuthStatusData
}

struct AuthStatusData: Codable {
    let authenticated: Bool
    let legacyMode: Bool
    let clientType: String
    let user: User?
    
    enum CodingKeys: String, CodingKey {
        case authenticated
        case legacyMode = "legacy_mode"
        case clientType = "client_type"
        case user
    }
}

// MARK: - Profile Response Models
struct ProfileResponse: Codable {
    let success: Bool
    let data: ProfileData
}

struct ProfileData: Codable {
    let user: User
    let stats: UserStats
    let clientType: String
}

struct UserStats: Codable {
    let totalVocabularies: Int
    let masteredVocabularies: Int
    let totalReviews: Int
} 