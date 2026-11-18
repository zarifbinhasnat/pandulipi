import SwiftUI

/// Proofread transcribed pages next to the scan, fix text, or re-run a page.
struct ReviewView: View {
    @EnvironmentObject var app: AppModel
    @State private var selected: Int?
    @State private var image: NSImage?
    @State private var draft = ""
    @State private var filter = ""

    private var pages: [Int] {
        guard let doc = app.document else { return [] }
        let all = Array(0..<doc.pageCount)
        if filter.isEmpty { return all }
        return all.filter { (app.results[$0]?.text ?? "").localizedCaseInsensitiveContains(filter) }
    }

    var body: some View {
        HSplitView {
            VStack(spacing: 0) {
                TextField("Search text", text: $filter)
                    .textFieldStyle(.roundedBorder)
                    .padding(8)
                List(pages, id: \.self, selection: $selected) { p in
                    HStack {
                        Image(systemName: app.results[p] == nil ? "circle" : "checkmark.circle.fill")
                            .foregroundStyle(app.results[p] == nil ? Color.secondary : Color.green)
                        VStack(alignment: .leading, spacing: 1) {
                            Text("Page \(p + 1)")
                            if let label = app.pageLabels[p] {
                                Text(label).font(.caption2).foregroundStyle(.purple).lineLimit(1)
                            }
                        }
                        Spacer()
                        if app.rerunningPages.contains(p) { ProgressView().controlSize(.small) }
                        else if let r = app.results[p] {
                            Text(Fmt.duration(r.seconds)).font(.caption).foregroundStyle(.secondary).monospacedDigit()
                        }
                    }
                    .tag(p)
                }
            }
            .frame(minWidth: 180, idealWidth: 200, maxWidth: 260)

            if let p = selected {
                HStack(spacing: 12) {
                    PageImagePane(image: image, caption: "Page \(p + 1)")
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Label(app.results[p]?.engine ?? "Not transcribed yet", systemImage: "pencil.and.list.clipboard")
                                .font(.headline).lineLimit(1)
                            Spacer()
                            Menu {
                                ForEach(OCREngine.allCases.filter { $0 != .pdfText || app.textLayerCoverage > 0 }) { e in
                                    Button(app.label(for: e)) { app.rerun(page: p, with: e) }
                                }
                            } label: {
                                Label("Re-run", systemImage: "arrow.clockwise")
                            }
                            .fixedSize()
                            .disabled(app.rerunningPages.contains(p))
                        }
                        TextEditor(text: $draft)
                            .font(.system(size: 14))
                            .lineSpacing(3)
                            .padding(6)
                            .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 10))
                            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(.quaternary))
                        HStack {
                            Text("\(draft.count) characters").font(.caption).foregroundStyle(.secondary)
                            Spacer()
                            Button("Revert") { draft = app.results[p]?.text ?? "" }
                                .disabled(draft == (app.results[p]?.text ?? ""))
                            Button("Save Correction") { app.setText(draft, page: p) }
                                .buttonStyle(.borderedProminent)
                                .keyboardShortcut("s")
                                .disabled(draft == (app.results[p]?.text ?? ""))
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                .padding(12)
            } else {
                VStack(spacing: 10) {
                    Image(systemName: "text.magnifyingglass").font(.system(size: 44, weight: .light)).foregroundStyle(.secondary)
                    Text("Pick a page to proofread it against the scan.").foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .onAppear { if selected == nil { selected = app.results.keys.min() ?? 0 } }
        .onChange(of: selected) { _, p in load(p) }
        .onChange(of: app.results[selected ?? -1]?.text) { _, t in draft = t ?? "" }
        .task { load(selected) }
    }

    private func load(_ p: Int?) {
        guard let p, let doc = app.document else { return }
        draft = app.results[p]?.text ?? ""
        image = nil
        Task.detached {
            let img = doc.render(page: p, maxPixel: 1600)
            await MainActor.run { if selected == p { image = img?.nsImage } }
        }
    }
}
