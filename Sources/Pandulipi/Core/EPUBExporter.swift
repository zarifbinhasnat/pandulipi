import CoreGraphics
import Foundation

struct BookMeta {
    var title: String
    var author: String
    var language: String // BCP-47, e.g. "bn"
    var pageMarkers: Bool
    var pagesPerChapter: Int
    var autoChapters: Bool = true
}

enum TextCleaner {
    private static let bengaliDigits = CharacterSet(charactersIn: "০১২৩৪৫৬৭৮৯")

    /// Turns raw OCR text into clean paragraphs.
    static func paragraphs(_ raw: String, dropPageNumbers: Bool) -> [String] {
        var s = raw.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\u{000C}", with: "\n")
        // Strip code fences some models wrap their answer in.
        s = s.split(separator: "\n", omittingEmptySubsequences: false)
            .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("```") }
            .joined(separator: "\n")
        // Re-join words hyphenated across lines (Latin scripts).
        s = s.replacingOccurrences(of: #"(\p{L})-\n[ \t]*(\p{Ll})"#, with: "$1$2", options: .regularExpression)

        var paras = s.replacingOccurrences(of: #"\n[ \t]*\n"#, with: "\u{1E}", options: .regularExpression)
            .components(separatedBy: "\u{1E}")
            .map { $0.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }.joined(separator: " ") }
            .map { $0.replacingOccurrences(of: #"[ \t]{2,}"#, with: " ", options: .regularExpression).trimmed }
            .filter { !$0.isEmpty }

        if dropPageNumbers {
            let isNumber: (String) -> Bool = { p in
                let core = p.trimmingCharacters(in: CharacterSet(charactersIn: "-–—|•. ()[]"))
                return !core.isEmpty && core.count <= 4 &&
                    core.unicodeScalars.allSatisfy { CharacterSet.decimalDigits.contains($0) || bengaliDigits.contains($0) }
            }
            if let f = paras.first, isNumber(f) { paras.removeFirst() }
            if let l = paras.last, isNumber(l) { paras.removeLast() }
        }
        return paras
    }

    /// Key used to spot running headers/footers: lowercase letters only, digits dropped.
    static func headerKey(_ p: String) -> String {
        String(p.lowercased().unicodeScalars.filter { CharacterSet.letters.contains($0) || $0 == " " }).trimmed
    }

    /// Short first/last lines that repeat on many pages (book title, chapter title) are running headers.
    static func repeatedEdges(_ pages: [[String]]) -> Set<String> {
        guard pages.count >= 3 else { return [] }
        var counts: [String: Int] = [:]
        for paras in pages {
            for p in [paras.first, paras.last].compactMap({ $0 }) where p.split(separator: " ").count <= 8 {
                let k = headerKey(p)
                if k.count >= 3 { counts[k, default: 0] += 1 }
            }
        }
        // Books alternate headers (book title / chapter title), so a short edge line seen twice is a header.
        let threshold = 2
        return Set(counts.filter { $0.value >= threshold }.keys)
    }

    /// Paragraphs for every page with page numbers and repeated running headers removed.
    static func cleanPages(_ pages: [(index: Int, text: String)], dropPageNumbers: Bool) -> [(index: Int, paras: [String])] {
        let raw = pages.sorted { $0.index < $1.index }.map { ($0.index, paragraphs($0.text, dropPageNumbers: dropPageNumbers)) }
        guard dropPageNumbers else { return raw.map { ($0.0, $0.1) } }
        let headers = repeatedEdges(raw.map(\.1))
        return raw.map { idx, paras in
            var p = paras
            if let f = p.first, headers.contains(headerKey(f)) { p.removeFirst() }
            if let l = p.last, headers.contains(headerKey(l)) { p.removeLast() }
            return (idx, p)
        }
    }

    static func xml(_ s: String) -> String {
        s.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }
}

enum EPUBExporter {
    static func export(meta: BookMeta, pages: [(index: Int, text: String)], cover: CGImage?,
                       dropPageNumbers: Bool, to dest: URL) throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent("pandulipi-epub-\(UUID().uuidString)")
        let oebps = root.appendingPathComponent("OEBPS")
        try fm.createDirectory(at: root.appendingPathComponent("META-INF"), withIntermediateDirectories: true)
        try fm.createDirectory(at: oebps, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: root) }

        func write(_ s: String, _ path: String) throws {
            try s.write(to: root.appendingPathComponent(path), atomically: true, encoding: .utf8)
        }

        let lang = TextCleaner.xml(meta.language)
        let title = TextCleaner.xml(meta.title.isEmpty ? "Untitled" : meta.title)
        let author = TextCleaner.xml(meta.author)

        try write("application/epub+zip", "mimetype")
        try write("""
        <?xml version="1.0" encoding="UTF-8"?>
        <container version="1.0" xmlns="urn:oasis:names:tc:opendocument:xmlns:container">
          <rootfiles><rootfile full-path="OEBPS/content.opf" media-type="application/oebps-package+xml"/></rootfiles>
        </container>
        """, "META-INF/container.xml")

        try write("""
        body { font-family: serif; line-height: 1.6; margin: 0 4%; }
        h1 { font-size: 1.5em; text-align: center; margin: 2em 0 1.2em; line-height: 1.3; }
        h2 { font-size: 1.15em; margin: 1.6em 0 0.8em; }
        p { margin: 0 0 0.5em; text-indent: 1.2em; text-align: justify; }
        h1 + p, h2 + p { text-indent: 0; }
        p.line { text-indent: -1.5em; margin: 0 0 0.15em 1.5em; text-align: left; }
        section.index p.line, section.toc p.line { font-size: 0.92em; }
        p.pg { text-indent: 0; text-align: center; color: #999; font-size: 0.75em; margin: 1em 0; }
        .cover { text-align: center; margin: 0; padding: 0; }
        .cover img { max-width: 100%; max-height: 100%; }
        """, "OEBPS/style.css")

        // Chapters: detected headings / contents / index, or fixed page ranges.
        let structured = BookStructure.analyze(pages, dropHeaders: dropPageNumbers, bookTitle: meta.title)
        let sections = BookStructure.sections(structured, fallbackEvery: meta.pagesPerChapter, autoDetect: meta.autoChapters)
        var chapters: [(file: String, label: String, kind: PageKind, subs: [(id: String, text: String)])] = []
        for section in sections {
            var body = "<section epub:type=\"\(section.kind.epubType)\" class=\"\(section.kind.epubType)\">\n"
            var lastPage = -1
            var subIndex = 0
            var openedWithHeading = false
            for (n, item) in section.items.enumerated() {
                if meta.pageMarkers, item.page != lastPage {
                    body += "<p class=\"pg\" id=\"page\(item.page + 1)\">— \(item.page + 1) —</p>\n"
                }
                lastPage = item.page
                switch item.block {
                case .heading(let level, let text):
                    if level == 1 {
                        body += "<h1>\(TextCleaner.xml(text))</h1>\n"
                        if n == 0 { openedWithHeading = true }
                    } else {
                        let id = subIndex < section.subheadings.count ? section.subheadings[subIndex].id : "s\(n)"
                        subIndex += 1
                        body += "<h2 id=\"\(id)\">\(TextCleaner.xml(text))</h2>\n"
                    }
                case .para(let text):
                    body += "<p>\(TextCleaner.xml(text))</p>\n"
                case .line(let text):
                    body += "<p class=\"line\">\(TextCleaner.xml(text))</p>\n"
                }
            }
            if !openedWithHeading, section.kind != .body {
                body = body.replacingOccurrences(of: "class=\"\(section.kind.epubType)\">\n",
                                                 with: "class=\"\(section.kind.epubType)\">\n<h1>\(TextCleaner.xml(section.title))</h1>\n")
            }
            body += "</section>"
            let file = "c\(chapters.count + 1).xhtml"
            try write(xhtml(title: TextCleaner.xml(section.title), lang: lang, body: body), "OEBPS/\(file)")
            chapters.append((file, section.title, section.kind, section.subheadings))
        }

        var hasCover = false
        if let cover, let jpg = cover.jpegData(quality: 0.85) {
            try jpg.write(to: oebps.appendingPathComponent("cover.jpg"))
            try write(xhtml(title: "Cover", lang: lang,
                            body: "<div class=\"cover\"><img src=\"cover.jpg\" alt=\"\(title)\"/></div>"),
                      "OEBPS/cover.xhtml")
            hasCover = true
        }

        let navItems = chapters.map { c -> String in
            let subs = c.subs.isEmpty ? "" : "<ol>" + c.subs.map {
                "<li><a href=\"\(c.file)#\($0.id)\">\(TextCleaner.xml($0.text))</a></li>"
            }.joined() + "</ol>"
            return "<li><a href=\"\(c.file)\">\(TextCleaner.xml(c.label))</a>\(subs)</li>"
        }.joined(separator: "\n")
        var landmarks = hasCover ? "<li><a epub:type=\"cover\" href=\"cover.xhtml\">Cover</a></li>" : ""
        if let c = chapters.first(where: { $0.kind == .contents }) { landmarks += "<li><a epub:type=\"toc\" href=\"\(c.file)\">Contents</a></li>" }
        if let c = chapters.first(where: { $0.kind == .body }) { landmarks += "<li><a epub:type=\"bodymatter\" href=\"\(c.file)\">Start of text</a></li>" }
        if let c = chapters.first(where: { $0.kind == .index }) { landmarks += "<li><a epub:type=\"index\" href=\"\(c.file)\">Index</a></li>" }
        try write(xhtml(title: title, lang: lang, body: """
        <nav epub:type="toc" id="toc"><h2>\(title)</h2><ol>
        \(navItems)
        </ol></nav>
        <nav epub:type="landmarks" id="landmarks" hidden="hidden"><ol>\(landmarks)</ol></nav>
        """), "OEBPS/nav.xhtml")

        let uuid = UUID().uuidString.lowercased()
        let ncxPoints = chapters.enumerated().map { n, c in
            "<navPoint id=\"np\(n + 1)\" playOrder=\"\(n + 1)\"><navLabel><text>\(TextCleaner.xml(c.label))</text></navLabel><content src=\"\(c.file)\"/></navPoint>"
        }.joined(separator: "\n")
        try write("""
        <?xml version="1.0" encoding="UTF-8"?>
        <ncx xmlns="http://www.daisy.org/z3986/2005/ncx/" version="2005-1">
        <head><meta name="dtb:uid" content="urn:uuid:\(uuid)"/></head>
        <docTitle><text>\(title)</text></docTitle>
        <navMap>
        \(ncxPoints)
        </navMap>
        </ncx>
        """, "OEBPS/toc.ncx")

        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime]
        var manifest = """
        <item id="nav" href="nav.xhtml" media-type="application/xhtml+xml" properties="nav"/>
        <item id="ncx" href="toc.ncx" media-type="application/x-dtbncx+xml"/>
        <item id="css" href="style.css" media-type="text/css"/>
        """
        var spine = ""
        if hasCover {
            manifest += "\n<item id=\"cover-image\" href=\"cover.jpg\" media-type=\"image/jpeg\" properties=\"cover-image\"/>"
            manifest += "\n<item id=\"cover\" href=\"cover.xhtml\" media-type=\"application/xhtml+xml\"/>"
            spine += "<itemref idref=\"cover\"/>\n"
        }
        for (n, c) in chapters.enumerated() {
            manifest += "\n<item id=\"ch\(n + 1)\" href=\"\(c.file)\" media-type=\"application/xhtml+xml\"/>"
            spine += "<itemref idref=\"ch\(n + 1)\"/>\n"
        }
        try write("""
        <?xml version="1.0" encoding="UTF-8"?>
        <package xmlns="http://www.idpf.org/2007/opf" version="3.0" unique-identifier="bookid" xml:lang="\(lang)">
        <metadata xmlns:dc="http://purl.org/dc/elements/1.1/">
        <dc:identifier id="bookid">urn:uuid:\(uuid)</dc:identifier>
        <dc:title>\(title)</dc:title>
        \(author.isEmpty ? "" : "<dc:creator>\(author)</dc:creator>")
        <dc:language>\(lang)</dc:language>
        <meta property="dcterms:modified">\(iso.string(from: Date()))</meta>
        \(hasCover ? "<meta name=\"cover\" content=\"cover-image\"/>" : "")
        </metadata>
        <manifest>
        \(manifest)
        </manifest>
        <spine toc="ncx">
        \(spine)</spine>
        </package>
        """, "OEBPS/content.opf")

