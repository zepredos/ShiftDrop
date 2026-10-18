import AppKit
import UniformTypeIdentifiers

enum FileKind {
    case pdf, image, text

    static func detect(_ url: URL) throws -> FileKind {
        let values = try url.resourceValues(forKeys: [.isRegularFileKey, .contentTypeKey])
        guard values.isRegularFile == true else { throw ConversionError.message("Choose a file, rather than a folder.") }
        if url.pathExtension.lowercased() == "pdf" { return .pdf }
        if let type = values.contentType {
            if type.conforms(to: .image) { return .image }
            if type.conforms(to: .text) || type == .rtf || type.identifier == "org.openxmlformats.wordprocessingml.document" { return .text }
        }
        throw ConversionError.message("This version supports images, PDFs, and text documents.")
    }
}

enum OutputFormat: String, CaseIterable {
    case docx = "DOCX", jpg = "JPG", png = "PNG", txt = "TXT"
    case webp = "WEBP", heic = "HEIC", tiff = "TIFF", avif = "AVIF", bmp = "BMP", pdf = "PDF"

    var fileExtension: String { rawValue.lowercased() }
    var typeIdentifier: String {
        switch self {
        case .jpg: return "public.jpeg"
        case .png: return "public.png"
        case .heic: return "public.heic"
        case .tiff: return "public.tiff"
        case .avif: return "public.avif"
        case .bmp: return "com.microsoft.bmp"
        case .webp: return "org.webmproject.webp"
        default: return "public.data"
        }
    }

    static func wheel(for kind: FileKind, sourceExtension: String) -> [OutputFormat] {
        switch kind {
        case .pdf: return [.docx, .jpg, .png, .txt]
        case .text: return [.pdf, .docx, .txt, .png]
        case .image:
            let primary: OutputFormat = sourceExtension.lowercased() == "png" ? .jpg : .png
            return [primary, .webp, .heic, .tiff, .avif, .bmp, .pdf, .docx]
        }
    }
}

enum ImageTool: String, CaseIterable {
    case compress = "COMPRESS", metadata = "METADATA", edit = "EDIT", annotate = "ANNOTATE"
    case background = "ADD BG", crop = "CROP", redact = "REDACT"
    var symbol: String {
        switch self {
        case .compress: return "arrow.down.right.and.arrow.up.left"
        case .metadata: return "tag"
        case .edit: return "slider.horizontal.3"
        case .annotate: return "pencil.tip.crop.circle"
        case .background: return "photo"
        case .crop: return "crop"
        case .redact: return "eye.slash"
        }
    }
    var title: String {
        switch self {
        case .crop: return "Crop Image"
        case .background: return "Add BG"
        case .compress: return "Compress Image"
        case .metadata: return "Metadata"
        case .edit: return "Edit Image"
        case .annotate: return "Annotate Image"
        case .redact: return "Redact Image"
        }
    }
}

enum WheelAction: Equatable {
    case convert(OutputFormat), tool(ImageTool)
    var title: String {
        switch self { case .convert(let f): return f.rawValue; case .tool(let t): return t.rawValue }
    }
    var symbol: String? { if case .tool(let tool) = self { return tool.symbol }; return nil }
}

enum ConversionError: LocalizedError {
    case message(String)
    var errorDescription: String? { if case .message(let message) = self { return message }; return nil }
}

enum WheelGeometry {
    static func index(at point: CGPoint, center: CGPoint, inner: CGFloat, outer: CGFloat, count: Int) -> Int? {
        let dx = point.x - center.x, dy = point.y - center.y
        let radius = hypot(dx, dy)
        guard radius >= inner, radius <= outer, count > 0 else { return nil }
        let step = 2 * CGFloat.pi / CGFloat(count)
        var angle = atan2(dy, dx) + .pi / 2 + step / 2
        if angle < 0 { angle += 2 * .pi }
        return Int(angle / step) % count
    }
}
