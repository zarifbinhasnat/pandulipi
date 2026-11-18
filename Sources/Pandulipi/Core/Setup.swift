import AppKit
import Foundation

/// Detects what a new user is missing and fixes it where possible.
enum Setup {
    static let brewPath: String? = ["/opt/homebrew/bin/brew", "/usr/local/bin/brew"]
        .first { FileManager.default.isExecutableFile(atPath: $0) }

    static var ollamaAppURL: URL? {
        if ProcessInfo.processInfo.environment["PANDULIPI_OLLAMA_URL"] != nil { return nil } // test mode
        let candidates = ["/Applications/Ollama.app", NSHomeDirectory() + "/Applications/Ollama.app"]
        return candidates.map(URL.init(fileURLWithPath:)).first { FileManager.default.fileExists(atPath: $0.path) }
            ?? NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.electron.ollama")
    }

    static var ollamaCLIPath: String? {
        if ProcessInfo.processInfo.environment["PANDULIPI_OLLAMA_URL"] != nil { return nil } // test mode
        return ["/opt/homebrew/bin/ollama", "/usr/local/bin/ollama", "/Applications/Ollama.app/Contents/Resources/ollama"]
            .first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    static var ollamaInstalled: Bool { ollamaAppURL != nil || ollamaCLIPath != nil }

    /// A model that fits this Mac's RAM.
    static var recommendedModel: String {
        ProcessInfo.processInfo.physicalMemory >= 15 * 1_073_741_824 ? "qwen3-vl:8b" : "qwen3-vl:4b"
    }

    static let brewInstallCommand =
        #"/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)""#

    /// Starts Ollama: the menu-bar app if present, otherwise `ollama serve` in the background.
    static func startOllama() throws {
        if let app = ollamaAppURL {
            let cfg = NSWorkspace.OpenConfiguration()
            cfg.activates = false
            NSWorkspace.shared.openApplication(at: app, configuration: cfg)
            return
        }
        guard let cli = ollamaCLIPath else { throw OCRError.message("Ollama isn't installed.") }
        let p = Process()
        p.executableURL = URL(fileURLWithPath: cli)
        p.arguments = ["serve"]
        p.standardOutput = FileHandle.nullDevice
        p.standardError = FileHandle.nullDevice
        try p.run()
    }

    /// Runs `brew <args>` and streams its output line by line.
    static func brew(_ args: [String], onLine: @escaping @MainActor (String) -> Void) async throws {
        guard let brewPath else { throw OCRError.message("Homebrew isn't installed.") }
        let p = Process()
        p.executableURL = URL(fileURLWithPath: brewPath)
        p.arguments = args
        var env = ProcessInfo.processInfo.environment
        env["PATH"] = "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
        env["HOMEBREW_NO_AUTO_UPDATE"] = "1"
        env["HOMEBREW_NO_ENV_HINTS"] = "1"
        env["NONINTERACTIVE"] = "1"
        p.environment = env
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = pipe
        pipe.fileHandleForReading.readabilityHandler = { h in
            let data = h.availableData
            guard !data.isEmpty else { return }
            let text = String(decoding: data, as: UTF8.self)
            Task { @MainActor in
                for line in text.split(separator: "\n") where !line.trimmingCharacters(in: .whitespaces).isEmpty {
                    onLine(String(line))
                }
            }
        }
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
                p.terminationHandler = { proc in
                    pipe.fileHandleForReading.readabilityHandler = nil
                    if proc.terminationStatus == 0 { cont.resume() }
                    else { cont.resume(throwing: OCRError.message("brew \(args.joined(separator: " ")) failed (exit \(proc.terminationStatus)). See the log above.")) }
                }
                do { try p.run() } catch { cont.resume(throwing: error) }
            }
        } onCancel: {
            if p.isRunning { p.terminate() }
        }
    }

    static func copy(_ s: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(s, forType: .string)
    }

    static func openTerminal(running command: String) {
        let script = "tell application \"Terminal\" to do script \"\(command.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\""))\"\ntell application \"Terminal\" to activate"
        NSAppleScript(source: script)?.executeAndReturnError(nil)
    }
}
