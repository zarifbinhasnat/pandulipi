import Foundation
@main struct T {
    static func check(_ name: String, _ ok: Bool) { print(ok ? "PASS" : "FAIL", name); if !ok { failed += 1 }; if CommandLine.arguments.contains("-q") && ok { return } }
    nonisolated(unsafe) static var failed = 0
    static func main() {
        // English book: contents, chapter opener, body with running header, index pages
        let pages: [(index: Int, text: String)] = [
            (5, "CONTENTS\n\nPreface 9\nChapter One: The New World Order 17\nChapter Two: The Hinge 29\nIndex 271"),
            (12, "# CHAPTER ONE\n\n# The New World Order\n\nAlmost as if according to some natural law, in every century there seems to emerge a country with the power.\n\nSecond paragraph ends without a full stop and continues on the next page with the"),
            (13, "DIPLOMACY\n\nrest of the sentence. Another para-\n\n14"),
            (14, "THE NEW WORLD ORDER\n\ngraph that was hyphenated. Done.\n\n## A Section Heading\n\nBody text here."),
            (15, "DIPLOMACY\n\nMore text in the chapter.\n\n16"),
            (16, "CHAPTER TWO\n\nThe Hinge: Theodore Roosevelt or Woodrow Wilson\n\nUntil the early twentieth century, the isolationist tendency prevailed in American foreign policy and lasted for decades."),
            (17, "DIPLOMACY\n\nText of chapter two continues here for a while.\n\n18"),
            (270, "INDEX\n\nAcheson, Dean, 445, 470-72\nAdenauer, Konrad, 498, 503\nAlexander I, Czar, 76, 79-82\nAlsace-Lorraine, 118, 133\nAmerica, isolationism of, 29, 33\nAustria, 81, 83-85"),
            (271, "Balkans, 137, 148, 156\nBismarck, Otto von, 103-36\nBritain, see Great Britain\nCastlereagh, Lord, 78, 85\nChurchill, Winston, 394, 411\nCongress of Vienna, 79-81"),
        ]
        let s = BookStructure.analyze(pages, dropHeaders: true)
        let kinds = Dictionary(uniqueKeysWithValues: s.map { ($0.index, $0.kind) })
        check("contents page detected", kinds[5] == .contents)
        check("index page detected", kinds[270] == .index)
        check("index continuation page detected", kinds[271] == .index)
        let secs = BookStructure.sections(s, fallbackEvery: 10, autoDetect: true)
        print("   sections:", secs.map { "[\($0.kind.rawValue)] \($0.title)" })
        check("chapter one merged title", secs.contains { $0.title == "CHAPTER ONE: The New World Order" })
        check("chapter two heuristic + merged", secs.contains { $0.title.hasPrefix("CHAPTER TWO: The Hinge") })
        check("section heading nested", secs.contains { $0.subheadings.map(\.text) == ["A Section Heading"] })
        let ch1 = secs.first { $0.title.hasPrefix("CHAPTER ONE") }!
        let paras = ch1.items.compactMap { if case .para(let t) = $0.block { return t } else { return nil } }
        check("paragraph merged across page break", paras.contains { $0.contains("with the rest of the sentence.") })
        check("hyphen joined across page break", paras.contains { $0.contains("Another paragraph that was hyphenated.") })
        check("running headers removed", !paras.contains { $0.contains("DIPLOMACY") || $0.hasPrefix("THE NEW WORLD ORDER") })
        check("page numbers removed", !paras.contains { $0 == "14" || $0 == "16" })
        let idx = secs.first { $0.kind == .index }!
        check("index keeps one entry per line", idx.items.filter { if case .line = $0.block { return true } else { return false } }.count == 12)

        // Bangla book
        let bn: [(index: Int, text: String)] = [
            (3, "সূচিপত্র\n\nভূমিকা ৯\nপ্রথম অধ্যায়: নদী ও মানুষ ১৫\nদ্বিতীয় অধ্যায়: গ্রামের কথা ৪২\nনির্ঘণ্ট ২১০"),
            (8, "ভূমিকা\n\nএই বইটি লেখার পেছনে একটি দীর্ঘ গল্প আছে। অনেক বছর ধরে আমি নদীর পাড়ের মানুষের জীবন দেখেছি।"),
            (14, "প্রথম অধ্যায়\n\nনদী ও মানুষ\n\nবাংলাদেশের মানুষের জীবনে নদীর প্রভাব অনেক গভীর। নদীর তীরে গড়ে উঠেছে শহর, বন্দর আর হাজারো গ্রাম।"),
            (209, "নির্ঘণ্ট\n\nঅমর্ত্য সেন, ১২, ৪৫\nআকবর, ৬৭-৬৯\nইলিশ, ২৩, ৮৮\nকলকাতা, ১০৪, ১১২\nগঙ্গা, ৫, ১৫-১৮\nঢাকা, ৩, ৪৪, ৯০"),
        ]
        let sb = BookStructure.analyze(bn, dropHeaders: true)
        let bk = Dictionary(uniqueKeysWithValues: sb.map { ($0.index, $0.kind) })
        check("Bangla সূচিপত্র = contents", bk[3] == .contents)
        check("Bangla নির্ঘণ্ট = index", bk[209] == .index)
        let bsecs = BookStructure.sections(sb, fallbackEvery: 10, autoDetect: true)
        print("   sections:", bsecs.map { "[\($0.kind.rawValue)] \($0.title)" })
        check("Bangla ভূমিকা = chapter", bsecs.contains { $0.title == "ভূমিকা" })
        check("Bangla অধ্যায় heading", bsecs.contains { $0.title.hasPrefix("প্রথম অধ্যায়") })

        // Body pages with no headings fall back to fixed ranges
        let plain: [(index: Int, text: String)] = (0..<12).map { ($0, "Just body text on page \($0) that goes on and on without any heading at all here.") }
        let ps = BookStructure.sections(BookStructure.analyze(plain, dropHeaders: true), fallbackEvery: 5, autoDetect: true)
        check("fallback to page ranges", ps.map(\.title) == ["Pages 1–5", "Pages 6–10", "Pages 11–12"])
        print(failed == 0 ? "ALL PASSED" : "\(failed) FAILED")
        exit(failed == 0 ? 0 : 1)
    }
}
