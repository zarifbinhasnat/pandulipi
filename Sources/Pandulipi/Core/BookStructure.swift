import Foundation

/// What a page is for. Drives chapter splitting, the EPUB table of contents and landmarks.
enum PageKind: String, Codable {
    case body, contents, index, notes, bibliography

    var title: String {
        switch self {
        case .body: return ""
        case .contents: return "Contents"
        case .index: return "Index"
        case .notes: return "Notes"
        case .bibliography: return "Bibliography"
        }
    }

    var epubType: String {
        switch self {
        case .body: return "chapter"
        case .contents: return "toc"
        case .index: return "index"
        case .notes: return "endnotes"
        case .bibliography: return "bibliography"
        }
    }

    /// Pages whose line breaks matter (entries, not prose).
    var keepsLines: Bool { self != .body }
}

enum Block: Equatable {
    case heading(level: Int, text: String)
    case para(String)
    case line(String)
}

struct StructuredPage {
    let index: Int
    var kind: PageKind
    var blocks: [Block]
}

struct BookSection {
    var title: String
    var kind: PageKind
    var firstPage: Int
    var items: [(page: Int, block: Block)] = []
    var subheadings: [(id: String, text: String)] = []
}

enum BookStructure {
    // MARK: Patterns (English + Bangla)

