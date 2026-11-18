import SwiftUI

struct SidebarView: View {
    @EnvironmentObject var app: AppModel
    @EnvironmentObject var monitor: SystemMonitor
    @Binding var showModels: Bool
    @State private var showPrompt = false

    private var langOptions: [String] {
        var opts = ["ben+eng", "ben", "eng"].filter { combo in
            combo.split(separator: "+").allSatisfy { app.tessLanguages.contains(String($0)) }
        }
        opts += app.tessLanguages.filter { !opts.contains($0) }
        if !opts.contains(app.tessLang) { opts.insert(app.tessLang, at: 0) }
        return opts
    }

    var body: some View {
        Form {
            if let doc = app.document {
                Section("Book") {
                    LabeledContent("File", value: doc.url.lastPathComponent)
                    LabeledContent("Pages", value: "\(doc.pageCount)")
                    LabeledContent("Transcribed", value: "\(app.results.count) of \(doc.pageCount)")
                    if app.textLayerCoverage > 0 {
                        Label(app.legacyFontWarning
                              ? "Has a text layer, but it looks like a legacy Bijoy/SutonnyMJ font. Use OCR instead."
                              : "This PDF already has a text layer — the PDF text engine reads it instantly.",
                              systemImage: app.legacyFontWarning ? "exclamationmark.triangle" : "bolt.fill")
                            .font(.caption)
                            .foregroundStyle(app.legacyFontWarning ? .orange : .secondary)
                    }
                }
            }

            Section("Engine for transcription") {
                Picker("Engine", selection: $app.engine) {
                    ForEach(OCREngine.allCases.filter { $0 != .pdfText || app.textLayerCoverage > 0 }) {
                        Label($0.label, systemImage: $0.symbol).tag($0)
                    }
                }
                .pickerStyle(.radioGroup)
                .labelsHidden()
                Text("Compare always runs Tesseract and the model side by side.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section {
                HStack {
                    Circle().fill(app.ollamaVersion != nil ? .green : .red).frame(width: 8, height: 8)
                    Text(app.ollamaVersion != nil ? "Ollama running" : "Ollama not running")
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button { Task { await app.refreshModels() } } label: { Image(systemName: "arrow.clockwise") }
                        .buttonStyle(.borderless)
                        .help("Refresh")
                }
                Picker("Model", selection: $app.selectedModel) {
                    if app.models.isEmpty { Text("None").tag("") }
                    ForEach(app.visionModels) { m in
                        Text(m.name).tag(m.name)
                    }
                    let other = app.models.filter { !$0.isVision }
                    if !other.isEmpty {
                        Divider()
                        ForEach(other) { m in Text("\(m.name) (no vision)").tag(m.name) }
                    }
                }
                LabeledContent("Image size") {
                    HStack {
                        Slider(value: $app.modelImageSize, in: 896...2560, step: 64)
                        Text("\(Int(app.modelImageSize))px").monospacedDigit().frame(width: 52, alignment: .trailing)
                    }
                }
                .help("Longest side of the page image sent to the model. Bigger reads small print better but is slower.")
                HStack {
                    Button("Manage Models…") { showModels = true }
                    Spacer()
                    if !monitor.loadedModels.isEmpty {
                        Button("Free RAM") { app.unloadModels(monitor.loadedModels) }
                            .help("Unload the model from memory now (it reloads on next use)")
                    }
                }
            } header: {
                Text("Local model")
            }

            Section("Tesseract") {
                if Tesseract.isInstalled {
                    Picker("Languages", selection: $app.tessLang) {
                        ForEach(langOptions, id: \.self) { code in
                            Text(LanguageNames.describe(code)).tag(code)
                        }
                    }
                    LabeledContent("Image size") {
                        HStack {
                            Slider(value: $app.tessImageSize, in: 1200...4000, step: 100)
                            Text("\(Int(app.tessImageSize))px").monospacedDigit().frame(width: 52, alignment: .trailing)
                        }
                    }
                } else {
                    Text("Not installed. In Terminal run:\nbrew install tesseract tesseract-lang")
                        .font(.caption).textSelection(.enabled)
                }
            }

            Section("Output") {
                Toggle("Drop page numbers & running headers", isOn: $app.dropHeaders)
                DisclosureGroup("Custom model prompt", isExpanded: $showPrompt) {
                    TextEditor(text: $app.customPrompt)
                        .font(.caption.monospaced())
                        .frame(minHeight: 90)
                    Text(app.customPrompt.isEmpty ? "Empty = built-in prompt tuned per model." : "Overrides the built-in prompt.")
                        .font(.caption2).foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
    }
}
