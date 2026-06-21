//
//  OllamaProvider.swift
//  Searxly
//
//  NEW FILE (Phase 0 scaffold, real work in Phase 5).
//  Experimental localhost-only fallback. Explicitly gated behind a secondary
//  "Enable experimental local LLM fallbacks" toggle in Local AI settings.
//  The manager will only instantiate this when the user has turned on the gate
//  AND the primary Apple path is unavailable or deliberately deselected.
//
//  SECURITY: Talks only to whatever baseURL the user has configured in Local AI settings
//  (the UI defaults to and strongly recommends the localhost:11434 used by the official Ollama.app
//  the user downloaded and runs locally). The manager + settings surface always default to the
//  safe localhost value. Remote values are allowed only because the user explicitly typed them;
//  doing so means their prompts, RAG context and attached files will leave the Mac.
//

import Foundation

final class OllamaProvider: IntelligenceProvider {

    var capabilities: ProviderCapabilities   // name includes the concrete model chosen by the user

    var baseURL: URL
    var modelName: String   // User-configurable in settings (the model tag, e.g. "llama3.2", "mistral", etc.)

    init(modelName: String = "llama3.2", baseURL: URL = URL(string: "http://127.0.0.1:11434")!) {
        self.modelName = modelName
        self.baseURL = baseURL
        self.capabilities = ProviderCapabilities(
            supportsStreaming: true,
            maxContextTokensApprox: 8192,
            name: "Ollama (\(modelName))",
            supportsNativeTools: false   // experimental fallback uses plain text generation; native tools are Apple-only path
        )
    }

    func generate(prompt: String, instructions: String?) async throws -> String {
        // Use /api/chat for better context handling and performance on multi-turn chats (Ollama maintains
        // KV cache / conversation state server-side when using the chat endpoint).
        // The "prompt" param here is already the formatted history + current user turn from the engine.
        var messages: [[String: String]] = []
        if let instructions, !instructions.isEmpty {
            messages.append(["role": "system", "content": instructions])
        }
        messages.append(["role": "user", "content": prompt])

        let url = baseURL.appendingPathComponent("api/chat")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 180

        let body: [String: Any] = [
            "model": modelName,
            "messages": messages,
            "stream": false,
            "options": [
                "keep_alive": "10m",
                "num_ctx": 16384
            ]
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            let serverMsg = String(data: data, encoding: .utf8) ?? "unknown error"
            throw NSError(domain: "Ollama", code: 2, userInfo: [
                NSLocalizedDescriptionKey: "Ollama error (is the server running on \(baseURL)?): \(serverMsg)"
            ])
        }

        struct OllamaChatResp: Decodable {
            struct Message: Decodable {
                let content: String?
            }
            let message: Message?
            let error: String?
            let done: Bool?
        }

        let decoded = try JSONDecoder().decode(OllamaChatResp.self, from: data)
        if let err = decoded.error, !err.isEmpty {
            throw NSError(domain: "Ollama", code: 3, userInfo: [NSLocalizedDescriptionKey: err])
        }
        return decoded.message?.content ?? "(no response from Ollama)"
    }

    func generateStream(prompt: String, instructions: String?) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            Task {
                do {
                    // Use /api/chat + proper messages array. This lets Ollama maintain internal
                    // conversation state / KV cache between turns, which is much faster for follow-ups
                    // than re-sending a giant concatenated prompt to /api/generate every time.
                    var messages: [[String: String]] = []
                    if let instructions, !instructions.isEmpty {
                        messages.append(["role": "system", "content": instructions])
                    }
                    messages.append(["role": "user", "content": prompt])

                    let url = baseURL.appendingPathComponent("api/chat")
                    var request = URLRequest(url: url)
                    request.httpMethod = "POST"
                    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                    request.timeoutInterval = 300

                    let body: [String: Any] = [
                        "model": modelName,
                        "messages": messages,
                        "stream": true,
                        "options": [
                            "keep_alive": "10m",
                            "num_ctx": 16384
                        ]
                    ]
                    request.httpBody = try JSONSerialization.data(withJSONObject: body)

                    let (bytes, response) = try await URLSession.shared.bytes(for: request)

                    guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
                        continuation.finish(throwing: NSError(domain: "Ollama", code: 2, userInfo: [NSLocalizedDescriptionKey: "Ollama stream error"]))
                        return
                    }

                    // /api/chat streams NDJSON with "message": {"content": "..."} + "done"
                    for try await line in bytes.lines {
                        if line.isEmpty { continue }
                        if let data = line.data(using: .utf8) {
                            if let errChunk = try? JSONDecoder().decode(OllamaErrorChunk.self, from: data),
                               let err = errChunk.error, !err.isEmpty {
                                continuation.finish(throwing: NSError(domain: "Ollama", code: 4, userInfo: [NSLocalizedDescriptionKey: err]))
                                return
                            }
                            // Try chat format first
                            if let chatChunk = try? JSONDecoder().decode(OllamaChatStreamChunk.self, from: data) {
                                if let content = chatChunk.message?.content, !content.isEmpty {
                                    continuation.yield(content)
                                }
                                if chatChunk.done == true {
                                    break
                                }
                            } else if let chunk = try? JSONDecoder().decode(OllamaStreamChunk.self, from: data) {
                                // Fallback for old generate format if somehow used
                                if let resp = chunk.response, !resp.isEmpty {
                                    continuation.yield(resp)
                                }
                                if chunk.done == true {
                                    break
                                }
                            }
                        }
                    }

                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    func unload() async {
        // No persistent session to release for basic Ollama HTTP usage.
    }
}

// Small decodable for Ollama streaming chunks
private struct OllamaStreamChunk: Decodable {
    let response: String?
    let done: Bool?
}

// P6: error lines can appear in the NDJSON stream from Ollama.
private struct OllamaErrorChunk: Decodable {
    let error: String?
}

// For /api/chat streaming responses
private struct OllamaChatStreamChunk: Decodable {
    struct Message: Decodable {
        let content: String?
    }
    let message: Message?
    let done: Bool?
}