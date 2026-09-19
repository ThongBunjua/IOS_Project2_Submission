import Foundation

enum API {
    static let baseURL = "https://finnhub.io/api/v1"
    static let defaultKey = "d949na9r01qj2cib71c0d949na9r01qj2cib71cg"

    static var key: String {
        let custom = UserDefaults.standard.string(forKey: "customFinnhubKey")?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return custom.isEmpty ? defaultKey : custom
    }
}

/// Typhoon LLM (OpenAI-compatible chat completions) — used for AI news
/// summaries and the DCA simulator's plain-language explanation.
enum TyphoonAPI {
    static let baseURL = "https://api.opentyphoon.ai/v1"
    static let defaultKey = "sk-8AJNvBzeB99l8d9fzKZGlQOF3gOhJM3amVzLSBE06UQZJdJr"

    static var key: String {
        let custom = UserDefaults.standard.string(forKey: "customTyphoonKey")?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return custom.isEmpty ? defaultKey : custom
    }

    // Verified against GET /v1/models — the only instruct chat model on
    // this account (the others are OCR/ASR-only).
    static let model = "typhoon-v2.5-30b-a3b-instruct"
}
