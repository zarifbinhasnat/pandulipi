import SwiftUI
import UniformTypeIdentifiers

enum MainTab: String, CaseIterable, Identifiable {
    case compare = "Compare"
    case transcribe = "Transcribe"
    case review = "Review"
    var id: String { rawValue }
}

struct ContentView: View {
    @EnvironmentObject var app: AppModel
    @State private var tab: MainTab = .compare
    @State private var showModels = false
    @State private var dropTargeted = false

    var body: some View {
        NavigationSplitView {
            SidebarView(showModels: $showModels)
                .navigationSplitViewColumnWidth(min: 270, ideal: 300, max: 380)
        } detail: {
            Group {
                if app.document == nil {
                    WelcomeView(showModels: $showModels)
                } else {
                    switch tab {
                    case .compare: CompareView()
                    case .transcribe: TranscribeView()
                    case .review: ReviewView()
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .safeAreaInset(edge: .bottom, spacing: 0) { MemoryBar() }
            .navigationTitle(app.document?.title ?? "Pandulipi")
            .navigationSubtitle(app.document.map { "\($0.pageCount) pages · \($0.kindLabel)" } ?? "")
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Picker("View", selection: $tab) {
                        ForEach(MainTab.allCases) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 280)
                    .disabled(app.document == nil)
                }
                ToolbarItemGroup(placement: .primaryAction) {
                    Button { app.presentOpenPanel() } label: {
                        Label("Open", systemImage: "doc.badge.plus")
                    }
                    .help("Open a PDF or page images (⌘O)")
                    Button {
                        tab = .compare
                        app.compareRandomPage()
                    } label: {
                        Label("Compare Random Page", systemImage: "dice")
                    }
                    .help("Run Tesseract and the local model on a random page, side by side (⌘R)")
                    .disabled(app.document == nil)
                    Button { showModels = true } label: {
                        Label("Models", systemImage: "square.stack.3d.down.right")
                    }
                    .help("Manage and download local models")
                }
            }
        }
        .onDrop(of: [.fileURL], isTargeted: $dropTargeted) { providers in
            loadDrop(providers)
            return true
        }
        .overlay {
            if dropTargeted {
                RoundedRectangle(cornerRadius: 16)
                    .strokeBorder(Color.accentColor, style: StrokeStyle(lineWidth: 3, dash: [10, 6]))
                    .background(Color.accentColor.opacity(0.06))
                    .padding(8)
                    .allowsHitTesting(false)
            }
        }
        .sheet(isPresented: $showModels) { ModelManagerView() }
        .alert("Pandulipi", isPresented: Binding(get: { app.alert != nil }, set: { if !$0 { app.alert = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(app.alert ?? "")
        }
        .onChange(of: app.document?.cacheKey) { _, _ in tab = .compare }
    }

    private func loadDrop(_ providers: [NSItemProvider]) {
        let group = DispatchGroup()
        let box = URLBox()
        for p in providers {
            group.enter()
            _ = p.loadObject(ofClass: URL.self) { url, _ in
                if let url { box.append(url) }
                group.leave()
            }
        }
        group.notify(queue: .main) {
            let urls = box.urls
            Task { @MainActor in if !urls.isEmpty { AppModel.shared.open(urls: urls) } }
        }
    }
}

private final class URLBox: @unchecked Sendable {
    private let lock = NSLock()
    private(set) var urls: [URL] = []
    func append(_ u: URL) { lock.lock(); urls.append(u); lock.unlock() }
}

struct WelcomeView: View {
    @EnvironmentObject var app: AppModel
    @Binding var showModels: Bool

    var body: some View {
        VStack(spacing: 22) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 128, height: 128)
            VStack(spacing: 6) {
                Text("Pandulipi").font(.system(size: 34, weight: .bold, design: .serif))
                Text("Turn scanned books into EPUBs with Tesseract or a local AI model — fully offline.")
                    .foregroundStyle(.secondary)
            }
            Button {
                app.presentOpenPanel()
            } label: {
                Label("Open PDF or Images…", systemImage: "doc.badge.plus")
                    .padding(.horizontal, 10).padding(.vertical, 4)
            }
            .controlSize(.large)
            .buttonStyle(.borderedProminent)
            Text("or drop a file anywhere in this window").font(.callout).foregroundStyle(.tertiary)

            VStack(alignment: .leading, spacing: 10) {
                StatusRow(ok: Tesseract.isInstalled,
                          title: "Tesseract",
                          detail: app.tesseractVersion.map { "\($0) · \(app.tessLanguages.count) languages" + (app.tessLanguages.contains("ben") ? " incl. Bangla" : "") }
                              ?? "Not found — brew install tesseract tesseract-lang")
                StatusRow(ok: app.ollamaVersion != nil,
                          title: "Ollama",
                          detail: app.ollamaVersion.map { "v\($0) running" } ?? "Not running — open the Ollama app")
                StatusRow(ok: !app.visionModels.isEmpty,
                          title: "Vision model",
                          detail: app.visionModels.isEmpty ? "None installed — open Models to download one"
                              : app.visionModels.map(\.name).joined(separator: ", "))
            }
            .padding(16)
            .frame(width: 460, alignment: .leading)
            .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 12))

            HStack {
                Button("Manage Models…") { showModels = true }
                Button("Refresh") { Task { await app.refreshModels() } }
            }
            .buttonStyle(.link)
        }
        .padding(40)
    }
}

struct StatusRow: View {
    let ok: Bool
    let title: String
    let detail: String
    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Image(systemName: ok ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                .foregroundStyle(ok ? .green : .orange)
            Text(title).bold().frame(width: 100, alignment: .leading)
            Text(detail).foregroundStyle(.secondary).textSelection(.enabled)
        }
    }
}
