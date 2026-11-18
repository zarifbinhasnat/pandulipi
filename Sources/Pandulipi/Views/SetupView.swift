import SwiftUI

/// Guides a brand-new user from "nothing installed" to a working engine.
struct SetupChecklist: View {
    @EnvironmentObject var app: AppModel
    var compact = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // 1. Local AI model via Ollama
            SetupStep(
                number: 1,
                done: app.modelReady,
                title: "Local AI model (best for Bangla)",
                detail: modelDetail
            ) {
                if app.ollamaVersion == nil {
                    if Setup.ollamaInstalled {
                        Button(app.ollamaStarting ? "Starting…" : "Start Ollama") { app.startOllama() }
                            .disabled(app.ollamaStarting)
                    } else {
                        Link("Download Ollama", destination: URL(string: "https://ollama.com/download/mac")!)
                            .buttonStyle(.borderedProminent)
                        if Setup.brewPath != nil {
                            Button("Install via Terminal") { Setup.openTerminal(running: "brew install --cask ollama-app && open -a Ollama") }
                                .help("Runs: brew install --cask ollama-app")
                        }
                    }
                } else if app.visionModels.isEmpty {
                    Button("Download \(Setup.recommendedModel)") { app.pull(Setup.recommendedModel) }
                        .buttonStyle(.borderedProminent)
                        .disabled(app.pullName != nil)
                }
            }
            if let name = app.pullName {
                PullProgress(name: name).padding(.leading, 34)
            }
            if let e = app.pullError {
                Label(e, systemImage: "xmark.octagon.fill").font(.caption).foregroundStyle(.red).padding(.leading, 34)
            }

            // 2. Tesseract
            SetupStep(
                number: 2,
                done: Tesseract.isInstalled && app.hasBangla,
                title: "Tesseract (fast, optional)",
                detail: tessDetail
            ) {
                if !(Tesseract.isInstalled && app.hasBangla) {
                    if Setup.brewPath != nil {
                        Button(Tesseract.isInstalled ? "Add Bangla" : "Install") { app.installTesseract() }
                            .disabled(app.setupBusy != nil)
                    } else {
                        Button("Copy command") { Setup.copy("brew install tesseract tesseract-lang") }
                    }
                }
            }
            if Setup.brewPath == nil && !(Tesseract.isInstalled && app.hasBangla) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Tesseract installs with Homebrew, which isn't on this Mac yet.")
                    HStack {
                        Button("Install Homebrew in Terminal") { Setup.openTerminal(running: Setup.brewInstallCommand) }
                        Link("What's Homebrew?", destination: URL(string: "https://brew.sh")!)
                    }
                }
                .font(.caption)
                .padding(.leading, 34)
            }
            if let busy = app.setupBusy {
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        ProgressView().controlSize(.small)
                        Text(busy).font(.callout.weight(.medium))
                        Spacer()
                        Button("Cancel") { app.cancelSetupTask() }.buttonStyle(.link)
                    }
                    ScrollViewReader { proxy in
                        ScrollView {
                            VStack(alignment: .leading, spacing: 1) {
                                ForEach(Array(app.setupLog.enumerated()), id: \.offset) { i, line in
                                    Text(line).font(.caption2.monospaced()).foregroundStyle(.secondary).id(i)
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .frame(height: 90)
                        .onChange(of: app.setupLog.count) { _, n in proxy.scrollTo(n - 1, anchor: .bottom) }
                    }
                }
                .padding(10)
                .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))
                .padding(.leading, 34)
            }
            if let e = app.setupError {
                Label(e, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption).foregroundStyle(.orange).textSelection(.enabled)
                    .padding(.leading, 34)
            }

            if !compact {
                Text(app.canTranscribe
                     ? "You're ready. You only need one engine; having both lets you compare them."
                     : "Set up at least one engine. The local model is more accurate; Tesseract is much faster.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private var modelDetail: String {
        if app.ollamaVersion == nil {
            return Setup.ollamaInstalled ? "Ollama is installed but not running." : "Needs Ollama, a free app that runs AI models on your Mac."
        }
        if app.visionModels.isEmpty {
            return "Ollama v\(app.ollamaVersion!) is running. Download a vision model (\(Setup.recommendedModel) suits \(Fmt.bytes(ProcessInfo.processInfo.physicalMemory)) RAM)."
        }
        return "Ollama v\(app.ollamaVersion!) · \(app.visionModels.map(\.name).joined(separator: ", "))"
    }

    private var tessDetail: String {
        guard let v = app.tesseractVersion else { return "Not installed." }
        return app.hasBangla ? "\(v) · \(app.tessLanguages.count) languages incl. Bangla"
            : "\(v) · Bangla language pack missing (\(app.tessLanguages.joined(separator: ", ")))"
    }
}

struct SetupStep<Actions: View>: View {
    let number: Int
    let done: Bool
    let title: String
    let detail: String
    @ViewBuilder var actions: Actions

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            ZStack {
                Circle().fill(done ? Color.green : Color.secondary.opacity(0.25)).frame(width: 22, height: 22)
                if done { Image(systemName: "checkmark").font(.caption.bold()).foregroundStyle(.white) }
                else { Text("\(number)").font(.caption.bold()) }
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.body.weight(.semibold))
                Text(detail).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 6) { actions }
                .fixedSize()
                .controlSize(.regular)
        }
    }
}

struct PullProgress: View {
    @EnvironmentObject var app: AppModel
    let name: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("Downloading \(name)").font(.callout.weight(.medium))
                Spacer()
                Button("Cancel") { app.cancelPull() }.buttonStyle(.link)
            }
            if app.pullTotal > 0 {
                ProgressView(value: Double(app.pullDone), total: Double(app.pullTotal))
                Text("\(app.pullStatus) — \(Fmt.bytes(UInt64(app.pullDone))) of \(Fmt.bytes(UInt64(app.pullTotal)))")
                    .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
            } else {
                ProgressView().progressViewStyle(.linear)
                Text(app.pullStatus).font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(10)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))
    }
}

struct SetupSheet: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Label("Setup", systemImage: "wrench.and.screwdriver").font(.title2.bold())
                Spacer()
                Button("Done") { dismiss() }.keyboardShortcut(.defaultAction)
            }
            SetupChecklist()
        }
        .padding(20)
        .frame(width: 600)
    }
}
