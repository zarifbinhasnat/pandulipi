import AppKit
import SwiftUI
import UniformTypeIdentifiers

@MainActor
final class AppModel: ObservableObject {
    static let shared = AppModel()
    private let defaults = UserDefaults.standard

    // MARK: Document
    @Published var document: SourceDocument?
    @Published var alert: String?
    @Published var textLayerCoverage: Double = 0
    @Published var legacyFontWarning = false
    @Published var rerunningPages: Set<Int> = []

    // MARK: Settings (persisted)
    @Published var engine: OCREngine { didSet { defaults.set(engine.rawValue, forKey: "engine") } }
    @Published var selectedModel: String { didSet { defaults.set(selectedModel, forKey: "model") } }
    @Published var tessLang: String { didSet { defaults.set(tessLang, forKey: "tessLang") } }
    @Published var modelImageSize: Double { didSet { defaults.set(modelImageSize, forKey: "modelPx") } }
    @Published var tessImageSize: Double { didSet { defaults.set(tessImageSize, forKey: "tessPx") } }
    @Published var dropHeaders: Bool { didSet { defaults.set(dropHeaders, forKey: "dropHeaders") } }
    @Published var customPrompt: String { didSet { defaults.set(customPrompt, forKey: "prompt") } }

    // MARK: Environment
    @Published var models: [OllamaModel] = []
    @Published var ollamaVersion: String?
    @Published var tessLanguages: [String] = []
    let tesseractVersion = Tesseract.version()

    // MARK: Compare
    @Published var comparePage: Int?
    @Published var compareImage: NSImage?
    @Published var tessRun = EngineRun()
    @Published var modelRun = EngineRun()
    @Published var compareSimilarity: Double?
    private var compareTask: Task<Void, Never>?

    // MARK: Transcription job
    @Published var results: [Int: PageResult] = [:]
    @Published var jobFrom = 1
    @Published var jobTo = 1
    @Published var skipDone = true
    @Published var jobRunning = false
    @Published var jobStart: Date?
    @Published var jobEnd: Date?
    @Published var jobPageStart: Date?
    @Published var jobCurrentPage: Int?
    @Published var jobImage: NSImage?
    @Published var jobLiveText = ""
    @Published var jobDone = 0
    @Published var jobTotal = 0
    @Published var jobPageSeconds = 0.0
    @Published var jobError: String?
    private var jobTask: Task<Void, Never>?
    private var activity: NSObjectProtocol?

    // MARK: Export metadata
    @Published var bookTitle = ""
    @Published var bookAuthor = ""
    @Published var bookLanguage = "bn"
    @Published var pageMarkers = false
    @Published var pagesPerChapter = 10

    private init() {
        engine = OCREngine(rawValue: defaults.string(forKey: "engine") ?? "") ?? .ollama
        selectedModel = defaults.string(forKey: "model") ?? ""
        tessLang = defaults.string(forKey: "tessLang") ?? "ben+eng"
        modelImageSize = defaults.object(forKey: "modelPx") as? Double ?? 1600
        tessImageSize = defaults.object(forKey: "tessPx") as? Double ?? 2400
        dropHeaders = defaults.object(forKey: "dropHeaders") as? Bool ?? true
        customPrompt = defaults.string(forKey: "prompt") ?? ""
        tessLanguages = Tesseract.languages()
        bookLanguage = LanguageNames.bcp47(tessLang)
        Task { await refreshModels() }
    }

    var visionModels: [OllamaModel] { models.filter(\.isVision) }

    var engineLabel: String { label(for: engine) }

    func label(for engine: OCREngine) -> String {
        switch engine {
        case .tesseract: return "Tesseract · \(tessLang)"
        case .ollama: return selectedModel.isEmpty ? "No model" : selectedModel
        case .pdfText: return "PDF text layer"
        }
    }

    // MARK: - Ollama

    func refreshModels() async {
        ollamaVersion = await OllamaClient.shared.version()
        guard ollamaVersion != nil else { models = []; return }
        models = (try? await OllamaClient.shared.models()) ?? []
        if !models.contains(where: { $0.name == selectedModel }) {
            selectedModel = visionModels.first?.name ?? models.first?.name ?? ""
        }
    }

    func unloadModels(_ names: [String]) {
        Task {
            for n in names { try? await OllamaClient.shared.unload(model: n) }
        }
    }

