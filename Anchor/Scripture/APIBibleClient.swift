import AnchorCore
import Foundation

/// Optional integration with API.Bible (https://scripture.api.bible) for
/// licensed translations such as NIV or NLT, using the user's own key.
/// Which translations are available depends on that key's licence.
struct APIBibleClient {
    struct BibleSummary: Decodable, Identifiable, Hashable {
        let id: String
        let name: String
        let abbreviationLocal: String?
        var label: String { abbreviationLocal.map { "\($0) — \(name)" } ?? name }
    }

    struct Passage: Decodable {
        let reference: String
        let content: String
        let copyright: String?
    }

    enum ClientError: LocalizedError {
        case missingKey, http(Int), decoding
        var errorDescription: String? {
            switch self {
            case .missingKey: "Add your API.Bible key in Settings → Scripture."
            case .http(let code): code == 401 || code == 403 ? "API.Bible rejected the key (HTTP \(code))." : "API.Bible returned HTTP \(code)."
            case .decoding: "Unexpected response from API.Bible."
            }
        }
    }

    private struct Envelope<T: Decodable>: Decodable { let data: T }

    var key: String? = Keychain.string(.apiBibleKey)
    private static let base = URL(string: "https://api.scripture.api.bible/v1/")!

    func bibles(language: String = "eng") async throws -> [BibleSummary] {
        var c = URLComponents(url: Self.base.appendingPathComponent("bibles"), resolvingAgainstBaseURL: false)!
        c.queryItems = [URLQueryItem(name: "language", value: language)]
        let list: [BibleSummary] = try await get(c.url!)
        return list.sorted { $0.label < $1.label }
    }

    func chapter(_ ref: ChapterRef, bibleID: String) async throws -> Passage {
        var c = URLComponents(url: Self.base.appendingPathComponent("bibles/\(bibleID)/passages/\(ref.apiBibleID)"),
                              resolvingAgainstBaseURL: false)!
        c.queryItems = [
            URLQueryItem(name: "content-type", value: "text"),
            URLQueryItem(name: "include-notes", value: "false"),
            URLQueryItem(name: "include-titles", value: "false"),
            URLQueryItem(name: "include-verse-numbers", value: "true"),
        ]
        return try await get(c.url!)
    }

    private func get<T: Decodable>(_ url: URL) async throws -> T {
        guard let key, !key.isEmpty else { throw ClientError.missingKey }
        var req = URLRequest(url: url)
        req.setValue(key, forHTTPHeaderField: "api-key")
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        let (data, resp) = try await URLSession.shared.data(for: req)
        let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(code) else { throw ClientError.http(code) }
        guard let env = try? JSONDecoder().decode(Envelope<T>.self, from: data) else { throw ClientError.decoding }
        return env.data
    }
}
