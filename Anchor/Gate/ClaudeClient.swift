import Foundation

/// Optional AI reflection questions via the Claude Messages API, using the
/// user's own Anthropic API key. Off by default. What is sent: the passage
/// reference and its text, and (for feedback) the questions and the user's
/// answers. Nothing else from Anchor is ever sent.
struct ClaudeClient {
    enum ClientError: LocalizedError {
        case missingKey, http(Int, String), refused, empty
        var errorDescription: String? {
            switch self {
            case .missingKey: "Add your Anthropic API key in Settings → AI."
            case .http(let code, let message): "Claude API error \(code): \(message)"
            case .refused: "Claude declined this request."
            case .empty: "Claude returned no text."
            }
        }
    }

    var key: String? = Keychain.string(.claudeKey)
    var model: String

    private static let endpoint = URL(string: "https://api.anthropic.com/v1/messages")!

    private static let system = """
    You help a Christian reader reflect on the Bible passage they just read in a short daily devotional app. \
    Be warm, brief and encouraging. Stay with the text itself; don't add doctrine the passage doesn't support, \
    and don't moralize. Never grade the person; respond like a thoughtful friend in a small group.
    """

    /// Two or three open questions about the passage.
    func questions(reference: String, passage: String) async throws -> [String] {
        let schema: [String: Any] = [
            "type": "object",
            "properties": ["questions": ["type": "array", "items": ["type": "string"]]],
            "required": ["questions"],
            "additionalProperties": false,
        ]
        let prompt = """
        Passage: \(reference)

        \(passage)

        Write 2 or 3 short, open questions (one sentence each) that help the reader notice what the passage says, \
        what it shows about God, and how it might shape their day. Return them in the `questions` array.
        """
        let text = try await send(prompt, format: ["type": "json_schema", "schema": schema])
        struct Out: Decodable { let questions: [String] }
        let out = try JSONDecoder().decode(Out.self, from: Data(text.utf8))
        return Array(out.questions.prefix(3))
    }

    /// Gentle feedback on the reader's answers.
    func feedback(reference: String, passage: String, questions: [String], answers: [String]) async throws -> String {
        let qa = zip(questions, answers).enumerated()
            .map { "\($0.offset + 1). \($0.element.0)\nAnswer: \($0.element.1.isEmpty ? "(left blank)" : $0.element.1)" }
            .joined(separator: "\n\n")
        let prompt = """
        Passage: \(reference)

        \(passage)

        The reader answered these questions:

        \(qa)

        In 3–5 sentences, affirm what they noticed, gently point to anything in the passage they might look at again, \
        and end with one short encouragement for today. Plain text, no headings or lists.
        """
        return try await send(prompt, format: nil)
    }

    private func send(_ prompt: String, format: [String: Any]?) async throws -> String {
        guard let key, !key.isEmpty else { throw ClientError.missingKey }
        var outputConfig: [String: Any] = ["effort": "low"]
        if let format { outputConfig["format"] = format }
        let body: [String: Any] = [
            "model": model,
            "max_tokens": 4000,
            "system": Self.system,
            "messages": [["role": "user", "content": prompt]],
            "output_config": outputConfig,
            // If a safety classifier declines, let the API retry on a suitable fallback model.
            "fallbacks": "default",
        ]
        var req = URLRequest(url: Self.endpoint)
        req.httpMethod = "POST"
        req.timeoutInterval = 120
        req.setValue("application/json", forHTTPHeaderField: "content-type")
        req.setValue(key, forHTTPHeaderField: "x-api-key")
        req.setValue("2026-10-21", forHTTPHeaderField: "anthropic-version")
        req.setValue("server-side-fallback-2026-07-01", forHTTPHeaderField: "anthropic-beta")
        req.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, resp) = try await URLSession.shared.data(for: req)
        let code = (resp as? HTTPURLResponse)?.statusCode ?? 0

        struct APIError: Decodable { struct E: Decodable { let message: String }; let error: E }
        guard (200..<300).contains(code) else {
            let message = (try? JSONDecoder().decode(APIError.self, from: data))?.error.message ?? "Request failed"
            throw ClientError.http(code, message)
        }

        struct Response: Decodable {
            struct Block: Decodable { let type: String; let text: String? }
            let content: [Block]
            let stop_reason: String?
        }
        let r = try JSONDecoder().decode(Response.self, from: data)
        if r.stop_reason == "refusal" { throw ClientError.refused }
        let text = r.content.filter { $0.type == "text" }.compactMap(\.text).joined()
        guard !text.isEmpty else { throw ClientError.empty }
        return text
    }
}