    private static let kindTitles: [(PageKind, String)] = [
        (.contents, #"^(table of )?contents$|^সূচি(পত্র)?$|^সূচী(পত্র)?$|^বিষয়সূচি$"#),
        (.index, #"^(general )?index$|^নির্ঘণ্ট$|^নির্ঘন্ট$|^শব্দসূচি$"#),
        (.notes, #"^(end)?notes$|^notes and references$|^টীকা$|^টীকা ও তথ্যসূত্র$"#),
        (.bibliography, #"^bibliography$|^references$|^works cited$|^further reading$|^select(ed)? bibliography$|^গ্রন্থপঞ্জি$|^তথ্যসূত্র$|^সহায়ক গ্রন্থ$"#),
    ]

    private static let chapterKeyword =
        #"^(chapter|part|book|prologue|epilogue|preface|foreword|introduction|acknowledg(e)?ments?|appendix|conclusion|afterword|অধ্যায়|পরিচ্ছেদ|পর্ব|খণ্ড|ভূমিকা|মুখবন্ধ|প্রাক্কথন|উপসংহার|পরিশিষ্ট|কৃতজ্ঞতা|সূচনা)\b"#

    /// "CHAPTER TWO", "Part 3", "প্রথম অধ্যায়", "অধ্যায় ৫": a label whose title usually follows on the next line.
    private static let chapterLabel =
        #"^(chapter|part|book)\s+\S+$|^\S+\s+(অধ্যায়|পরিচ্ছেদ|পর্ব|খণ্ড)$|^(অধ্যায়|পরিচ্ছেদ|পর্ব|খণ্ড)\s*[০-৯0-9]+$"#

    private static let numberWord =
        #"^((chapter|part)\s+)?([0-9০-৯]+|[ivxlcdm]+|one|two|three|four|five|six|seven|eight|nine|ten|eleven|twelve|thirteen|fourteen|fifteen|sixteen|seventeen|eighteen|nineteen|twenty|thirty|forty)\.?$"#

    /// A line that ends in a page reference: "Wilson, Woodrow, 29, 44–47" or "The Hinge ......... 29".
    private static let endsInPageRef = #"([\s.·…,–-]|^)([0-9০-৯]{1,4}|[ivxlc]{1,6})(\s*[-–]\s*[0-9০-৯]{1,4})?\.?$"#

    private static func matches(_ s: String, _ pattern: String) -> Bool {
        s.range(of: pattern, options: [.regularExpression, .caseInsensitive]) != nil
    }

    // MARK: Analysis

    /// Turns raw OCR text into typed blocks for every page and classifies the page.
    static func analyze(_ pages: [(index: Int, text: String)], dropHeaders: Bool, bookTitle: String = "") -> [StructuredPage] {
        let sorted = pages.sorted { $0.index < $1.index }
        let rawParas = sorted.map { rawParagraphs($0.text) }
        let headers = dropHeaders ? TextCleaner.repeatedEdges(rawParas.map { $0.map(joinLines) }) : []

        var out: [StructuredPage] = []
        var previousKind: PageKind = .body
        var headingKeys: Set<String> = []
        let titleKey = TextCleaner.headerKey(bookTitle)
        if titleKey.count >= 3 { headingKeys.insert(titleKey) }
        for (i, page) in sorted.enumerated() {
            var paras = rawParas[i]
            if dropHeaders {
                paras = stripEdges(paras, headers: headers)
                // Recto headers repeat the chapter title: drop a top line that matches a heading already seen.
                if let f = paras.first, f.count == 1, markedHeading(f[0]) == nil {
                    let k = TextCleaner.headerKey(f[0])
                    if headingKeys.contains(k) || headingKeys.contains(where: { $0.hasSuffix(" " + k) || $0.hasSuffix(k) && k.count > 8 }) {
                        paras.removeFirst()
                    }
                }
            }
            var kind = classify(paras, pageIndex: page.index, previous: previousKind)
            var blocks: [Block] = []
            for (n, lines) in paras.enumerated() {
                let joined = joinLines(lines)
                if let h = markedHeading(lines.first ?? "") {
                    blocks.append(.heading(level: h.level, text: h.text))
                    let rest = Array(lines.dropFirst())
                    if !rest.isEmpty { blocks.append(contentsOf: body(rest, kind: kind)) }
                    continue
                }
                if lines.count == 1, isKindTitle(joined) != nil {
                    blocks.append(.heading(level: 1, text: joined))
                    continue
                }
                if kind == .body, lines.count <= 2, let h = heuristicHeading(joined, position: n, next: n + 1 < paras.count ? joinLines(paras[n + 1]) : nil) {
                    blocks.append(.heading(level: h, text: joined))
                    continue
                }
                // A long title wrapped over several lines: "Two Revolutionaries:" + "Napoleon III and Bismarck".
                if kind == .body, lines.count <= 2, case .heading(1, let t)? = blocks.last,
                   headingContinues(t), joined.split(separator: " ").count <= 10, !joined.hasSuffix(".") {
                    blocks[blocks.count - 1] = .heading(level: 1, text: t + " " + joined)
                    continue
                }
                // The title line right after "CHAPTER TWO" / "প্রথম অধ্যায়".
                if kind == .body, lines.count <= 5, case .heading(1, let label)? = blocks.last,
                   matches(label, chapterLabel) || matches(label, numberWord),
                   lines.allSatisfy({ $0.split(separator: " ").count <= 8 }),
                   joined.split(separator: " ").count <= 20, !joined.hasSuffix(".") {
                    blocks.append(.heading(level: 1, text: joined))
                    continue
                }
                blocks.append(contentsOf: body(lines, kind: kind))
            }
            // Merge "ONE" + "The Hinge" into one heading.
            blocks = mergeNumberedHeadings(blocks)
            for b in blocks {
                if case .heading(1, let t) = b {
                    headingKeys.insert(TextCleaner.headerKey(t))
                    if let colon = t.firstIndex(of: ":") { headingKeys.insert(TextCleaner.headerKey(String(t[t.index(after: colon)...]))) }
                }
            }
            if kind == .body, blocks.isEmpty { kind = previousKind == .body ? .body : previousKind }
            out.append(StructuredPage(index: page.index, kind: kind, blocks: blocks))
            previousKind = kind
        }
        return out
    }

    /// Groups pages into chapters/sections. Falls back to fixed page ranges when nothing is detected.
    static func sections(_ pages: [StructuredPage], fallbackEvery: Int, autoDetect: Bool) -> [BookSection] {
        let hasStructure = pages.contains { p in
            p.kind != .body || p.blocks.contains { if case .heading(1, _) = $0 { return true } else { return false } }
        }
        if !autoDetect || !hasStructure {
            return fixedSections(pages, every: max(1, fallbackEvery))
        }

        var sections: [BookSection] = []
        var current = BookSection(title: "Beginning", kind: .body, firstPage: pages.first?.index ?? 0)
        var subCount = 0
        var lastPage = -10
        func flush() { if !current.items.isEmpty { sections.append(current) } }

        for page in pages {
            if page.kind != current.kind {
                flush()
                current = BookSection(title: page.kind == .body ? "Text" : page.kind.title, kind: page.kind, firstPage: page.index)
            }
            for block in page.blocks {
                if case .heading(let level, let text) = block {
                    if level == 1, current.items.isEmpty {
                        current.title = text                      // heading opens the section we're in
                    } else if level == 1, page.kind == .body {
                        flush()                                   // new chapter
                        current = BookSection(title: text, kind: .body, firstPage: page.index)
                    } else if level >= 2 {
                        subCount += 1
                        current.subheadings.append(("s\(subCount)", text))
                    }
                }
                appendMerging(&current.items, page: page.index, block: block, lastPage: &lastPage)
            }
        }
        flush()
        return sections
    }

    /// Short human summary for the UI, e.g. "7 chapters · Contents · Index".
    static func summary(_ sections: [BookSection]) -> String {
        let chapters = sections.filter { $0.kind == .body && $0.title != "Beginning" && $0.title != "Text" }.count
        var parts = ["\(chapters) chapter\(chapters == 1 ? "" : "s")"]
        for k in [PageKind.contents, .notes, .bibliography, .index] where sections.contains(where: { $0.kind == k }) {
            parts.append(k.title)
        }
        return parts.joined(separator: " · ")
    }

    /// "bn" when most letters are Bengali script, otherwise "en" (used to default the EPUB language).
    static func dominantLanguage(_ texts: [String]) -> String? {
        var bengali = 0, latin = 0
        for t in texts.prefix(20) {
            for u in t.unicodeScalars {
                if (0x0980...0x09FF).contains(u.value) { bengali += 1 }
                else if (0x41...0x7A).contains(u.value) { latin += 1 }
            }
        }
        guard bengali + latin > 200 else { return nil }
        return bengali > latin ? "bn" : "en"
    }

    /// Per-page label for the Review list ("Contents", "Ch: The Hinge").
    static func pageLabels(_ pages: [StructuredPage]) -> [Int: String] {
        var labels: [Int: String] = [:]
        for p in pages {
            if p.kind != .body { labels[p.index] = p.kind.title; continue }
            for b in p.blocks {
                if case .heading(1, let t) = b { labels[p.index] = "§ " + t; break }
            }
        }
        return labels
    }

    // MARK: Helpers

    private static func rawParagraphs(_ raw: String) -> [[String]] {
        var s = raw.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\u{000C}", with: "\n")
        s = s.split(separator: "\n", omittingEmptySubsequences: false)
            .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("```") }
            .joined(separator: "\n")
        s = s.replacingOccurrences(of: "**", with: "").replacingOccurrences(of: "__", with: "")
        let blocks = s.replacingOccurrences(of: #"\n[ \t]*\n"#, with: "\u{1E}", options: .regularExpression)
            .components(separatedBy: "\u{1E}")
            .map { $0.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty } }
            .filter { !$0.isEmpty }

        // Models often skip blank lines: give every "#" heading its own paragraph,
        // and fold a title wrapped over a few short lines back into its heading.
        var split: [[String]] = []
        for para in blocks {
            var cur: [String] = []
            var i = 0
            while i < para.count {
                let line = para[i]
                guard line.hasPrefix("#") else { cur.append(line); i += 1; continue }
                if !cur.isEmpty { split.append(cur); cur = [] }
                var heading = line
                var j = i + 1
                while j < para.count, j - i <= 3, !para[j].hasPrefix("#"),
                      para[j].split(separator: " ").count <= 8, !para[j].hasSuffix("."), !para[j].hasSuffix("।") {
                    heading += " " + para[j]
                    j += 1
                }
                split.append([heading])
                i = j
            }
            if !cur.isEmpty { split.append(cur) }
        }
        // One whole paragraph per line (long lines) means line breaks are paragraph breaks.
        return split.flatMap { lines -> [[String]] in
            let avg = lines.map(\.count).reduce(0, +) / max(lines.count, 1)
            return lines.count > 1 && avg > 160 ? lines.map { [$0] } : [lines]
        }
    }

    private static func joinLines(_ lines: [String]) -> String {
        var s = lines.joined(separator: "\n")
        s = s.replacingOccurrences(of: #"(\p{L})-\n(\p{Ll})"#, with: "$1$2", options: .regularExpression)
        return s.replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: #"[ \t]{2,}"#, with: " ", options: .regularExpression).trimmed
    }

    private static func stripEdges(_ paras: [[String]], headers: Set<String>) -> [[String]] {
        var p = paras
        let isPageNumber: (String) -> Bool = { s in
            let core = s.trimmingCharacters(in: CharacterSet(charactersIn: "-–—|•. ()[]"))
            return !core.isEmpty && core.count <= 4 && matches(core, #"^([0-9০-৯]+|[ivxlc]+)$"#)
        }
        for _ in 0..<2 { // header may sit above the page number, or vice versa
            if let f = p.first, f.count == 1, isPageNumber(f[0]) || (headers.contains(TextCleaner.headerKey(f[0])) && markedHeading(f[0]) == nil) {
                p.removeFirst()
            }
            if let l = p.last, l.count == 1, isPageNumber(l[0]) || headers.contains(TextCleaner.headerKey(l[0])) {
                p.removeLast()
            }
        }
        // A header line glued to the first paragraph ("DIPLOMACY\nit did so…").
        if var f = p.first, f.count > 1, headers.contains(TextCleaner.headerKey(f[0])) || isPageNumber(f[0]) {
            f.removeFirst()
            p[0] = f
        }
        return p
    }

    private static func isKindTitle(_ s: String) -> PageKind? {
        let t = s.trimmingCharacters(in: CharacterSet(charactersIn: "#:. ")).trimmed
        return kindTitles.first { matches(t, $0.1) }?.0
    }

    private static func classify(_ paras: [[String]], pageIndex: Int, previous: PageKind) -> PageKind {
        let lines = paras.flatMap { $0 }
        if let titled = lines.prefix(3).compactMap({ isKindTitle($0.replacingOccurrences(of: #"^#+\s*"#, with: "", options: .regularExpression)) }).first {
            return titled
        }
        guard lines.count >= 5 else { return previous == .body ? .body : (lines.isEmpty ? previous : .body) }
        let refLines = lines.filter { matches($0, endsInPageRef) }.count
        let commaRefs = lines.filter { matches($0, #"[0-9০-৯]+\s*,\s*[0-9০-৯]+"#) }.count
        let short = lines.filter { $0.count < 70 }.count
        let refShare = Double(refLines) / Double(lines.count)
        // Index: many short entries with page numbers, often comma lists.
        if refShare > 0.5, Double(short) / Double(lines.count) > 0.7,
           commaRefs >= 3 || previous == .index {
            return .index
        }
        // Continue an index or contents run.
        if (previous == .index || previous == .contents), refShare > 0.45 { return previous }
        // Contents near the front: most lines end with a page number.
        if refShare > 0.55, pageIndex < 40 { return .contents }
        return .body
    }

    private static func markedHeading(_ line: String) -> (level: Int, text: String)? {
        guard line.hasPrefix("#") else { return nil }
        let hashes = line.prefix { $0 == "#" }.count
        let text = String(line.dropFirst(hashes)).trimmed
        guard !text.isEmpty, hashes <= 4 else { return nil }
        return (hashes == 1 ? 1 : 2, text)
    }

    private static func heuristicHeading(_ s: String, position: Int, next: String?) -> Int? {
        let words = s.split(separator: " ").count
        guard words <= 12, !s.hasSuffix("."), !s.hasSuffix(","), !s.hasSuffix(";"), !s.hasSuffix("।") || words <= 3 else { return nil }
        if matches(s, chapterKeyword) || matches(s, chapterLabel) { return 1 }
        if matches(s, numberWord), position <= 2 { return 1 }
        // ALL-CAPS short line at the very top of a page (after headers were removed).
        let letters = s.unicodeScalars.filter { CharacterSet.letters.contains($0) }
        if position == 0, letters.count >= 4, s == s.uppercased(), s != s.lowercased(), words <= 8,
           let next, next.split(separator: " ").count > 12,
           let first = next.first, !first.isLowercase {   // a running header is followed by mid-sentence text
            return 1
        }
        return nil
    }

    /// True when a heading obviously runs on to the next line.
    private static func headingContinues(_ t: String) -> Bool {
        if let c = t.last, ":,–—-&".contains(c) { return true }
        let last = t.split(separator: " ").last.map { $0.lowercased() } ?? ""
        return ["the", "of", "and", "or", "a", "an", "to", "in", "for", "on", "with", "from", "at", "by", "ও", "এবং"].contains(last)
    }

    private static func mergeNumberedHeadings(_ blocks: [Block]) -> [Block] {
        var out: [Block] = []
        for b in blocks {
            if case .heading(_, let t2) = b, case .heading(1, let t1)? = out.last,
               matches(t1, numberWord) || matches(t1, chapterLabel) {
                let sep = t1.hasSuffix(":") ? " " : ": "
                out[out.count - 1] = .heading(level: 1, text: "\(t1)\(sep)\(t2)")
            } else {
                out.append(b)
            }
        }
        return out
    }

    private static func body(_ lines: [String], kind: PageKind) -> [Block] {
        kind.keepsLines ? lines.map { .line($0) } : [.para(joinLines(lines))]
    }

    /// Appends a block, joining a paragraph that was split by a page break.
    private static func appendMerging(_ items: inout [(page: Int, block: Block)], page: Int, block: Block, lastPage: inout Int) {
        defer { lastPage = page }
        if case .para(let next) = block, let last = items.last, lastPage == page - 1, case .para(let prev) = last.block,
           !endsSentence(prev), let first = next.unicodeScalars.first, !CharacterSet.uppercaseLetters.contains(first) || prev.hasSuffix("-") {
            let joined: String
            if prev.hasSuffix("-"), let f = next.first, f.isLowercase {
                joined = String(prev.dropLast()) + next
            } else {
                joined = prev + " " + next
            }
            items[items.count - 1] = (last.page, .para(joined))
            return
        }
        items.append((page, block))
    }

    private static func endsSentence(_ s: String) -> Bool {
        guard let c = s.trimmed.last else { return true }
        return ".!?\"”’:;।॥)".contains(c) || c.isNumber && s.hasSuffix(".")
    }

    private static func fixedSections(_ pages: [StructuredPage], every: Int) -> [BookSection] {
        var sections: [BookSection] = []
        var i = 0
        while i < pages.count {
            let chunk = pages[i..<min(i + every, pages.count)]
            let a = chunk.first!.index + 1, b = chunk.last!.index + 1
            var s = BookSection(title: a == b ? "Page \(a)" : "Pages \(a)–\(b)", kind: .body, firstPage: chunk.first!.index)
            var lastPage = -10
            for p in chunk {
                for block in p.blocks { appendMerging(&s.items, page: p.index, block: block, lastPage: &lastPage) }
            }
            sections.append(s)
            i += every
        }
        return sections
    }
}

/// The OCR prompt, shared by the app and tests.
enum OCRPrompt {
    static func build(model: String, languages: String, dropHeaders: Bool) -> String {
        let n = model.lowercased()
        if n.hasPrefix("glm-ocr") { return "Text Recognition:" }
        if n.hasPrefix("deepseek-ocr") { return "Free OCR." }
        return """
        You are a precise OCR engine. Transcribe all the text on this book page exactly as printed. \
        Expected language(s): \(LanguageNames.describe(languages)).
        Rules:
        - Keep the original language and script. Never translate, correct, or summarize.
        - Follow the natural reading order. Separate paragraphs with one blank line.
        - Start a chapter or part title line with "# " and a section heading line with "## ".
        - In a table of contents, index, or list, keep each entry on its own line.
        \(dropHeaders ? "- Leave out running headers, footers and page numbers.\n" : "")\
        - Output only the transcribed text, with no other formatting, comments, or code fences.
        """
    }
}
