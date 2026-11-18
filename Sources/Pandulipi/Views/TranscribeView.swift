import SwiftUI

struct TranscribeView: View {
    @EnvironmentObject var app: AppModel
    @EnvironmentObject var monitor: SystemMonitor

    var body: some View {
        VStack(spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                setupCard
                progressCard
            }
            .frame(height: 216)

            HStack(spacing: 12) {
                PageImagePane(image: app.jobImage,
                              caption: app.jobCurrentPage.map { "Now reading page \($0 + 1)" } ?? "Current page",
                              loading: app.jobRunning)
                VStack(alignment: .leading, spacing: 8) {
                    Label("Live output", systemImage: "text.alignleft").font(.headline)
                    ZStack(alignment: .topLeading) {
                        RoundedRectangle(cornerRadius: 10).fill(Color(nsColor: .textBackgroundColor))
                        RoundedRectangle(cornerRadius: 10).strokeBorder(.quaternary)
                        ScrollView {
                            Text(app.jobLiveText.isEmpty ? "Text appears here as each page is read." : app.jobLiveText)
                                .foregroundStyle(app.jobLiveText.isEmpty ? .secondary : .primary)
                                .font(.system(size: 14))
                                .lineSpacing(3)
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(12)
                        }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                exportCard.frame(width: 280)
            }
        }
        .padding(12)
    }

    // MARK: Setup

    private var setupCard: some View {
        Card(title: "Transcribe", symbol: "books.vertical") {
            LabeledContent("Engine") {
                Label(app.engineLabel, systemImage: app.engine.symbol).lineLimit(1)
            }
            if let doc = app.document {
                LabeledContent("Pages") {
                    HStack(spacing: 6) {
                        TextField("", value: $app.jobFrom, format: .number).frame(width: 60)
                        Stepper("", value: $app.jobFrom, in: 1...doc.pageCount).labelsHidden()
                        Text("to")
                        TextField("", value: $app.jobTo, format: .number).frame(width: 60)
                        Stepper("", value: $app.jobTo, in: 1...doc.pageCount).labelsHidden()
                        Button("All") { app.jobFrom = 1; app.jobTo = doc.pageCount }.buttonStyle(.link)
                    }
                    .disabled(app.jobRunning)
                }
            }
            Toggle("Skip pages already done (resume)", isOn: $app.skipDone).disabled(app.jobRunning)
            HStack {
                if app.jobRunning {
                    Button(role: .destructive) { app.stopJob() } label: {
                        Label("Stop", systemImage: "stop.fill").frame(minWidth: 90)
                    }
                    .controlSize(.large)
                } else {
                    Button { app.startJob() } label: {
                        Label("Start", systemImage: "play.fill").frame(minWidth: 90)
                    }
                    .controlSize(.large)
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.return, modifiers: .command)
                }
                Spacer()
            }
            if let err = app.jobError {
                Label(err, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption).foregroundStyle(.red).textSelection(.enabled)
                    .lineLimit(3)
            }
        }
    }

    // MARK: Progress

    private var progressCard: some View {
        Card(title: "Progress", symbol: "gauge.with.dots.needle.67percent") {
            TimelineView(.periodic(from: .now, by: 0.5)) { ctx in
                let total = max(app.jobTotal, 1)
                let elapsed = app.jobStart.map { (app.jobEnd ?? ctx.date).timeIntervalSince($0) } ?? 0
                let avg = app.jobDone > 0 ? app.jobPageSeconds / Double(app.jobDone) : nil
                VStack(alignment: .leading, spacing: 10) {
                    ProgressView(value: Double(app.jobDone), total: Double(total))
                    HStack(alignment: .top, spacing: 18) {
                        Stat("Pages", app.jobTotal == 0 ? "—" : "\(app.jobDone) / \(app.jobTotal)")
                        Stat("Elapsed", app.jobStart == nil ? "—" : Fmt.duration(elapsed))
                        Stat("Per page", avg.map { Fmt.duration($0) } ?? "—")
                        Stat("Time left", app.jobETA.map { "~" + Fmt.duration($0) } ?? (app.jobRunning ? "estimating…" : "—"))
                        Stat("Finishes", app.jobETA.map { Fmt.clock(ctx.date.addingTimeInterval($0)) } ?? "—")
                    }
                    if let p = app.jobPageStart {
                        Text("This page: \(Fmt.duration(ctx.date.timeIntervalSince(p))) · Peak RAM \(Fmt.bytes(monitor.peak))")
                            .font(.caption).foregroundStyle(.secondary).monospacedDigit()
                    } else if app.jobEnd != nil, app.jobDone > 0 {
                        Text("Finished \(app.jobDone) pages in \(Fmt.duration(elapsed)). Peak RAM \(Fmt.bytes(monitor.peak)).")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
        }
        .onChange(of: app.jobRunning) { _, running in if running { monitor.resetPeak() } }
    }

    // MARK: Export

    private var exportCard: some View {
        Card(title: "Export", symbol: "book.closed") {
            TextField("Title", text: $app.bookTitle)
            TextField("Author", text: $app.bookAuthor)
            Picker("Language", selection: Binding(get: { app.bookLanguage }, set: { app.userSetLanguage = true; app.bookLanguage = $0 })) {
                Text("Bangla (bn)").tag("bn")
                Text("English (en)").tag("en")
                Text("Hindi (hi)").tag("hi")
                Text("Arabic (ar)").tag("ar")
                if !["bn", "en", "hi", "ar"].contains(app.bookLanguage) { Text(app.bookLanguage).tag(app.bookLanguage) }
            }
            Picker("Chapters", selection: $app.autoChapters) {
                Text("Detect automatically").tag(true)
                Text("Every N pages").tag(false)
            }
            if !app.autoChapters {
                Stepper("Every \(app.pagesPerChapter) pages", value: $app.pagesPerChapter, in: 1...100)
            }
            if !app.structureSummary.isEmpty {
                Label(app.structureSummary, systemImage: "list.bullet.indent")
                    .font(.caption).foregroundStyle(.secondary)
                    .help("Chapters, contents, index, notes and bibliography found in the transcribed pages. Used for the EPUB's table of contents.")
            }
            Toggle("Show page numbers in book", isOn: $app.pageMarkers)
            Text("\(app.results.count) pages ready").font(.caption).foregroundStyle(.secondary)
            Button { app.exportEPUB() } label: {
                Label("Export EPUB…", systemImage: "book").frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .disabled(app.results.isEmpty)
            Button { app.exportText() } label: {
                Label("Export Text…", systemImage: "doc.text").frame(maxWidth: .infinity)
            }
            .disabled(app.results.isEmpty)
        }
    }
}

struct Card<Content: View>: View {
    let title: String
    let symbol: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(title, systemImage: symbol).font(.headline)
            content
        }
        .padding(14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(.quaternary))
    }
}

struct Stat: View {
    let title: String
    let value: String
    init(_ title: String, _ value: String) { self.title = title; self.value = value }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(value).font(.title3.monospacedDigit().weight(.semibold))
        }
    }
}
