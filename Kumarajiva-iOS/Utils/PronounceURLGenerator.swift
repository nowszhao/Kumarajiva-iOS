import Foundation
import CryptoKit

class PronounceURLGenerator {
    private static let SECRET_KEY = "U3uACNRWSDWdcsKm"
    
    struct PronounceInput {
        let product = "webdict"
        let appVersion = 1
        let client = "web"
        let mid = 1
        let vendor = "web"
        let screen = 1
        let model = 1
        let imei = 1
        let network = "wifi"
        let keyfrom = "dick"
        let keyid = "voiceDictWeb"
        let mysticTime: Int64
        let yduuid = "abcdefg"
        let le = "zh"
        let phonetic = ""
        let rate = 4
        let word: String
        let type: String
        let id = ""
    }
    
    private static func createMd5Sign(_ input: String) -> String {
        let inputData = input.data(using: .utf8)!
        let hashed = Insecure.MD5.hash(data: inputData)
        return hashed.map { String(format: "%02hhx", $0) }.joined()
    }
    
    private static func removeEmptyValues(_ dict: [String: Any]) -> [String: Any] {
        var result = dict
        for (key, value) in dict {
            if let strValue = value as? String, strValue.isEmpty {
                result.removeValue(forKey: key)
            }
        }
        return result
    }
    
    static func generatePronounceUrl(word: String, type: String) -> String {
        let inputData = PronounceInput(
            mysticTime: Int64(Date().timeIntervalSince1970 * 1000),
            word: word,
            type: type
        )
        
        // Convert struct to dictionary
        let mirror = Mirror(reflecting: inputData)
        var inputDict = [String: Any]()
        for child in mirror.children {
            if let key = child.label {
                inputDict[key] = child.value
            }
        }
        
        // Remove empty values
        let newInputDict = removeEmptyValues(inputDict)
        
        // Sort keys and add SECRET_KEY
        var sortedKeys = newInputDict.keys.sorted()
        sortedKeys.append("key")
        var signDict = newInputDict
        signDict["key"] = SECRET_KEY
        
        // Create sign query string
        let signQueryString = sortedKeys.map { key in
            let value = signDict[key] ?? ""
            return "\(key)=\(value)"
        }.joined(separator: "&")
        
        // Generate sign and point param
        let sign = createMd5Sign(signQueryString)
        let pointParam = sortedKeys.joined(separator: ",")
        
        // Create final dictionary with sign and pointParam
        var signData = inputDict
        signData["sign"] = sign
        signData["pointParam"] = pointParam
        
        // Generate query string
        let queryString = signData.map { key, value in
            return "\(key)=\(value)"
        }.joined(separator: "&")
        
        // Create final URL
        let url = "https://dict.youdao.com/pronounce/base?\(queryString)"
        return url.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? url
    }
} 