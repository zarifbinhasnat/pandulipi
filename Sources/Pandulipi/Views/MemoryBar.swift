import SwiftUI

/// Always-visible RAM meter: system usage, the loaded Ollama model, this app, swap.
struct MemoryBar: View {
    @EnvironmentObject var monitor: SystemMonitor
    @EnvironmentObject var app: AppModel

    private var color: Color {
        switch monitor.fraction {
        case ..<0.70: return .green
        case ..<0.88: return .orange
        default: return .red
        }
    }

    var body: some View {
        HStack(spacing: 14) {
            Label("RAM", systemImage: "memorychip").font(.caption.weight(.semibold))
            GeometryReader { geo in
                let w = geo.size.width
                let modelFrac = min(1, Double(monitor.modelBytes) / Double(max(monitor.total, 1)))
                ZStack(alignment: .leading) {
                    Capsule().fill(.quaternary)
                    Capsule().fill(color.gradient).frame(width: w * monitor.fraction)
                    if modelFrac > 0 {
                        Capsule().fill(Color.purple.opacity(0.85)).frame(width: w * min(modelFrac, monitor.fraction))
                    }
                }
            }
            .frame(width: 180, height: 8)
            .help("Purple = local model, rest = everything else on your Mac")

            Text("\(Fmt.bytes(monitor.used)) / \(Fmt.bytes(monitor.total))")
                .font(.caption.monospacedDigit())
            Divider().frame(height: 12)
            item("brain", monitor.modelBytes > 0 ? "Model \(Fmt.bytes(monitor.modelBytes))" : "Model not loaded",
                 tint: monitor.modelBytes > 0 ? .purple : .secondary)
            item("app", "App \(Fmt.bytes(monitor.app))", tint: .secondary)
            if monitor.swap > 50_000_000 {
                item("arrow.left.arrow.right", "Swap \(Fmt.bytes(monitor.swap))", tint: .orange)
                    .help("macOS is swapping to disk; a smaller model or image size will be faster.")
            }
            item("chart.line.uptrend.xyaxis", "Peak \(Fmt.bytes(monitor.peak))", tint: .secondary)
            Spacer()
            if !monitor.loadedModels.isEmpty && !app.jobRunning {
                Button("Unload model") { app.unloadModels(monitor.loadedModels) }
                    .buttonStyle(.link).font(.caption)
            }
            HStack(spacing: 5) {
                Circle().fill(monitor.ollamaUp ? .green : .red).frame(width: 7, height: 7)
                Text(monitor.ollamaUp ? "Ollama" : "Ollama offline").font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 7)
        .background(.bar)
        .overlay(alignment: .top) { Divider() }
    }

    private func item(_ symbol: String, _ text: String, tint: Color) -> some View {
        Label(text, systemImage: symbol)
            .font(.caption.monospacedDigit())
            .foregroundStyle(tint)
    }
}
