import Foundation

struct OllamaModel: Decodable, Identifiable, Hashable {
    struct Details: Decodable, Hashable {
        let parameter_size: String?
        let quantization_level: String?
        let family: String?
    }

    let name: String
    let size: Int64
    let details: Details?
    let capabilities: [String]?

    var id: String { name }

    var isVision: Bool {
        if let capabilities { return capabilities.contains("vision") }
        let n = name.lowercased()
        return ["vl", "vision", "llava", "ocr", "minicpm-v", "gemma3", "moondream", "granite3.2-vision"]
            .contains { n.contains($0) }
    }
}

struct OllamaRunning: Decodable, Hashable {
    let name: String
    let size: Int64
    let size_vram: Int64?
}

struct GenerationStats {
    var tokens: Int = 0
    var evalSeconds: Double = 0
    var loadSeconds: Double = 0
    var tokensPerSecond: Double { evalSeconds > 0 ? Double(tokens) / evalSeconds : 0 }
}

final class OllamaClient: @unchecked Sendable {
    static let shared = OllamaClient()

    /// `PANDULIPI_OLLAMA_URL` points the app at another server (or a dead port, to test the no-Ollama path).
    let base = URL(string: ProcessInfo.processInfo.environment["PANDULIPI_OLLAMA_URL"] ?? "http://127.0.0.1:11434")!

    private let session: URLSession = {
        let c = URLSessionConfiguration.default
        c.timeoutIntervalForRequest = 1800 // first token can take a while while the model loads
        c.timeoutIntervalForResource = 6 * 3600
        return URLSession(configuration: c)
    }()

    private func request(_ path: String, method: String = "GET", body: [String: Any]? = nil,
                         timeout: TimeInterval = 30) throws -> URLRequest {
        var req = URLRequest(url: base.appendingPathComponent(path))
        req.httpMethod = method
        req.timeoutInterval = timeout
        if let body {
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.httpBody = try JSONSerialization.data(withJSONObject: body)
        }
        return req
    }

    func version() async -> String? {
        struct V: Decodable { let version: String }
        guard let req = try? request("api/version", timeout: 2),
              let (data, _) = try? await session.data(for: req),
              let v = try? JSONDecoder().decode(V.self, from: data) else { return nil }
        return v.version
    }

    func models() async throws -> [OllamaModel] {
        struct R: Decodable { let models: [OllamaModel] }
        let (data, _) = try await session.data(for: request("api/tags", timeout: 5))
        var models = try JSONDecoder().decode(R.self, from: data).models
        // Older Ollama versions don't include capabilities in /api/tags; ask /api/show.
        for i in models.indices where models[i].capabilities == nil {
            if let caps = try? await capabilities(of: models[i].name) {
                models[i] = OllamaModel(name: models[i].name, size: models[i].size,
                                        details: models[i].details, capabilities: caps)
            }
        }
        return models.sorted { $0.name < $1.name }
    }

    private func capabilities(of model: String) async throws -> [String] {
        struct S: Decodable { let capabilities: [String]? }
        let (data, _) = try await session.data(for: request("api/show", method: "POST", body: ["model": model], timeout: 5))
        return try JSONDecoder().decode(S.self, from: data).capabilities ?? []
    }

    func running() async throws -> [OllamaRunning] {
        struct R: Decodable { let models: [OllamaRunning] }
        let (data, _) = try await session.data(for: request("api/ps", timeout: 3))
        return try JSONDecoder().decode(R.self, from: data).models
    }

    /// Frees the model's RAM right away.
    func unload(model: String) async throws {
        _ = try await session.data(for: request("api/generate", method: "POST",
                                                body: ["model": model, "keep_alive": 0], timeout: 30))
    }

    func delete(model: String) async throws {
        let (data, resp) = try await session.data(for: request("api/delete", method: "DELETE", body: ["model": model]))
        if let http = resp as? HTTPURLResponse, http.statusCode != 200 {
            throw OCRError.message(Self.errorText(data) ?? "Delete failed (\(http.statusCode))")
        }
    }

