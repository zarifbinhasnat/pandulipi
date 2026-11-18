import Foundation

enum Tesseract {
    /// Looked up each time so a fresh install is picked up without relaunching.
    /// `PANDULIPI_TESSERACT=none` simulates a Mac without Tesseract (for testing).
    static var path: String? {
        if let forced = ProcessInfo.processInfo.environment["PANDULIPI_TESSERACT"] {
            return FileManager.default.isExecutableFile(atPath: forced) ? forced : nil
        }
        return ["/opt/homebrew/bin/tesseract", "/usr/local/bin/tesseract", "/opt/local/bin/tesseract"]
            .first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    static var isInstalled: Bool { path != nil }

    static func version() -> String? {
        guard let path, let out = try? ProcessRunner.runSync(path, ["--version"]) else { return nil }
        return out.split(separator: "\n").first.map(String.init)
    }

    static func languages() -> [String] {
        guard let path, let out = try? ProcessRunner.runSync(path, ["--list-langs"]) else { return [] }
        return out.split(separator: "\n")
            .map { String($0).trimmed }
            .filter { !$0.isEmpty && !$0.contains(" ") && $0 != "osd" && $0 != "equ" }
            .sorted()
    }

    static func recognize(png: Data, languages: String, psm: Int = 3) async throws -> String {
        guard let path else {
            throw OCRError.message("Tesseract isn't installed. Run: brew install tesseract tesseract-lang")
        }
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("pandulipi-\(UUID().uuidString).png")
        try png.write(to: tmp)
        defer { try? FileManager.default.removeItem(at: tmp) }
        return try await ProcessRunner.run(path, [tmp.path, "stdout", "-l", languages, "--psm", String(psm)])
    }
}

enum ProcessRunner {
    /// Runs a command off the main thread; terminates it if the calling task is cancelled.
    static func run(_ exe: String, _ args: [String]) async throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: exe)
        process.arguments = args
        let out = Pipe(), err = Pipe()
        process.standardOutput = out
        process.standardError = err
        try Task.checkCancellation()

        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (cont: CheckedContinuation<String, Error>) in
                DispatchQueue.global(qos: .userInitiated).async {
                    do {
                        try process.run()
                    } catch {
                        cont.resume(throwing: error)
                        return
                    }
                    let errBox = DataBox()
                    let group = DispatchGroup()
                    group.enter()
                    DispatchQueue.global().async {
                        errBox.data = err.fileHandleForReading.readDataToEndOfFile()
                        group.leave()
                    }
                    let data = out.fileHandleForReading.readDataToEndOfFile()
                    group.wait()
                    process.waitUntilExit()
                    if process.terminationStatus == 0 {
                        cont.resume(returning: String(decoding: data, as: UTF8.self))
                    } else if process.terminationReason == .uncaughtSignal {
                        cont.resume(throwing: CancellationError())
                    } else {
                        let msg = String(decoding: errBox.data, as: UTF8.self).trimmed
                        cont.resume(throwing: OCRError.message(msg.isEmpty ? "\(exe) exited with \(process.terminationStatus)" : msg))
                    }
                }
            }
        } onCancel: {
            if process.isRunning { process.terminate() }
        }
    }

    @discardableResult
    static func runSync(_ exe: String, _ args: [String], cwd: URL? = nil) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: exe)
        process.arguments = args
        if let cwd { process.currentDirectoryURL = cwd }
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        try process.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        let s = String(decoding: data, as: UTF8.self)
        if process.terminationStatus != 0 { throw OCRError.message(s.trimmed) }
        return s
    }
}

private final class DataBox: @unchecked Sendable { var data = Data() }
