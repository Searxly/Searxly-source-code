//
//  CloudIntelligenceProvider.swift
//  Searxly
//
//  "Searxly AI" — the cloud / server-backed provider.
//
//  Talks to an OpenAI-compatible Chat Completions endpoint (`POST {baseURL}/chat/completions`).
//  This is deliberately OpenAI-compatible so the SAME code works against:
//    - the user's LOCAL Ollama during development (Ollama exposes an OpenAI-compatible API at
//      http://127.0.0.1:11434/v1) — this is the default, so nothing leaves the Mac yet, AND
//    - a future hosted Searxly AI backend (vLLM on RunPod Serverless, or the Searxly AI gateway)
//      by changing ONLY the base URL + supplying an API key. No code change needed to "go cloud".
//
//  SECURITY / PRIVACY:
//  - Default baseURL points at the user's local Ollama, so by default this provider is on-device.
//  - Any non-localhost baseURL means prompts, RAG context and attached files leave the Mac and go to
//    that server. The Settings UI surfaces this clearly; the provider is opt-in (searxlyAIEnabled).
//  - `apiKey` is an optional Bearer token. For the eventual production path the app should NOT hold a
//    static upstream key — it should send a short-lived per-session token from Sign-In-With-Ethereum to
//    the Searxly AI *gateway*, and the gateway holds the real model key. The plain key field here is a
//    convenience for pointing at your own self-hosted endpoint during bring-up.
//

import Foundation

final class CloudIntelligenceProvider: IntelligenceProvider {

    var capabilities: ProviderCapabilities

    var baseURL: URL      // OpenAI-compatible base, e.g. http://127.0.0.1:11434/v1  (or https://api.searxly.ai/v1)
    var modelName: String // e.g. "searxly-ai" locally, or "Qwen/Qwen2.5-7B-Instruct" on the server
    var apiKey: String    // optional Bearer token (empty for a local Ollama endpoint)

    init(modelName: String = "searxly-ai",
         baseURL: URL = URL(string: "http://127.0.0.1:11434/v1")!,
         apiKey: String = "") {
        self.modelName = modelName
        self.baseURL = baseURL
        self.apiKey = apiKey
        self.capabilities = ProviderCapabilities(
            supportsStreaming: true,
            maxContextTokensApprox: 16384,
            name: "Searxly AI (\(modelName))",
            supportsNativeTools: false   // server models use plain text generation; native tools are the Apple-only path
        )
    }

    // MARK: - Request building

    private func makeRequest(stream: Bool, prompt: String, instructions: String?) throws -> URLRequest {
        var messages: [[String: String]] = []
        if let instructions, !instructions.isEmpty {
            messages.append(["role": "system", "content": instructions])
        }
        messages.append(["role": "user", "content": prompt])

        let url = baseURL.appendingPathComponent("chat/completions")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if !apiKey.isEmpty {
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        }
        request.timeoutInterval = stream ? 300 : 180

        let body: [String: Any] = [
            "model": modelName,
            "messages": messages,
            "stream": stream,
            "temperature": 0.6
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        return request
    }

    // MARK: - One-shot generation

    func generate(prompt: String, instructions: String?) async throws -> String {
        let request = try makeRequest(stream: false, prompt: prompt, instructions: instructions)
        let (data, response) = try await URLSession.shared.data(for: request)

        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            let serverMsg = String(data: data, encoding: .utf8) ?? "unknown error"
            throw NSError(domain: "SearxlyAI", code: 2, userInfo: [
                NSLocalizedDescriptionKey: "Searxly AI error (is the server reachable at \(baseURL)?): \(serverMsg)"
            ])
        }

        let decoded = try JSONDecoder().decode(OpenAIChatResponse.self, from: data)
        if let err = decoded.error?.message, !err.isEmpty {
            throw NSError(domain: "SearxlyAI", code: 3, userInfo: [NSLocalizedDescriptionKey: err])
        }
        return decoded.choices?.first?.message?.content ?? "(no response from Searxly AI)"
    }

    // MARK: - Streaming generation (Server-Sent Events)

    func generateStream(prompt: String, instructions: String?) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            Task {
                do {
                    let request = try makeRequest(stream: true, prompt: prompt, instructions: instructions)
                    let (bytes, response) = try await URLSession.shared.bytes(for: request)

                    guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
                        continuation.finish(throwing: NSError(domain: "SearxlyAI", code: 2, userInfo: [
                            NSLocalizedDescriptionKey: "Searxly AI stream error (is the server reachable at \(baseURL)?)"
                        ]))
                        return
                    }

                    // OpenAI-compatible streaming is SSE: each event is a line like `data: {json}` and the
                    // stream terminates with `data: [DONE]`.
                    for try await line in bytes.lines {
                        guard line.hasPrefix("data:") else { continue }
                        let payload = line.dropFirst("data:".count).trimmingCharacters(in: .whitespaces)
                        if payload == "[DONE]" { break }
                        if payload.isEmpty { continue }
                        guard let data = payload.data(using: .utf8) else { continue }

                        if let chunk = try? JSONDecoder().decode(OpenAIStreamChunk.self, from: data) {
                            if let content = chunk.choices?.first?.delta?.content, !content.isEmpty {
                                continuation.yield(content)
                            }
                            if chunk.choices?.first?.finishReason != nil { break }
                        } else if let errChunk = try? JSONDecoder().decode(OpenAIChatResponse.self, from: data),
                                  let err = errChunk.error?.message, !err.isEmpty {
                            continuation.finish(throwing: NSError(domain: "SearxlyAI", code: 4, userInfo: [NSLocalizedDescriptionKey: err]))
                            return
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
        // Stateless HTTP — nothing to release.
    }
}

// MARK: - OpenAI-compatible response shapes

private struct OpenAIChatResponse: Decodable {
    struct Choice: Decodable {
        struct Message: Decodable { let content: String? }
        let message: Message?
    }
    struct APIError: Decodable { let message: String? }
    let choices: [Choice]?
    let error: APIError?
}

private struct OpenAIStreamChunk: Decodable {
    struct Choice: Decodable {
        struct Delta: Decodable { let content: String? }
        let delta: Delta?
        let finishReason: String?

        enum CodingKeys: String, CodingKey {
            case delta
            case finishReason = "finish_reason"
        }
    }
    let choices: [Choice]?
}
