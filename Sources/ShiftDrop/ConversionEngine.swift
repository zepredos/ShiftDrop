import AppKit
import PDFKit
import ImageIO
import Vision
import CoreImage

final class ConversionEngine {
    static let shared = ConversionEngine()

    func convert(_ url: URL, to format: OutputFormat) throws -> [URL] {
        let kind = try FileKind.detect(url)
        if format == .txt || format == .docx {
            let text = try extractText(url, kind: kind)
            guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw ConversionError.message("No readable text was found in this file.")
            }
            let data = format == .txt ? Data(text.utf8) : try makeDOCX(text)
            return [try save(data, beside: url, extension: format.fileExtension)]
        }
        if format == .pdf {
            if kind == .text { return [try save(try textPDF(extractText(url, kind: kind)), beside: url, extension: "pdf")] }
            let images = try loadImages(url)
            let document = PDFDocument()
            for (index, image) in images.enumerated() {
                guard let page = PDFPage(image: NSImage(cgImage: image, size: .zero)) else {
                    throw ConversionError.message("Could not create the PDF page.")
                }
                document.insert(page, at: index)
            }
            guard let data = document.dataRepresentation() else { throw ConversionError.message("Could not create the PDF.") }
            return [try save(data, beside: url, extension: "pdf")]
        }
        if kind == .pdf {
            guard let pdf = PDFDocument(url: url), !pdf.isLocked, pdf.pageCount > 0 else {
                throw ConversionError.message("This PDF is empty, locked, or could not be opened.")
            }
            var outputs: [URL] = []
            do {
                for index in 0..<pdf.pageCount {
                    let output = try autoreleasepool {
                        guard let page = pdf.page(at: index) else { throw ConversionError.message("A PDF page could not be read.") }
                        let data = try encode(renderPage(page), as: format)
                        let suffix = pdf.pageCount > 1 ? String(format: " Page %03d", index + 1) : ""
                        return try save(data, beside: url, suffix: suffix, extension: format.fileExtension)
                    }
                    outputs.append(output)
                }
            } catch {
                for output in outputs { try? FileManager.default.removeItem(at: output) }
                throw error
            }
            return outputs
        }
        let images: [CGImage]
        if kind == .text {
            let pdfData = try textPDF(extractText(url, kind: kind))
            guard let pdf = PDFDocument(data: pdfData) else { throw ConversionError.message("Could not render the document.") }
            images = try renderPDF(pdf)
        } else {
            images = try loadImages(url)
        }
        // Encode every page before writing, so unsupported codecs cannot leave a partial batch.
        let encoded = try images.map { try encode($0, as: format) }
        var outputs: [URL] = []
        do {
            for (index, data) in encoded.enumerated() {
                let suffix = images.count > 1 ? String(format: " Page %03d", index + 1) : ""
                outputs.append(try save(data, beside: url, suffix: suffix, extension: format.fileExtension))
            }
        } catch {
            for output in outputs { try? FileManager.default.removeItem(at: output) }
            throw error
        }
        return outputs
    }

    func loadImages(_ url: URL) throws -> [CGImage] {
        if url.pathExtension.lowercased() == "pdf" {
            guard let pdf = PDFDocument(url: url), !pdf.isLocked else {
                throw ConversionError.message("This PDF is locked or could not be opened.")
            }
            return try renderPDF(pdf)
        }
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else {
            throw ConversionError.message("This image could not be opened.")
        }
        // Image editors use the first frame; conversion preserves all TIFF pages.
        let count = url.pathExtension.lowercased() == "tiff" || url.pathExtension.lowercased() == "tif" ? CGImageSourceGetCount(source) : 1
        return try (0..<count).map { index in
            let options: [CFString: Any] = [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: 12000
            ]
            guard let image = CGImageSourceCreateThumbnailAtIndex(source, index, options as CFDictionary) else {
                throw ConversionError.message("The image is damaged or uses an unsupported format.")
            }
            return image
        }
    }

    func renderPDF(_ document: PDFDocument) throws -> [CGImage] {
        guard document.pageCount > 0, !document.isLocked else { throw ConversionError.message("The PDF is empty or locked.") }
        return try (0..<document.pageCount).map { index in
            guard let page = document.page(at: index) else { throw ConversionError.message("A PDF page could not be read.") }
            return try renderPage(page)
        }
    }

    private func renderPage(_ page: PDFPage) throws -> CGImage {
        let bounds = page.bounds(for: .mediaBox)
        guard bounds.width.isFinite, bounds.height.isFinite, bounds.width > 0, bounds.height > 0 else {
            throw ConversionError.message("This PDF page has invalid dimensions.")
        }
        let scale = min(300.0 / 72.0, 12000 / max(bounds.width, bounds.height))
        return try raster(width: max(1, Int(bounds.width * scale)), height: max(1, Int(bounds.height * scale))) { context in
            context.setFillColor(CGColor(gray: 1, alpha: 1))
            context.fill(CGRect(x: 0, y: 0, width: bounds.width * scale, height: bounds.height * scale))
            context.scaleBy(x: scale, y: scale)
            context.translateBy(x: -bounds.minX, y: -bounds.minY)
            page.draw(with: .mediaBox, to: context)
        }
    }

    func encode(_ image: CGImage, as format: OutputFormat, quality: Double = 0.9) throws -> Data {
        if format == .webp { return try WebPEncoder.encode(image, quality: quality) }
        let supported = CGImageDestinationCopyTypeIdentifiers() as! [String]
        guard supported.contains(format.typeIdentifier) else {
            throw ConversionError.message("\(format.rawValue) encoding is unavailable on this macOS version. Choose another format.")
        }
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, format.typeIdentifier as CFString, 1, nil) else {
            throw ConversionError.message("Could not start \(format.rawValue) conversion.")
        }
        let output: CGImage
        if format == .jpg || format == .bmp {
            output = try raster(width: image.width, height: image.height) { context in
                context.setFillColor(CGColor(gray: 1, alpha: 1))
                context.fill(CGRect(x: 0, y: 0, width: image.width, height: image.height))
                context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
            }
        } else { output = image }
        CGImageDestinationAddImage(destination, output, [kCGImageDestinationLossyCompressionQuality: quality] as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { throw ConversionError.message("\(format.rawValue) conversion failed.") }
        return data as Data
    }

    func save(_ data: Data, beside source: URL, suffix: String = "", extension ext: String) throws -> URL {
        let base = source.deletingPathExtension().lastPathComponent + suffix
        let directory = source.deletingLastPathComponent()
        for index in 0..<10000 {
            let name = base + (index == 0 ? "" : " \(index + 1)") + "." + ext
            let output = directory.appendingPathComponent(name)
            do { try data.write(to: output, options: .withoutOverwriting); return output }
            catch CocoaError.fileWriteFileExists { continue }
        }
        throw ConversionError.message("Could not find an unused output filename.")
    }

    func extractText(_ url: URL, kind: FileKind) throws -> String {
        if kind == .text {
            if ["rtf", "docx"].contains(url.pathExtension.lowercased()) {
                return try NSAttributedString(url: url, options: [:], documentAttributes: nil).string
            }
            return try String(contentsOf: url, encoding: .utf8)
        }
        if kind == .pdf, let pdf = PDFDocument(url: url) {
            guard !pdf.isLocked else { throw ConversionError.message("Unlock the PDF before converting it.") }
            var pages: [String] = []
            for index in 0..<pdf.pageCount {
                guard let page = pdf.page(at: index) else { continue }
                let text = page.string ?? ""
                if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    let single = PDFDocument(); single.insert(page, at: 0)
                    pages.append(try recognizeText(renderPDF(single)[0]))
                } else { pages.append(text) }
            }
            return pages.joined(separator: "\n\n")
        }
        return try recognizeText(loadImages(url)[0])
    }

    private func recognizeText(_ image: CGImage) throws -> String {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        try VNImageRequestHandler(cgImage: image).perform([request])
        return (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }.joined(separator: "\n")
    }

    func makeDOCX(_ text: String) throws -> Data {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory.appendingPathComponent("_rels"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: directory.appendingPathComponent("word"), withIntermediateDirectories: true)
        let escaped = text.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;").replacingOccurrences(of: ">", with: "&gt;")
        let paragraphs = escaped.components(separatedBy: .newlines).map { "<w:p><w:r><w:t xml:space=\"preserve\">\($0)</w:t></w:r></w:p>" }.joined()
        let parts = [
            "[Content_Types].xml": "<?xml version=\"1.0\" encoding=\"UTF-8\"?><Types xmlns=\"http://schemas.openxmlformats.org/package/2006/content-types\"><Default Extension=\"rels\" ContentType=\"application/vnd.openxmlformats-package.relationships+xml\"/><Default Extension=\"xml\" ContentType=\"application/xml\"/><Override PartName=\"/word/document.xml\" ContentType=\"application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml\"/></Types>",
            "_rels/.rels": "<?xml version=\"1.0\" encoding=\"UTF-8\"?><Relationships xmlns=\"http://schemas.openxmlformats.org/package/2006/relationships\"><Relationship Id=\"rId1\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument\" Target=\"word/document.xml\"/></Relationships>",
            "word/document.xml": "<?xml version=\"1.0\" encoding=\"UTF-8\"?><w:document xmlns:w=\"http://schemas.openxmlformats.org/wordprocessingml/2006/main\"><w:body>\(paragraphs)<w:sectPr><w:pgSz w:w=\"11906\" w:h=\"16838\"/><w:pgMar w:top=\"1440\" w:right=\"1440\" w:bottom=\"1440\" w:left=\"1440\"/></w:sectPr></w:body></w:document>"
        ]
        for (path, xml) in parts { try Data(xml.utf8).write(to: directory.appendingPathComponent(path)) }
        let archive = directory.appendingPathComponent("output.docx")
        let process = Process(); process.executableURL = URL(fileURLWithPath: "/usr/bin/zip")
        process.currentDirectoryURL = directory
        process.arguments = ["-q", "-r", archive.path, "[Content_Types].xml", "_rels", "word"]
        let errors = Pipe(); process.standardError = errors
        try process.run(); process.waitUntilExit()
        guard process.terminationStatus == 0 else { throw ConversionError.message("Could not create the Word document.") }
        return try Data(contentsOf: archive)
    }

    private func textPDF(_ text: String) throws -> Data {
        let storage = NSTextStorage(string: text, attributes: [.font: NSFont.systemFont(ofSize: 12), .foregroundColor: NSColor.black])
        let manager = NSLayoutManager(); storage.addLayoutManager(manager)
        let data = NSMutableData()
        guard let consumer = CGDataConsumer(data: data), let context = CGContext(consumer: consumer, mediaBox: nil, nil) else {
            throw ConversionError.message("Could not create the document.")
        }
        var location = 0
        repeat {
            let container = NSTextContainer(containerSize: NSSize(width: 499, height: 746))
            manager.addTextContainer(container)
            let range = manager.glyphRange(for: container)
            var box = CGRect(x: 0, y: 0, width: 595, height: 842)
            context.beginPage(mediaBox: &box)
            context.saveGState(); context.translateBy(x: 48, y: 794); context.scaleBy(x: 1, y: -1)
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: true)
            manager.drawGlyphs(forGlyphRange: range, at: .zero)
            NSGraphicsContext.restoreGraphicsState()
            context.restoreGState(); context.endPage()
            let next = NSMaxRange(range)
            if next <= location { break }; location = next
        } while location < manager.numberOfGlyphs
        context.closePDF()
        return data as Data
    }

    func raster(width: Int, height: Int, draw: (CGContext) -> Void) throws -> CGImage {
        guard width > 0, height > 0, width <= 16000, height <= 16000, Double(width) * Double(height) <= 100_000_000,
              let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
            throw ConversionError.message("This image is too large to process safely. Use an image below 100 megapixels.")
        }
        draw(context)
        guard let image = context.makeImage() else { throw ConversionError.message("Could not render the image.") }
        return image
    }
}