        // The mimetype entry must be first and stored uncompressed.
        try? fm.removeItem(at: dest)
        try ProcessRunner.runSync("/usr/bin/zip", ["-X0q", dest.path, "mimetype"], cwd: root)
        try ProcessRunner.runSync("/usr/bin/zip", ["-Xr9Dq", dest.path, "META-INF", "OEBPS"], cwd: root)
    }

    static func plainText(pages: [(index: Int, text: String)], dropPageNumbers: Bool, markers: Bool,
                          autoChapters: Bool = true, pagesPerChapter: Int = 10, bookTitle: String = "") -> String {
        let structured = BookStructure.analyze(pages, dropHeaders: dropPageNumbers, bookTitle: bookTitle)
        let sections = BookStructure.sections(structured, fallbackEvery: pagesPerChapter, autoDetect: autoChapters)
        var out: [String] = []
        for section in sections {
            var lastPage = -1
            var lines: [String] = []
            if case .heading(1, _)? = section.items.first?.block {} else { lines.append("# " + section.title) }
            for item in section.items {
                if markers, item.page != lastPage { lines.append("— \(item.page + 1) —") }
                lastPage = item.page
                switch item.block {
                case .heading(let level, let text): lines.append(String(repeating: "#", count: level) + " " + text)
                case .para(let text): lines.append(text)
                case .line(let text): lines.append(text)
                }
            }
            out.append(lines.joined(separator: "\n\n"))
        }
        return out.joined(separator: "\n\n")
    }

    private static func xhtml(title: String, lang: String, body: String) -> String {
        """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE html>
        <html xmlns="http://www.w3.org/1999/xhtml" xmlns:epub="http://www.idpf.org/2007/ops" lang="\(lang)" xml:lang="\(lang)">
        <head><meta charset="utf-8"/><title>\(title)</title><link rel="stylesheet" type="text/css" href="style.css"/></head>
        <body>
        \(body)
        </body>
        </html>
        """
    }
}
