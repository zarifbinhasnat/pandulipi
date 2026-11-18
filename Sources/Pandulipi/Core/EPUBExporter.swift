import CoreGraphics
import Foundation

struct BookMeta {
    var title: String
    var author: String
    var language: String // BCP-47, e.g. "bn"
    var pageMarkers: Bool
    var pagesPerChapter: Int
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
        h2 { font-size: 1.1em; text-align: center; margin: 1.5em 0 1em; color: #555; }
        p { margin: 0 0 0.5em; text-indent: 1.2em; text-align: justify; }
        p.pg { text-indent: 0; text-align: center; color: #999; font-size: 0.75em; margin: 1em 0; }
        .cover { text-align: center; margin: 0; padding: 0; }
        .cover img { max-width: 100%; max-height: 100%; }
        """, "OEBPS/style.css")

        // Chapters
        let sorted = pages.sorted { $0.index < $1.index }
        let per = max(1, meta.pagesPerChapter)
        var chapters: [(file: String, label: String)] = []
        var i = 0
        while i < sorted.count {
            let chunk = Array(sorted[i..<min(i + per, sorted.count)])
            let label = chunk.count == 1
                ? "Page \(chunk.first!.index + 1)"
                : "Pages \(chunk.first!.index + 1)–\(chunk.last!.index + 1)"
            var body = ""
            for page in chunk {
                if meta.pageMarkers {
                    body += "<p class=\"pg\" id=\"page\(page.index + 1)\">— \(page.index + 1) —</p>\n"
                }
                for p in TextCleaner.paragraphs(page.text, dropPageNumbers: dropPageNumbers) {
                    body += "<p>\(TextCleaner.xml(p))</p>\n"
                }
            }
            let file = "c\(chapters.count + 1).xhtml"
            try write(xhtml(title: label, lang: lang, body: body), "OEBPS/\(file)")
            chapters.append((file, label))
            i += per
        }

        var hasCover = false
        if let cover, let jpg = cover.jpegData(quality: 0.85) {
            try jpg.write(to: oebps.appendingPathComponent("cover.jpg"))
            try write(xhtml(title: "Cover", lang: lang,
                            body: "<div class=\"cover\"><img src=\"cover.jpg\" alt=\"\(title)\"/></div>"),
                      "OEBPS/cover.xhtml")
            hasCover = true
        }

        let navItems = chapters.map { "<li><a href=\"\($0.file)\">\(TextCleaner.xml($0.label))</a></li>" }.joined(separator: "\n")
        try write(xhtml(title: title, lang: lang, body: """
        <nav epub:type="toc" id="toc"><h2>\(title)</h2><ol>
        \(navItems)
        </ol></nav>
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

    static func plainText(pages: [(index: Int, text: String)], dropPageNumbers: Bool, markers: Bool) -> String {
        pages.sorted { $0.index < $1.index }.map { page in
            let body = TextCleaner.paragraphs(page.text, dropPageNumbers: dropPageNumbers).joined(separator: "\n\n")
            return markers ? "— \(page.index + 1) —\n\n\(body)" : body
        }.joined(separator: "\n\n")
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