enum WebPEncoder {
    static func encode(_ image: CGImage, quality: Double) throws -> Data {
        let bundled = Bundle.main.bundleURL.appendingPathComponent("Contents/Frameworks/libwebp.dylib").path
        let paths = [bundled, "/opt/homebrew/opt/webp/lib/libwebp.dylib", "/usr/local/opt/webp/lib/libwebp.dylib"]
        var library: UnsafeMutableRawPointer?
        for path in paths { if let handle = dlopen(path, RTLD_NOW) { library = handle; break } }
        guard let handle = library else {
            throw ConversionError.message("The WebP encoder is missing. Run scripts/build-app.sh to bundle it.")
        }
        defer { dlclose(handle) }
        typealias Encode = @convention(c) (UnsafePointer<UInt8>?, Int32, Int32, Int32, Float, UnsafeMutablePointer<UnsafeMutablePointer<UInt8>?>?) -> Int
        typealias Free = @convention(c) (UnsafeMutableRawPointer?) -> Void
        guard let encodeSymbol = dlsym(handle, "WebPEncodeRGBA"), let freeSymbol = dlsym(handle, "WebPFree") else {
            throw ConversionError.message("The WebP encoder could not be loaded.")
        }
        let encode = unsafeBitCast(encodeSymbol, to: Encode.self), free = unsafeBitCast(freeSymbol, to: Free.self)
        var pixels = [UInt8](repeating: 0, count: image.width * image.height * 4)
        return try pixels.withUnsafeMutableBytes { bytes in
            guard let context = CGContext(data: bytes.baseAddress, width: image.width, height: image.height, bitsPerComponent: 8,
                                          bytesPerRow: image.width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue) else {
                throw ConversionError.message("Could not prepare the WebP image.")
            }
            context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
            // WebP expects straight alpha, while Core Graphics draws premultiplied RGBA.
            let rgba = bytes.bindMemory(to: UInt8.self)
            for offset in stride(from: 0, to: rgba.count, by: 4) {
                let alpha = Int(rgba[offset + 3])
                if alpha > 0 && alpha < 255 {
                    for channel in 0..<3 { rgba[offset + channel] = UInt8(min(255, Int(rgba[offset + channel]) * 255 / alpha)) }
                }
            }
            var output: UnsafeMutablePointer<UInt8>?
            let size = encode(rgba.baseAddress, Int32(image.width), Int32(image.height), Int32(image.width * 4), Float(quality * 100), &output)
            guard size > 0, let output else { throw ConversionError.message("WebP conversion failed.") }
            defer { free(UnsafeMutableRawPointer(output)) }
            return Data(bytes: output, count: size)
        }
    }
}