    func prompt(for model: String) -> String {
        if !customPrompt.trimmed.isEmpty { return customPrompt }
        let n = model.lowercased()
        if n.hasPrefix("glm-ocr") { return "Text Recognition:" }
        if n.hasPrefix("deepseek-ocr") { return "Free OCR." }
        let lang = LanguageNames.describe(tessLang)
        return """
        You are a precise OCR engine. Transcribe all the text on this book page exactly as printed. \
        The page is most likely written in \(lang).
        Rules:
        - Keep the original language and script. Never translate, correct, or summarize.
        - Follow the natural reading order. Separate paragraphs with one blank line.
        \(dropHeaders ? "- Leave out running headers, footers and page numbers.\n" : "")\
        - Output only the transcribed text: no comments, no markdown, no code fences.
        """
    }

    // MARK: - Opening

    func presentOpenPanel() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.allowedContentTypes = [.pdf, .image]
        panel.message = "Choose a PDF, or several page images"
        if panel.runModal() == .OK { open(urls: panel.urls) }
    }

    func open(urls: [URL]) {
        guard let doc = SourceDocument(urls: urls) else {
            alert = "Couldn't open that file. Pandulipi reads PDFs and page images (PNG, JPEG, TIFF, HEIC)."
            return
        }
        stopJob()
        compareTask?.cancel()
        document = doc
        comparePage = nil
        compareImage = nil
        tessRun = EngineRun()
        modelRun = EngineRun()
        results = loadCache(for: doc)
        jobFrom = 1
        jobTo = doc.pageCount
        jobDone = 0
        jobTotal = 0
        jobStart = nil
        jobEnd = nil
        jobError = nil
        jobImage = nil
        jobLiveText = ""
        bookTitle = doc.title
        bookAuthor = doc.author ?? ""
        compareSimilarity = nil
        textLayerCoverage = doc.textLayerCoverage()
        let sample = (0..<min(5, doc.pageCount)).map { doc.embeddedText(page: $0) }.joined(separator: "\n")
        legacyFontWarning = TextSimilarity.looksLikeLegacyBangla(sample)
        if engine == .pdfText && textLayerCoverage == 0 { engine = .ollama }
        NSDocumentController.shared.noteNewRecentDocumentURL(doc.url)
    }

    // MARK: - Rendering helpers

    private func render(_ doc: SourceDocument, _ page: Int, _ px: Double) async throws -> (CGImage, Data) {
        let result = await Task.detached(priority: .userInitiated) { () -> (CGImage, Data)? in
            guard let img = doc.render(page: page, maxPixel: CGFloat(px)), let png = img.pngData() else { return nil }
            return (img, png)
        }.value
        guard let result else { throw OCRError.message("Couldn't render page \(page + 1).") }
        return result
    }

    // MARK: - Compare

    func compareRandomPage() {
        guard let doc = document, doc.pageCount > 0 else { return }
        var p = Int.random(in: 0..<doc.pageCount)
        if doc.pageCount > 1, p == comparePage { p = (p + 1) % doc.pageCount }
        compare(page: p)
    }

    func compare(page: Int) {
        guard let doc = document else { return }
        compareTask?.cancel()
        comparePage = page
        compareImage = nil
        tessRun = EngineRun()
        modelRun = EngineRun()
        compareSimilarity = nil
        let model = selectedModel
        compareTask = Task {
            if let (img, _) = try? await render(doc, page, 1400) { compareImage = img.nsImage }
            async let a: Void = compareTesseract(doc, page)
            async let b: Void = compareModel(doc, page, model)
            _ = await (a, b)
            if tessRun.state.seconds != nil, modelRun.state.seconds != nil {
                let (x, y) = (tessRun.text, modelRun.text)
                compareSimilarity = await Task.detached { TextSimilarity.ratio(x, y) }.value
            }
        }
    }

    func cancelCompare() {
        compareTask?.cancel()
    }

    private func compareTesseract(_ doc: SourceDocument, _ page: Int) async {
        let start = Date()
        tessRun = EngineRun(state: .running(start: start))
        do {
            let (_, png) = try await render(doc, page, tessImageSize)
            let text = try await Tesseract.recognize(png: png, languages: tessLang)
            tessRun = EngineRun(state: .done(seconds: Date().timeIntervalSince(start)), text: text,
                                detail: "\(text.trimmed.count) characters")
        } catch {
            tessRun.state = Task.isCancelled ? .idle : .failed(error.localizedDescription)
        }
    }

    private func compareModel(_ doc: SourceDocument, _ page: Int, _ model: String) async {
        guard !model.isEmpty else {
            modelRun.state = .failed("No local model selected. Start Ollama and pick a vision model.")
            return
        }
        let start = Date()
        modelRun = EngineRun(state: .running(start: start))
        do {
            let (_, png) = try await render(doc, page, modelImageSize)
            let (text, stats) = try await OllamaClient.shared.transcribe(model: model, png: png, prompt: prompt(for: model)) { t in
                self.modelRun.text = t
            }
            var detail = "\(text.trimmed.count) characters · \(stats.tokens) tokens · \(String(format: "%.1f", stats.tokensPerSecond)) tok/s"
            if stats.loadSeconds > 1 { detail += " · incl. \(Fmt.duration(stats.loadSeconds)) model load" }
            modelRun = EngineRun(state: .done(seconds: Date().timeIntervalSince(start)), text: text, detail: detail)
        } catch {
            modelRun.state = Task.isCancelled ? .idle : .failed(Self.friendly(error))
        }
    }

    static func friendly(_ error: Error) -> String {
        if let u = error as? URLError, u.code == .cannotConnectToHost || u.code == .networkConnectionLost {
            return "Can't reach Ollama on localhost:11434. Open the Ollama app (or run `ollama serve`) and try again."
        }
        return error.localizedDescription
    }

    // MARK: - Transcription job

    var jobETA: Double? {
        guard jobRunning, jobDone > 0 else { return nil }
        let avg = jobPageSeconds / Double(jobDone)
        let current = jobPageStart.map { Date().timeIntervalSince($0) } ?? 0
        let remainingPages = Double(max(0, jobTotal - jobDone - 1))
        return remainingPages * avg + max(0, avg - current)
    }

    func startJob() {
        guard let doc = document, !jobRunning else { return }
        if engine == .pdfText && textLayerCoverage == 0 {
            alert = "This file has no text layer (it's a scan). Use Tesseract or the local model."
            return
        }
        if engine == .ollama && selectedModel.isEmpty {
            alert = "Pick a local model first (or switch the engine to Tesseract)."
            return
        }
        let from = max(1, min(jobFrom, doc.pageCount)), to = max(from, min(jobTo, doc.pageCount))
        let pages = (from...to).map { $0 - 1 }.filter { !skipDone || results[$0] == nil }
        guard !pages.isEmpty else {
            alert = "Every page in \(from)–\(to) is already transcribed. Turn off \"Skip pages already done\" to redo them."
            return
        }
        let engine = engine, model = selectedModel, lang = tessLang
        let px = engine == .ollama ? modelImageSize : tessImageSize
        let prompt = prompt(for: model)
        let label = label(for: engine)

        jobTotal = pages.count
        jobDone = 0
        jobPageSeconds = 0
        jobStart = Date()
        jobEnd = nil
        jobError = nil
        jobRunning = true
        activity = ProcessInfo.processInfo.beginActivity(
            options: [.userInitiated, .idleSystemSleepDisabled], reason: "Transcribing a book")

        jobTask = Task {
            for p in pages {
                if Task.isCancelled { break }
                jobCurrentPage = p
                jobLiveText = ""
                let t0 = Date()
                jobPageStart = t0
                do {
                    let text = try await recognize(doc, p, engine: engine, model: model, lang: lang,
                                                   px: px, prompt: prompt) { img, live in
                        if let img { self.jobImage = img.nsImage }
                        if let live { self.jobLiveText = live }
                    }
                    let secs = Date().timeIntervalSince(t0)
                    results[p] = PageResult(text: text, seconds: secs, engine: label)
                    jobDone += 1
                    jobPageSeconds += secs
                    saveCache()
                } catch {
                    if !Task.isCancelled { jobError = "Stopped at page \(p + 1): \(Self.friendly(error))" }
                    break
                }
            }
            finishJob()
        }
    }

    /// One page through one engine. `update` gets the rendered image, then live text.
    private func recognize(_ doc: SourceDocument, _ p: Int, engine: OCREngine, model: String, lang: String,
                           px: Double, prompt: String,
                           update: @escaping @MainActor (CGImage?, String?) -> Void) async throws -> String {
        if engine == .pdfText {
            let text = await Task.detached { doc.embeddedText(page: p) }.value
            update(nil, text)
            return text
        }
        let (img, png) = try await render(doc, p, px)
        update(img, nil)
        if engine == .tesseract {
            let text = try await Tesseract.recognize(png: png, languages: lang)
            update(nil, text)
            return text
        }
        return try await OllamaClient.shared.transcribe(model: model, png: png, prompt: prompt) { t in
            update(nil, t)
        }.0
    }

    /// Re-runs a single page (used from the Review tab).
    func rerun(page p: Int, with engine: OCREngine) {
        guard let doc = document, !rerunningPages.contains(p) else { return }
        rerunningPages.insert(p)
        let model = selectedModel, lang = tessLang
        let px = engine == .ollama ? modelImageSize : tessImageSize
        let prompt = prompt(for: model), label = label(for: engine)
        Task {
            let t0 = Date()
            do {
                let text = try await recognize(doc, p, engine: engine, model: model, lang: lang,
                                               px: px, prompt: prompt) { _, _ in }
                results[p] = PageResult(text: text, seconds: Date().timeIntervalSince(t0), engine: label)
                saveCache()
            } catch {
                alert = "Page \(p + 1): \(Self.friendly(error))"
            }
            rerunningPages.remove(p)
        }
    }

    /// Saves a manual correction from the Review tab.
    func setText(_ text: String, page p: Int) {
        var r = results[p] ?? PageResult(text: "", seconds: 0, engine: "edited")
        guard r.text != text else { return }
        r.text = text
        if !r.engine.hasSuffix("(edited)") { r.engine += " (edited)" }
        results[p] = r
        saveCache()
    }

    func stopJob() {
        jobTask?.cancel()
        jobTask = nil
        if jobRunning { finishJob() }
    }

    private func finishJob() {
        guard jobRunning else { return }
        jobRunning = false
        jobEnd = Date()
        jobCurrentPage = nil
        jobPageStart = nil
        if let activity { ProcessInfo.processInfo.endActivity(activity) }
        activity = nil
        NSApp.requestUserAttention(.informationalRequest)
    }

    func clearResults() {
        results = [:]
        saveCache()
    }

    // MARK: - Cache (so long books survive quitting)

    private func cacheURL(for doc: SourceDocument) -> URL? {
        guard let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent("Pandulipi/Cache", isDirectory: true) else { return nil }
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent(doc.cacheKey + ".json")
    }

    private func loadCache(for doc: SourceDocument) -> [Int: PageResult] {
        guard let url = cacheURL(for: doc), let data = try? Data(contentsOf: url),
              let r = try? JSONDecoder().decode([Int: PageResult].self, from: data) else { return [:] }
        return r
    }

    private func saveCache() {
        guard let doc = document, let url = cacheURL(for: doc) else { return }
        if results.isEmpty { try? FileManager.default.removeItem(at: url); return }
        if let data = try? JSONEncoder().encode(results) { try? data.write(to: url, options: .atomic) }
    }

    // MARK: - Export

    private var orderedPages: [(index: Int, text: String)] {
        results.keys.sorted().map { ($0, results[$0]!.text) }
    }

    func exportEPUB() {
        guard let doc = document, !results.isEmpty else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [UTType(filenameExtension: "epub") ?? .data]
        panel.nameFieldStringValue = (bookTitle.isEmpty ? doc.title : bookTitle) + ".epub"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let meta = BookMeta(title: bookTitle, author: bookAuthor, language: bookLanguage,
                            pageMarkers: pageMarkers, pagesPerChapter: pagesPerChapter)
        let pages = orderedPages
        let drop = dropHeaders
        Task.detached {
            let cover = doc.render(page: 0, maxPixel: 1400)
            do {
                try EPUBExporter.export(meta: meta, pages: pages, cover: cover, dropPageNumbers: drop, to: url)
                await MainActor.run { NSWorkspace.shared.activateFileViewerSelecting([url]) }
            } catch {
                await MainActor.run { AppModel.shared.alert = "EPUB export failed: \(error.localizedDescription)" }
            }
        }
    }

    func exportText() {
        guard let doc = document, !results.isEmpty else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.plainText]
        panel.nameFieldStringValue = (bookTitle.isEmpty ? doc.title : bookTitle) + ".txt"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let text = EPUBExporter.plainText(pages: orderedPages, dropPageNumbers: dropHeaders, markers: pageMarkers)
        do {
            try text.write(to: url, atomically: true, encoding: .utf8)
            NSWorkspace.shared.activateFileViewerSelecting([url])
        } catch {
            alert = "Export failed: \(error.localizedDescription)"
        }
    }
}
