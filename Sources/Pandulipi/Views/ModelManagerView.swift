import SwiftUI

struct ModelManagerView: View {
    @EnvironmentObject var app: AppModel
    @Environment(\.dismiss) private var dismiss

    @State private var customName = ""
    @State private var pulling: String?
    @State private var pullStatus = ""
    @State private var pullDone: Int64 = 0
    @State private var pullTotal: Int64 = 0
    @State private var pullTask: Task<Void, Never>?
    @State private var error: String?
    @State private var confirmDelete: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Label("Local Models", systemImage: "square.stack.3d.down.right").font(.title2.bold())
                Spacer()
                Button("Done") { dismiss() }.keyboardShortcut(.defaultAction)
            }
            .padding(18)
            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    if app.ollamaVersion == nil {
                        Label("Ollama isn't running. Open the Ollama app, then press Refresh.", systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                        Button("Refresh") { Task { await app.refreshModels() } }
                    }

                    section("Installed") {
                        if app.models.isEmpty {
                            Text("No models yet.").foregroundStyle(.secondary)
                        }
                        ForEach(app.models) { m in
                            HStack(spacing: 10) {
                                Image(systemName: m.isVision ? "eye.fill" : "text.bubble")
                                    .foregroundStyle(m.isVision ? .purple : .secondary)
                                    .frame(width: 20)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(m.name).font(.body.weight(.medium))
                                    Text([Fmt.bytes(UInt64(m.size)), m.details?.parameter_size, m.details?.quantization_level,
                                          m.isVision ? "vision" : "text only — can't read images"]
                                        .compactMap { $0 }.joined(separator: " · "))
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                                if app.selectedModel == m.name {
                                    Label("In use", systemImage: "checkmark").font(.caption).foregroundStyle(.green)
                                } else if m.isVision {
                                    Button("Use") { app.selectedModel = m.name }
                                }
                                Button(role: .destructive) { confirmDelete = m.name } label: { Image(systemName: "trash") }
                                    .buttonStyle(.borderless)
                                    .help("Delete from disk")
                            }
                            .padding(.vertical, 4)
                        }
                    }

                    section("Download a model") {
                        HStack {
                            TextField("Any Ollama model name, e.g. qwen3-vl:8b", text: $customName)
                                .textFieldStyle(.roundedBorder)
                                .onSubmit { pull(customName) }
                            Button("Download") { pull(customName) }
                                .disabled(customName.trimmed.isEmpty || pulling != nil)
                        }
                        Link("Browse vision models on ollama.com", destination: URL(string: "https://ollama.com/search?c=vision")!)
                            .font(.caption)
                        if let pulling {
                            VStack(alignment: .leading, spacing: 4) {
                                HStack {
                                    Text("Downloading \(pulling)").font(.callout.weight(.medium))
                                    Spacer()
                                    Button("Cancel") { pullTask?.cancel() }.buttonStyle(.link)
                                }
                                if pullTotal > 0 {
                                    ProgressView(value: Double(pullDone), total: Double(pullTotal))
                                    Text("\(pullStatus) — \(Fmt.bytes(UInt64(pullDone))) of \(Fmt.bytes(UInt64(pullTotal)))")
                                        .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                                } else {
                                    ProgressView().progressViewStyle(.linear)
                                    Text(pullStatus).font(.caption).foregroundStyle(.secondary)
                                }
                            }
                            .padding(10)
                            .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))
                        }
                        if let error {
                            Label(error, systemImage: "xmark.octagon.fill").foregroundStyle(.red).font(.caption)
                        }
                    }

                    section("Recommended for book OCR") {
                        Text("All run fully offline. Models marked 🇧🇩 are the best bets for Bangla — test them with Compare before converting a whole book.")
                            .font(.caption).foregroundStyle(.secondary)
                        ForEach(CatalogModel.all) { c in
                            let installed = app.models.contains { $0.name == c.name || $0.name.hasPrefix(c.name + "-") || $0.name == c.name + ":latest" }
                            HStack(alignment: .top, spacing: 10) {
                                Text(c.bangla ? "🇧🇩" : "  ").frame(width: 20)
                                VStack(alignment: .leading, spacing: 2) {
                                    HStack {
                                        Text(c.name).font(.body.monospaced().weight(.medium))
                                        Text(c.size).font(.caption).foregroundStyle(.secondary)
                                    }
                                    Text(c.note).font(.caption).foregroundStyle(.secondary)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                                Spacer()
                                if installed {
                                    Label("Installed", systemImage: "checkmark.circle.fill").font(.caption).foregroundStyle(.green)
                                } else {
                                    Button("Get") { pull(c.name) }.disabled(pulling != nil)
                                }
                            }
                            .padding(.vertical, 3)
                        }
                    }
                }
                .padding(18)
            }
        }
        .frame(width: 640, height: 620)
        .confirmationDialog("Delete \(confirmDelete ?? "")?", isPresented: Binding(get: { confirmDelete != nil }, set: { if !$0 { confirmDelete = nil } })) {
            Button("Delete from disk", role: .destructive) {
                if let name = confirmDelete {
                    Task {
                        do { try await OllamaClient.shared.delete(model: name) } catch { self.error = error.localizedDescription }
                        await app.refreshModels()
                    }
                }
            }
        } message: {
            Text("The model files are removed from Ollama. You can download it again later.")
        }
    }

    private func section<C: View>(_ title: String, @ViewBuilder _ content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.headline)
            content()
        }
    }

    private func pull(_ name: String) {
        let name = name.trimmed
        guard !name.isEmpty, pulling == nil else { return }
        pulling = name
        pullStatus = "Starting…"
        pullDone = 0
        pullTotal = 0
        error = nil
        pullTask = Task {
            do {
                try await OllamaClient.shared.pull(model: name) { status, done, total in
                    pullStatus = status
                    if total > 0 { pullDone = done; pullTotal = total }
                }
                await app.refreshModels()
                if app.models.first(where: { $0.name.hasPrefix(name) })?.isVision == true, app.visionModels.count == 1 {
                    app.selectedModel = app.models.first { $0.name.hasPrefix(name) }!.name
                }
                customName = ""
            } catch {
                if !Task.isCancelled { self.error = AppModel.friendly(error) }
            }
            pulling = nil
        }
    }
}