    /// Downloads a model, reporting (status, completedBytes, totalBytes).
    func pull(model: String, progress: @escaping @MainActor (String, Int64, Int64) -> Void) async throws {
        struct P: Decodable { let status: String?; let total: Int64?; let completed: Int64?; let error: String? }
        let req = try request("api/pull", method: "POST", body: ["model": model, "stream": true], timeout: 600)
        let (bytes, _) = try await session.bytes(for: req)
        for try await line in bytes.lines {
            try Task.checkCancellation()
            guard let p = try? JSONDecoder().decode(P.self, from: Data(line.utf8)) else { continue }
            if let e = p.error { throw OCRError.message(e) }
            await progress(p.status ?? "", p.completed ?? 0, p.total ?? 0)
        }
    }

    /// Sends one page image to a vision model and streams the transcription back.
    func transcribe(model: String, png: Data, prompt: String,
                    onText: @escaping @MainActor (String) -> Void) async throws -> (String, GenerationStats) {
        struct Chunk: Decodable {
            struct Msg: Decodable { let content: String? }
            let message: Msg?
            let done: Bool?
            let error: String?
            let eval_count: Int?
            let eval_duration: Int64?
            let load_duration: Int64?
        }
        let body: [String: Any] = [
            "model": model,
            "stream": true,
            "keep_alive": "15m",
            "messages": [["role": "user", "content": prompt, "images": [png.base64EncodedString()]]],
            "options": ["temperature": 0, "num_predict": 4096, "num_ctx": 8192, "repeat_penalty": 1.05],
        ]
        let req = try request("api/chat", method: "POST", body: body, timeout: 1800)
        let (bytes, resp) = try await session.bytes(for: req)
        if let http = resp as? HTTPURLResponse, http.statusCode != 200 {
            var raw = Data()
            for try await b in bytes { raw.append(b) }
            throw OCRError.message(Self.errorText(raw) ?? "Ollama returned HTTP \(http.statusCode)")
        }
        var text = ""
        var stats = GenerationStats()
        for try await line in bytes.lines {
            try Task.checkCancellation()
            guard let c = try? JSONDecoder().decode(Chunk.self, from: Data(line.utf8)) else { continue }
            if let e = c.error { throw OCRError.message(e) }
            if let piece = c.message?.content, !piece.isEmpty {
                text += piece
                await onText(text)
            }
            if c.done == true {
                stats.tokens = c.eval_count ?? 0
                stats.evalSeconds = Double(c.eval_duration ?? 0) / 1e9
                stats.loadSeconds = Double(c.load_duration ?? 0) / 1e9
            }
        }
        return (text, stats)
    }

    private static func errorText(_ data: Data) -> String? {
        struct E: Decodable { let error: String }
        if let e = try? JSONDecoder().decode(E.self, from: data) { return e.error }
        let s = String(decoding: data, as: UTF8.self).trimmed
        return s.isEmpty ? nil : s
    }
}

/// Vision models worth trying for book OCR. Sizes are approximate download sizes.
struct CatalogModel: Identifiable {
    let name: String
    let size: String
    let note: String
    let bangla: Bool
    var id: String { name }

    static let all: [CatalogModel] = [
        .init(name: "qwen3-vl:8b", size: "~6 GB",
              note: "Best all-round pick for 16 GB Macs. Strong multilingual OCR and reading order; a good first choice for Bangla.",
              bangla: true),
        .init(name: "qwen3-vl:4b", size: "~3.3 GB",
              note: "Faster, lighter Qwen3-VL. Good when RAM is tight; a bit weaker on dense Bangla conjuncts.",
              bangla: true),
        .init(name: "gemma3:12b", size: "~8 GB",
              note: "Broad multilingual training (140+ languages incl. Bengali). Slower, and tight on 16 GB RAM.",
              bangla: true),
        .init(name: "glm-ocr", size: "~2.2 GB",
              note: "Small document-OCR specialist. Very fast; Bangla quality untested, so compare first.",
              bangla: false),
        .init(name: "deepseek-ocr", size: "~6.7 GB",
              note: "OCR specialist (3B). Excellent on English/Chinese layouts; weaker on Indic scripts.",
              bangla: false),
        .init(name: "minicpm-v", size: "~5.5 GB",
              note: "Compact model with high OCR accuracy for its size.",
              bangla: false),
        .init(name: "qwen2.5vl:7b", size: "~6 GB",
              note: "Previous-generation Qwen vision model; solid documents, superseded by Qwen3-VL.",
              bangla: false),
    ]
}
