import Testing
import AppKit
import ImageIO
import PDFKit
@testable import ShiftDrop

@Suite(.serialized)
final class ConversionTests {
    private let directory: URL
    private let engine = ConversionEngine.shared
    init() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("ShiftDropTests-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }
    deinit { try? FileManager.default.removeItem(at: directory) }

    private func fixture() throws -> URL {
        let image = try engine.raster(width: 120, height: 80) { context in
            context.setFillColor(NSColor.systemOrange.cgColor); context.fill(CGRect(x: 0, y: 0, width: 120, height: 80))
            context.setFillColor(NSColor.systemBlue.cgColor); context.fill(CGRect(x: 0, y: 0, width: 60, height: 40))
        }
        let url = directory.appendingPathComponent("Original.png")
        try engine.encode(image, as: .png).write(to: url)
        return url
    }

    @Test func everyImageCodecCreatesRealReadableOutput() throws {
        let input = try fixture()
        for format in [OutputFormat.jpg, .png, .webp, .heic, .tiff, .avif, .bmp] {
            if format == .avif && !(CGImageDestinationCopyTypeIdentifiers() as! [String]).contains(format.typeIdentifier) { continue }
            let output = try #require(engine.convert(input, to: format).first)
            let source = try #require(CGImageSourceCreateWithURL(output as CFURL, nil))
            let image = try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
            #expect(image.width == 120); #expect(image.height == 80)
            #expect(output != input)
            if format == .webp { #expect(String(data: try Data(contentsOf: output).prefix(4), encoding: .ascii) == "RIFF") }
        }
    }

    @Test func conversionNeverOverwritesOriginalOrExistingOutput() throws {
        let input = try fixture(), original = try Data(contentsOf: input)
        let occupied = directory.appendingPathComponent("Original.jpg")
        let sentinel = Data("leave me alone".utf8); try sentinel.write(to: occupied)
        let first = try #require(engine.convert(input, to: .jpg).first)
        let second = try #require(engine.convert(input, to: .jpg).first)
        #expect(first.lastPathComponent == "Original 2.jpg")
        #expect(second.lastPathComponent == "Original 3.jpg")
        #expect(try Data(contentsOf: occupied) == sentinel)
        #expect(try Data(contentsOf: input) == original)
    }

    @Test func multiPagePDFExportsEveryPageAndPreservesOrder() throws {
        let first = try #require(engine.loadImages(fixture()).first)
        let second = try engine.raster(width: 60, height: 100) { context in
            context.setFillColor(NSColor.systemGreen.cgColor); context.fill(CGRect(x: 0, y: 0, width: 60, height: 100))
        }
        let pdf = PDFDocument()
        pdf.insert(try #require(PDFPage(image: NSImage(cgImage: first, size: .zero))), at: 0)
        pdf.insert(try #require(PDFPage(image: NSImage(cgImage: second, size: .zero))), at: 1)
        let input = directory.appendingPathComponent("Pages.pdf")
        try #require(pdf.dataRepresentation()).write(to: input)
        let outputs = try engine.convert(input, to: .png)
        #expect(outputs.map(\.lastPathComponent) == ["Pages Page 001.png", "Pages Page 002.png"])
        let images = try outputs.map { try #require(engine.loadImages($0).first) }
        #expect(images[0].width > images[0].height)
        #expect(images[1].width < images[1].height)
    }

    @Test func textPDFAndDOCXHaveReadableTextAndEscapedXML() throws {
        let input = directory.appendingPathComponent("Notes.txt")
        let text = "A & B < C > D\nThis is a local conversion."
        try Data(text.utf8).write(to: input)
        let pdfURL = try #require(engine.convert(input, to: .pdf).first)
        let pdf = try #require(PDFDocument(url: pdfURL))
        #expect((pdf.string ?? "").contains("A & B < C > D"))
        let docx = try #require(engine.convert(pdfURL, to: .docx).first)
        #expect(try Data(contentsOf: docx).prefix(2) == Data([0x50, 0x4b]))
        let process = Process(); let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
        process.arguments = ["-p", docx.path, "word/document.xml"]; process.standardOutput = pipe
        try process.run()
        let xml = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        process.waitUntilExit()
        #expect(process.terminationStatus == 0)
        #expect(xml.contains("A &amp; B &lt; C &gt; D"))
        let txt = try #require(engine.convert(pdfURL, to: .txt).first)
        #expect(try String(contentsOf: txt).contains("This is a local conversion."))
    }

    @Test func invalidInputsFailWithoutCreatingFiles() throws {
        #expect(throws: (any Error).self) { try FileKind.detect(directory) }
        let fake = directory.appendingPathComponent("broken.png")
        try Data("not an image".utf8).write(to: fake)
        #expect(throws: (any Error).self) { try engine.convert(fake, to: .jpg) }
        #expect(try FileManager.default.contentsOfDirectory(atPath: directory.path) == ["broken.png"])
        #expect(throws: (any Error).self) { try engine.raster(width: 0, height: 10) { _ in } }
        #expect(throws: (any Error).self) { try engine.raster(width: 16000, height: 16000) { _ in } }
    }

    @Test func localOCRReadsAnImage() throws {
        let image = try engine.raster(width: 1200, height: 200) { context in
            context.setFillColor(NSColor.white.cgColor); context.fill(CGRect(x: 0, y: 0, width: 1200, height: 200))
            context.translateBy(x: 0, y: 200); context.scaleBy(x: 1, y: -1)
            NSGraphicsContext.saveGraphicsState(); NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: true)
            NSAttributedString(string: "HELLO SHIFT DROP", attributes: [.font: NSFont.systemFont(ofSize: 72), .foregroundColor: NSColor.black]).draw(at: CGPoint(x: 35, y: 55))
            NSGraphicsContext.restoreGraphicsState()
        }
        let input = directory.appendingPathComponent("Scan.png")
        try engine.encode(image, as: .png).write(to: input)
        let text = try engine.extractText(input, kind: .image)
        #expect(text.uppercased().contains("HELLO SHIFT DROP"))
    }

    @Test func longTextPaginatesWithoutLosingTheLastLine() throws {
        let text = (1...120).map { "Line \($0): This document stays on the Mac." }.joined(separator: "\n")
        let input = directory.appendingPathComponent("Long.txt")
        try Data(text.utf8).write(to: input)
        let output = try #require(engine.convert(input, to: .pdf).first)
        let pdf = try #require(PDFDocument(url: output))
        #expect(pdf.pageCount > 1)
        #expect((pdf.string ?? "").contains("Line 120:"))
    }

    @Test func wheelHitRegionsMatchTheVideo() {
        let center = CGPoint(x: 190, y: 190)
        #expect(WheelGeometry.index(at: CGPoint(x: 190, y: 80), center: center, inner: 60, outer: 164, count: 4) == 0)
        #expect(WheelGeometry.index(at: CGPoint(x: 300, y: 190), center: center, inner: 60, outer: 164, count: 4) == 1)
        #expect(WheelGeometry.index(at: CGPoint(x: 190, y: 300), center: center, inner: 60, outer: 164, count: 4) == 2)
        #expect(WheelGeometry.index(at: CGPoint(x: 80, y: 190), center: center, inner: 60, outer: 164, count: 4) == 3)
        #expect(WheelGeometry.index(at: center, center: center, inner: 60, outer: 164, count: 8) == nil)
        #expect(WheelGeometry.index(at: .zero, center: center, inner: 60, outer: 164, count: 8) == nil)
        #expect(OutputFormat.wheel(for: .pdf, sourceExtension: "pdf") == [.docx, .jpg, .png, .txt])
        #expect(ImageTool.allCases.count == 7)
    }
}
