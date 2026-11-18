import Foundation

enum OCREngine: String, CaseIterable, Identifiable, Codable {
    case tesseract
    case ollama
    case pdfText

    var id: String { rawValue }
    var label: String {
        switch self {
        case .tesseract: return "Tesseract"
        case .ollama: return "Local model"
        case .pdfText: return "PDF text"
        }
    }
    var symbol: String {
        switch self {
        case .tesseract: return "text.viewfinder"
        case .ollama: return "brain"
        case .pdfText: return "doc.plaintext"
        }
    }
}

struct PageResult: Codable, Equatable {
    var text: String
    var seconds: Double
    var engine: String
}

enum RunState: Equatable {
    case idle
    case running(start: Date)
    case done(seconds: Double)
    case failed(String)

    var isRunning: Bool { if case .running = self { return true } else { return false } }
    var seconds: Double? { if case .done(let s) = self { return s } else { return nil } }
}

struct EngineRun: Equatable {
    var state: RunState = .idle
    var text: String = ""
    var detail: String = ""
}

enum OCRError: LocalizedError {
    case message(String)
    var errorDescription: String? {
        switch self { case .message(let m): return m }
    }
}

enum Fmt {
    static func bytes(_ b: UInt64) -> String {
        let gb = Double(b) / 1_073_741_824
        if gb >= 1 { return String(format: "%.1f GB", gb) }
        return String(format: "%.0f MB", Double(b) / 1_048_576)
    }

    static func duration(_ s: Double) -> String {
        if s.isNaN || s.isInfinite { return "—" }
        if s < 60 { return String(format: "%.1fs", s) }
        let t = Int(s.rounded())
        let h = t / 3600, m = (t % 3600) / 60, sec = t % 60
        return h > 0 ? "\(h)h \(m)m" : "\(m)m \(sec)s"
    }

    static func clock(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateStyle = Calendar.current.isDateInToday(date) ? .none : .short
        f.timeStyle = .short
        return f.string(from: date)
    }
}

/// Human names for Tesseract language codes, used in UI and in the model prompt.
enum LanguageNames {
    static let map: [String: String] = [
        "ben": "Bengali (Bangla)", "eng": "English", "hin": "Hindi", "ara": "Arabic",
        "urd": "Urdu", "asm": "Assamese", "san": "Sanskrit", "fra": "French", "deu": "German",
        "spa": "Spanish", "chi_sim": "Chinese (Simplified)", "chi_tra": "Chinese (Traditional)",
        "jpn": "Japanese", "kor": "Korean", "rus": "Russian", "tam": "Tamil", "tel": "Telugu",
        "nep": "Nepali", "mar": "Marathi", "guj": "Gujarati", "pan": "Punjabi", "fas": "Persian",
    ]

    static func name(_ code: String) -> String { map[code] ?? code }

    static func describe(_ combo: String) -> String {
        combo.split(separator: "+").map { name(String($0)) }.joined(separator: " + ")
    }

    /// Best-guess BCP-47 code for EPUB metadata from a Tesseract combo like "ben+eng".
    static func bcp47(_ combo: String) -> String {
        let first = combo.split(separator: "+").first.map(String.init) ?? "en"
        let table = ["ben": "bn", "eng": "en", "hin": "hi", "ara": "ar", "urd": "ur", "fra": "fr",
                     "deu": "de", "spa": "es", "jpn": "ja", "kor": "ko", "rus": "ru", "chi_sim": "zh-Hans",
                     "chi_tra": "zh-Hant", "asm": "as", "nep": "ne", "tam": "ta", "tel": "te", "fas": "fa"]
        return table[first] ?? "en"
    }
}

extension String {
    var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
}

enum TextSimilarity {
    /// 0...1 similarity from Levenshtein distance over whitespace-normalised characters.
    static func ratio(_ a: String, _ b: String) -> Double {
        let x = Array(a.split(whereSeparator: \.isWhitespace).joined(separator: " ").unicodeScalars)
        let y = Array(b.split(whereSeparator: \.isWhitespace).joined(separator: " ").unicodeScalars)
        if x.isEmpty && y.isEmpty { return 1 }
        if x.isEmpty || y.isEmpty { return 0 }
        var prev = Array(0...y.count), cur = [Int](repeating: 0, count: y.count + 1)
        for i in 1...x.count {
            cur[0] = i
            for j in 1...y.count {
                cur[j] = x[i - 1] == y[j - 1] ? prev[j - 1] : 1 + min(prev[j - 1], prev[j], cur[j - 1])
            }
            swap(&prev, &cur)
        }
        return 1 - Double(prev[y.count]) / Double(max(x.count, y.count))
    }

    /// True when a "Bangla" text layer is really legacy (Bijoy/SutonnyMJ) glyph codes shown as Latin.
    static func looksLikeLegacyBangla(_ s: String) -> Bool {
        let scalars = s.unicodeScalars.filter { !CharacterSet.whitespacesAndNewlines.contains($0) }
        guard scalars.count > 40 else { return false }
        let bengali = scalars.filter { (0x0980...0x09FF).contains($0.value) }.count
        let latin = scalars.filter { CharacterSet.letters.contains($0) && $0.value < 0x0250 }.count
        let odd = scalars.filter { "©ª«¬®¯°±²³´µ¶·¸¹º»¼½¾¿ÀÁÂÃÄÅÆÇÈÉÊËÌÍÎÏÐÑÒÓÔÕÖ×ØÙÚÛÜÝÞßÿ‡†Š¨•–—˜™š›œ".unicodeScalars.contains($0) }.count
        return bengali == 0 && latin > 0 && Double(odd) / Double(scalars.count) > 0.03
    }
}
