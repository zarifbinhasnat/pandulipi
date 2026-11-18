import AppKit
import ImageIO
import PDFKit

/// A book to transcribe: either one PDF or a set of page images.
final class SourceDocument: @unchecked Sendable {
    static let imageExtensions: Set<String> = ["png", "jpg", "jpeg", "tif", "tiff", "heic", "bmp", "gif", "webp"]

    let url: URL
    let title: String
    let fileSize: Int64
    private let pdf: PDFDocument?
    private let imageURLs: [URL]
    private let lock = NSLock()

    var pageCount: Int { pdf?.pageCount ?? imageURLs.count }
    var kindLabel: String { pdf != nil ? "PDF" : "\(imageURLs.count) images" }

    init?(urls: [URL]) {
        guard let first = urls.first else { return nil }
        if urls.count == 1, first.pathExtension.lowercased() == "pdf" {
            guard let doc = PDFDocument(url: first) else { return nil }
            if doc.isLocked && !doc.unlock(withPassword: "") { return nil }
            pdf = doc
            imageURLs = []
            title = Self.usefulTitle(doc.documentAttributes?[PDFDocumentAttribute.titleAttribute] as? String)
                ?? Self.prettyFileName(first)
        } else {
            let imgs = urls
                .filter { Self.imageExtensions.contains($0.pathExtension.lowercased()) }
                .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
            guard !imgs.isEmpty else { return nil }
            pdf = nil
            imageURLs = imgs
            title = imgs.count == 1
                ? first.deletingPathExtension().lastPathComponent
                : first.deletingLastPathComponent().lastPathComponent
        }
        url = first
        let size = (try? FileManager.default.attributesOfItem(atPath: first.path)[.size] as? NSNumber)?.int64Value
        fileSize = size ?? 0
    }

    /// PDF title metadata is often junk left by the scanning tool ("Documento DjVu", "Microsoft Word - x.doc").
    static func usefulTitle(_ t: String?) -> String? {
        guard let t = t?.trimmed, t.count >= 3 else { return nil }
        let junk = ["djvu", "untitled", "microsoft word", "scan", "document", "adobe", ".pdf", ".doc", "pdf "]
        return junk.contains { t.lowercased().contains($0) } ? nil : t
    }

    static func prettyFileName(_ url: URL) -> String {
        url.deletingPathExtension().lastPathComponent
            .replacingOccurrences(of: "_", with: " ").replacingOccurrences(of: "-", with: " ")
            .replacingOccurrences(of: #"^(download|ebook|book)\s+"#, with: "", options: [.regularExpression, .caseInsensitive])
            .trimmed
    }

    var author: String? {
        (pdf?.documentAttributes?[PDFDocumentAttribute.authorAttribute] as? String)?.trimmed.nilIfEmpty
    }

    var isPDF: Bool { pdf != nil }

    /// The PDF's own text layer for a page (empty for scans).
    func embeddedText(page index: Int) -> String {
        lock.lock()
        defer { lock.unlock() }
        return pdf?.page(at: index)?.string ?? ""
    }

    /// Samples a few pages to see whether the PDF has a usable text layer.
    func textLayerCoverage() -> Double {
        guard isPDF, pageCount > 0 else { return 0 }
        let probes = Set((0..<min(8, pageCount)).map { $0 * max(1, pageCount / 8) }).filter { $0 < pageCount }
        let withText = probes.filter { embeddedText(page: $0).trimmed.count > 40 }.count
        return Double(withText) / Double(probes.count)
    }

    /// Stable key for the on-disk results cache.
    var cacheKey: String {
        let all = ([url] + imageURLs).map(\.path).joined(separator: "|") + "|\(fileSize)|\(pageCount)"
        return Hash.sha256(all)
    }

    /// Renders a page to an RGB bitmap whose longest side is `maxPixel`.
    func render(page index: Int, maxPixel: CGFloat) -> CGImage? {
        lock.lock()
        defer { lock.unlock() }
        if let pdf {
            guard let page = pdf.page(at: index) else { return nil }
            return Self.render(pdfPage: page, maxPixel: maxPixel)
        }
        guard index >= 0, index < imageURLs.count,
              let src = CGImageSourceCreateWithURL(imageURLs[index] as CFURL, nil) else { return nil }
        let opts: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixel,
            kCGImageSourceCreateThumbnailWithTransform: true,
        ]
        return CGImageSourceCreateThumbnailAtIndex(src, 0, opts as CFDictionary)
    }

    private static func render(pdfPage page: PDFPage, maxPixel: CGFloat) -> CGImage? {
        let box = page.bounds(for: .cropBox)
        var size = box.size
        if page.rotation % 180 != 0 { size = CGSize(width: size.height, height: size.width) }
        guard size.width > 0, size.height > 0 else { return nil }
        let scale = maxPixel / max(size.width, size.height)
        let w = max(1, Int((size.width * scale).rounded()))
        let h = max(1, Int((size.height * scale).rounded()))
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: space, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)
        else { return nil }
        ctx.setFillColor(CGColor(gray: 1, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
        ctx.interpolationQuality = .high
        ctx.scaleBy(x: scale, y: scale)
        page.draw(with: .cropBox, to: ctx)
        return ctx.makeImage()
    }
}

extension CGImage {
    func pngData() -> Data? {
        NSBitmapImageRep(cgImage: self).representation(using: .png, properties: [:])
    }

    func jpegData(quality: Double = 0.85) -> Data? {
        NSBitmapImageRep(cgImage: self).representation(using: .jpeg, properties: [.compressionFactor: quality])
    }

    var nsImage: NSImage { NSImage(cgImage: self, size: NSSize(width: width, height: height)) }
}

extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}

import CryptoKit

enum Hash {
    static func sha256(_ s: String) -> String {
        SHA256.hash(data: Data(s.utf8)).map { String(format: "%02x", $0) }.joined()
    }
}
