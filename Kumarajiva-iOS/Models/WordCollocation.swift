import Foundation

struct WordCollocation: Codable, Identifiable {
    var id: String { word }
    let word: String
    let chunks: [Chunk]
    
    struct Chunk: Codable, Identifiable {
        var id: UUID = UUID()
        let chunk: String
        let chunkChinese: String
        let chunkSentence: String
        
        // CodingKeys to map the API response fields to our model
        enum CodingKeys: String, CodingKey {
            case chunk = "chunck"
            case chunkChinese = "chunckChinese"
            case chunkSentence = "chunckSentence"
        }
        
        // Custom decoding to handle potential API response variations
        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            
            // Try to decode the chunk field
            do {
                chunk = try container.decode(String.self, forKey: .chunk)
            } catch {
                // If "chunck" field isn't found, try alternatives
                chunk = try container.decodeIfPresent(String.self, forKey: .chunk) ?? "Unknown"
            }
            
            // Try to decode the chunkChinese field
            do {
                chunkChinese = try container.decode(String.self, forKey: .chunkChinese)
            } catch {
                // If "chunckChinese" field isn't found, use a placeholder
                chunkChinese = try container.decodeIfPresent(String.self, forKey: .chunkChinese) ?? "无翻译"
            }
            
            // Try to decode the chunkSentence field
            do {
                chunkSentence = try container.decode(String.self, forKey: .chunkSentence)
            } catch {
                // If "chunckSentence" field isn't found, use a placeholder
                chunkSentence = try container.decodeIfPresent(String.self, forKey: .chunkSentence) ?? "无例句"
            }
        }
    }
    
    // Init method to handle the case where the API might return empty results
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        
        word = try container.decode(String.self, forKey: .word)
        
        do {
            chunks = try container.decode([Chunk].self, forKey: .chunks)
        } catch {
            // Handle the case where chunks array might be empty or invalid
            chunks = []
        }
    }
    
    enum CodingKeys: String, CodingKey {
        case word
        case chunks
    }
} 