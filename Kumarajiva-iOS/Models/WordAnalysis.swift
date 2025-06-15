import Foundation

// MARK: - Word Analysis Models

/// 单词智能解析数据模型
struct WordAnalysis: Codable, Identifiable {
    var id: String { word }
    let word: String
    let basicInfo: BasicInfo
    let splitAssociationMethod: String
    let sceneMemory: [SceneMemory]
    let synonymPreciseGuidance: [SynonymGuidance]
    let createdAt: Date
    let updatedAt: Date
    
    // 自定义初始化器
    init(word: String, basicInfo: BasicInfo, splitAssociationMethod: String, sceneMemory: [SceneMemory], synonymPreciseGuidance: [SynonymGuidance], createdAt: Date, updatedAt: Date) {
        self.word = word
        self.basicInfo = basicInfo
        self.splitAssociationMethod = splitAssociationMethod
        self.sceneMemory = sceneMemory
        self.synonymPreciseGuidance = synonymPreciseGuidance
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
    
    enum CodingKeys: String, CodingKey {
        case word
        case basicInfo = "basic_info"
        case splitAssociationMethod = "split_association_method"
        case sceneMemory = "scene_memory"
        case synonymPreciseGuidance = "synonym_precise_guidance"
        case createdAt, updatedAt
    }
}

/// 基本信息
struct BasicInfo: Codable {
    let phoneticNotation: PhoneticNotation
    let annotation: String
    
    enum CodingKeys: String, CodingKey {
        case phoneticNotation = "phonetic_notation"
        case annotation
    }
}

/// 音标信息
struct PhoneticNotation: Codable {
    let british: String
    let american: String
    
    enum CodingKeys: String, CodingKey {
        case british = "British"
        case american = "American"
    }
}

/// 场景记忆
struct SceneMemory: Codable, Identifiable {
    var id: String { scene }
    let scene: String
    
    enum CodingKeys: String, CodingKey {
        case scene
    }
}

/// 同义词精准指导
struct SynonymGuidance: Codable, Identifiable {
    var id: String { synonym }
    let synonym: String
    let explanation: String
    
    enum CodingKeys: String, CodingKey {
        case synonym, explanation
    }
}

// MARK: - Analysis State
enum AnalysisState {
    case notAnalyzed
    case analyzing
    case analyzed(WordAnalysis)
    case failed(String)
}

// MARK: - LLM Response Model
/// LLM API 响应的数据模型
struct LLMAnalysisResponse: Codable {
    let word: String
    let basicInfo: BasicInfo
    let splitAssociationMethod: String
    let sceneMemory: [SceneMemory]
    let synonymPreciseGuidance: [SynonymGuidance]
    
    enum CodingKeys: String, CodingKey {
        case word
        case basicInfo = "basic_info"
        case splitAssociationMethod = "split_association_method"
        case sceneMemory = "scene_memory"
        case synonymPreciseGuidance = "synonym_precise_guidance"
    }
} 