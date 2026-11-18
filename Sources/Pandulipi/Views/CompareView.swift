import SwiftUI

struct CompareView: View {
    @EnvironmentObject var app: AppModel
    @State private var pageField = ""

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            if app.comparePage == nil {
                emptyState
            } else {
                HStack(spacing: 12) {
                    PageImagePane(image: app.compareImage, caption: app.comparePage.map { "Page \($0 + 1)" } ?? "")
                    ResultPane(title: "Tesseract", subtitle: app.tessLang, symbol: "text.viewfinder",
                               tint: .orange, run: app.tessRun)
                    ResultPane(title: "Local model", subtitle: app.selectedModel, symbol: "brain",
                               tint: .purple, run: app.modelRun)
                }
                .padding(12)
            }
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            Button {
                app.compareRandomPage()
            } label: {
                Label("Random Page", systemImage: "dice.fill")
            }
            .buttonStyle(.borderedProminent)
            .keyboardShortcut("r")

            HStack(spacing: 4) {
                Text("or page")
                TextField("#", text: $pageField)
                    .frame(width: 56)
                    .onSubmit(runTyped)
                Button("Run", action: runTyped).disabled(Int(pageField) == nil)
            }

            if app.tessRun.state.isRunning || app.modelRun.state.isRunning {
                Button("Cancel", role: .cancel) { app.cancelCompare() }
            }
            Spacer()
            verdict
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    @ViewBuilder private var verdict: some View {
        if let t = app.tessRun.state.seconds, let m = app.modelRun.state.seconds {
            HStack(spacing: 14) {
                if let sim = app.compareSimilarity {
                    Label("\(Int((sim * 100).rounded()))% agreement", systemImage: "equal.circle")
                        .help("How similar the two transcriptions are (character-level). Low agreement means at least one engine struggled — read both.")
                }
                let ratio = m / max(t, 0.01)
                Label(ratio >= 1 ? String(format: "Model %.1f× slower", ratio) : String(format: "Model %.1f× faster", 1 / ratio),
                      systemImage: "speedometer")
            }
            .font(.callout)
            .foregroundStyle(.secondary)
        }
    }

    private func runTyped() {
        guard let n = Int(pageField), let doc = app.document else { return }
        app.compare(page: min(max(1, n), doc.pageCount) - 1)
    }

    private var emptyState: some View {
        VStack(spacing: 14) {
            Image(systemName: "rectangle.split.3x1")
                .font(.system(size: 48, weight: .light))
                .foregroundStyle(.secondary)
            Text("Compare engines on a random page").font(.title2.weight(.semibold))
            Text("Pandulipi picks a page at random and runs Tesseract and your local model on it side by side,\nwith timings, so you can decide which engine to use for the whole book.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
            Button {
                app.compareRandomPage()
            } label: {
                Label("Pick a Random Page", systemImage: "dice.fill").padding(.horizontal, 8).padding(.vertical, 3)
            }
            .controlSize(.large)
            .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct PageImagePane: View {
    let image: NSImage?
    let caption: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label(caption, systemImage: "doc.richtext").font(.headline)
                Spacer()
            }
            ZStack {
                RoundedRectangle(cornerRadius: 10).fill(.quaternary.opacity(0.4))
                if let image {
                    ScrollView([.vertical, .horizontal]) {
                        Image(nsImage: image)
                            .resizable()
                            .interpolation(.high)
                            .scaledToFit()
                            .shadow(radius: 2)
                            .padding(8)
                    }
                } else {
                    ProgressView()
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct ResultPane: View {
    let title: String
    let subtitle: String
    let symbol: String
    let tint: Color
    let run: EngineRun

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Label(title, systemImage: symbol).font(.headline).foregroundStyle(tint)
                Text(subtitle).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                Spacer()
                ElapsedBadge(state: run.state)
            }
            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 10).fill(Color(nsColor: .textBackgroundColor))
                RoundedRectangle(cornerRadius: 10).strokeBorder(.quaternary)
                content.padding(12)
            }
            HStack {
                Text(run.detail).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                Spacer()
                if !run.text.isEmpty {
                    Button {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(run.text, forType: .string)
                    } label: { Label("Copy", systemImage: "doc.on.doc") }
                        .buttonStyle(.borderless)
                        .font(.caption)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder private var content: some View {
        switch run.state {
        case .failed(let msg):
            Label(msg, systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(.red)
                .textSelection(.enabled)
        case .running where run.text.isEmpty:
            VStack(spacing: 8) {
                ProgressView()
                Text(title == "Local model" ? "Loading model & reading the page…" : "Reading the page…")
                    .font(.caption).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .idle where run.text.isEmpty:
            Text("Cancelled").foregroundStyle(.secondary)
        default:
            ScrollView {
                Text(run.text)
                    .font(.system(size: 14))
                    .lineSpacing(3)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
}

struct ElapsedBadge: View {
    let state: RunState

    var body: some View {
        switch state {
        case .running(let start):
            TimelineView(.periodic(from: .now, by: 0.1)) { ctx in
                badge(Fmt.duration(ctx.date.timeIntervalSince(start)), symbol: "timer", color: .blue)
            }
        case .done(let s):
            badge(Fmt.duration(s), symbol: "checkmark.circle.fill", color: .green)
        case .failed:
            badge("Failed", symbol: "xmark.circle.fill", color: .red)
        case .idle:
            EmptyView()
        }
    }

    private func badge(_ text: String, symbol: String, color: Color) -> some View {
        Label(text, systemImage: symbol)
            .font(.callout.monospacedDigit().weight(.medium))
            .foregroundStyle(color)
            .padding(.horizontal, 8).padding(.vertical, 3)
            .background(color.opacity(0.12), in: Capsule())
    }
}
