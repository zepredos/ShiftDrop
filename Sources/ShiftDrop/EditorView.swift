import SwiftUI
import CoreImage
import ImageIO

struct EditorView: View {
    let tool: ImageTool
    let file: URL
    let image: CGImage
    let onClose: () -> Void
    let onSave: (CGImage, String, OutputFormat, Double) -> Void

    @State private var crop = CGRect(x: 0, y: 0, width: 1, height: 1)
    @State private var cropRatio = "Free"
    @State private var backgroundIndex = 0
    @State private var customColor = Color.blue
    @State private var padding = 160.0
    @State private var corners = 40.0
    @State private var shadow = 24.0
    @State private var backgroundRatio = "Auto"
    @State private var quality = 0.7
    @State private var brightness = 0.0
    @State private var contrast = 1.0
    @State private var saturation = 1.0
    @State private var rotation = 0
    @State private var flipped = false
    @State private var strokes: [[CGPoint]] = []
    @State private var redactions: [CGRect] = []
    @State private var preview: CGImage?
    @State private var errorMessage: String?
    @State private var dragOrigin: CGPoint?
    @State private var outputFormat: OutputFormat = .jpg
    private let palettes: [[NSColor]] = [
        [.systemPink, .systemOrange, .systemYellow, .systemPurple],
        [NSColor(red: 0.38, green: 0.55, blue: 0.96, alpha: 1), .white],
        [.systemYellow, .systemGreen, .systemCyan, .systemPink],
        [.systemPurple.withAlphaComponent(0.6), .white],
        [NSColor(red: 0.80, green: 0.61, blue: 0.96, alpha: 1), .systemPink.withAlphaComponent(0.3)],
        [.systemRed, .systemGreen, .black],
        [.systemBlue, .systemCyan], [.systemCyan, .systemMint],
        [.white, NSColor(red: 0.65, green: 0.72, blue: 0.95, alpha: 1)],
        [.white], [.systemYellow], [.systemGreen], [.systemMint], [.systemTeal], [.systemCyan], [.systemBlue],
        [NSColor(red: 0.1, green: 0.14, blue: 0.22, alpha: 1)], [.systemPurple]
    ]

    var body: some View {
        GlassSurface {
            VStack(spacing: 0) {
                header
                Divider().opacity(0.3)
                if tool == .metadata { metadataContent }
                else {
                    imagePreview
                        .padding(.horizontal, 24).padding(.top, 22).padding(.bottom, tool == .background ? 18 : 20)
                    controls.padding(.horizontal, 22)
                    Spacer(minLength: 12)
                }
                Divider().opacity(0.3)
                footer
            }
        }
        .onAppear { updatePreview() }
        .onChange(of: backgroundIndex) { _, _ in updatePreview() }
        .onChange(of: customColor) { _, _ in updatePreview() }
        .onChange(of: padding) { _, _ in updatePreview() }
        .onChange(of: corners) { _, _ in updatePreview() }
        .onChange(of: shadow) { _, _ in updatePreview() }
        .onChange(of: backgroundRatio) { _, _ in updatePreview() }
        .onChange(of: brightness) { _, _ in updatePreview() }
        .onChange(of: contrast) { _, _ in updatePreview() }
        .onChange(of: saturation) { _, _ in updatePreview() }
        .onChange(of: rotation) { _, _ in updatePreview() }
        .onChange(of: flipped) { _, _ in updatePreview() }
        .alert("Could not save image", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) { Button("OK") {} } message: { Text(errorMessage ?? "") }
    }

    private var header: some View {
        HStack {
            Button(action: onClose) { Image(systemName: "xmark").font(.system(size: 10, weight: .medium)).frame(width: 23, height: 23) }
                .buttonStyle(.plain).keyboardShortcut(.cancelAction).accessibilityLabel("Close editor")
            Spacer(); Text(tool.title).font(.system(size: 14, weight: .semibold)); Spacer()
            Color.clear.frame(width: 23, height: 23)
        }.padding(.horizontal, 16).frame(height: 46)
    }

    @ViewBuilder private var imagePreview: some View {
        if tool == .crop {
            CropCanvas(image: image, crop: $crop, ratio: cropAspect).frame(height: 410)
        } else if tool == .annotate || tool == .redact {
            GeometryReader { geometry in
                let rect = imageRect(in: geometry.size, image: image)
                ZStack(alignment: .topLeading) {
                    Image(nsImage: NSImage(cgImage: image, size: .zero)).resizable().frame(width: rect.width, height: rect.height).position(x: rect.midX, y: rect.midY)
                    Canvas { context, _ in
                        for stroke in strokes {
                            var path = Path()
                            for (index, point) in stroke.enumerated() {
                                let p = CGPoint(x: rect.minX + point.x * rect.width, y: rect.minY + point.y * rect.height)
                                if index == 0 { path.move(to: p) } else { path.addLine(to: p) }
                            }
                            context.stroke(path, with: .color(ember), style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))
                        }
                        for box in redactions {
                            context.fill(Path(CGRect(x: rect.minX + box.minX * rect.width, y: rect.minY + box.minY * rect.height, width: box.width * rect.width, height: box.height * rect.height)), with: .color(.black))
                        }
                    }
                    .contentShape(Rectangle())
                    .gesture(DragGesture(minimumDistance: 0).onChanged { value in
                        let point = CGPoint(x: min(1, max(0, (value.location.x - rect.minX) / rect.width)), y: min(1, max(0, (value.location.y - rect.minY) / rect.height)))
                        if dragOrigin == nil {
                            dragOrigin = point
                            if tool == .annotate { strokes.append([point]) } else { redactions.append(CGRect(origin: point, size: .zero)) }
                        }
                        if tool == .annotate { strokes[strokes.count - 1].append(point) }
                        else if let origin = dragOrigin { redactions[redactions.count - 1] = CGRect(x: min(origin.x, point.x), y: min(origin.y, point.y), width: abs(point.x - origin.x), height: abs(point.y - origin.y)) }
                    }.onEnded { _ in dragOrigin = nil })
                }
            }.frame(height: 410)
        } else {
            Image(nsImage: NSImage(cgImage: preview ?? image, size: .zero))
                .resizable().interpolation(.high).scaledToFit()
                .frame(maxWidth: .infinity).frame(height: tool == .background ? 316 : 370)
                .background(.black.opacity(0.025), in: RoundedRectangle(cornerRadius: 3))
        }
    }

    @ViewBuilder private var controls: some View {
        switch tool {
        case .crop:
            HStack(spacing: 8) {
                Text("Aspect ratio").frame(width: 76, alignment: .leading)
                ratioPicker(selection: $cropRatio, values: ["Free", "1:1", "16:9", "9:16", "4:3", "3:4"])
            }.font(.system(size: 11))
            .onChange(of: cropRatio) { _, _ in fitCropRatio() }
            HStack(spacing: 7) {
                Text("W")
                TextField("Width", value: Binding(get: { Int((crop.width * Double(image.width)).rounded()) }, set: { crop.size.width = min(1 - crop.minX, max(1 / Double(image.width), Double($0) / Double(image.width))); constrainCropHeight() }), format: .number.grouping(.never))
                    .frame(width: 66).textFieldStyle(.roundedBorder).accessibilityLabel("Crop width in pixels")
                Text("H")
                TextField("Height", value: Binding(get: { Int((crop.height * Double(image.height)).rounded()) }, set: { crop.size.height = min(1 - crop.minY, max(1 / Double(image.height), Double($0) / Double(image.height))); if let ratio = cropAspect { crop.size.width = min(1 - crop.minX, crop.height * Double(image.height) * ratio / Double(image.width)); constrainCropHeight() } }), format: .number.grouping(.never))
                    .frame(width: 66).textFieldStyle(.roundedBorder).accessibilityLabel("Crop height in pixels")
                Text("px").opacity(0.6); Spacer()
            }.font(.system(size: 11)).padding(.top, 12)
        case .background:
            HStack(alignment: .top, spacing: 12) {
                Text("Background").font(.system(size: 11)).frame(width: 76, alignment: .leading).padding(.top, 8)
                VStack(spacing: 7) {
                    HStack(spacing: 5) { ForEach(0..<9) { swatch($0) } }
                    HStack(spacing: 5) { ForEach(9..<18) { swatch($0) } }
                }
                ColorPicker("Custom", selection: $customColor, supportsOpacity: false).labelsHidden().scaleEffect(0.85).frame(width: 24)
                    .onChange(of: customColor) { _, _ in backgroundIndex = 18 }
                    .accessibilityLabel("Custom background color")
            }.padding(.bottom, 14)
            slider("Padding", value: $padding, range: 0...1000, unit: "px")
            slider("Corners", value: $corners, range: 0...400, unit: "px")
            slider("Shadow", value: $shadow, range: 0...100, unit: "px")
            HStack { Text("Ratio").font(.system(size: 11)); Spacer(); ratioPicker(selection: $backgroundRatio, values: ["Auto", "1:1", "16:9", "4:5"]) }.padding(.top, 4)
        case .compress:
            slider("Quality", value: $quality, range: 0.1...1, unit: "%", multiplier: 100)
            HStack {
                Text("Format").font(.system(size: 11)); Spacer()
                Picker("Format", selection: $outputFormat) { ForEach([OutputFormat.jpg, .heic, .webp], id: \.self) { Text($0.rawValue).tag($0) } }.labelsHidden().frame(width: 128)
            }.padding(.top, 8)
            Text("A separate compressed copy keeps your original safe.").font(.system(size: 10)).opacity(0.6).padding(.top, 10)
        case .edit:
            slider("Brightness", value: $brightness, range: -0.5...0.5, unit: "", multiplier: 100)
            slider("Contrast", value: $contrast, range: 0.2...2, unit: "", multiplier: 100)
            slider("Saturation", value: $saturation, range: 0...2, unit: "", multiplier: 100)
            HStack(spacing: 10) {
                Button { rotation = (rotation + 1) % 4 } label: { Label("Rotate", systemImage: "rotate.right") }
                Button { flipped.toggle() } label: { Label("Flip", systemImage: "arrow.left.and.right.righttriangle.left.righttriangle.right") }
                Spacer()
            }.controlSize(.small).padding(.top, 6)
        case .annotate, .redact:
            HStack {
                Text(tool == .annotate ? "Draw on the image to annotate." : "Drag over areas to cover them permanently.").font(.system(size: 11)).opacity(0.7)
                Spacer()
                Button("Undo") { if tool == .annotate { if !strokes.isEmpty { strokes.removeLast() } } else if !redactions.isEmpty { redactions.removeLast() } }.controlSize(.small)
            }
            Text(tool == .redact ? "Saved as a flattened PNG with the covered pixels removed." : "Saved as a separate PNG.").font(.system(size: 10)).opacity(0.55).padding(.top, 10)
        case .metadata: EmptyView()
        }
    }

    private var metadataContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Image(nsImage: NSImage(cgImage: image, size: .zero)).resizable().scaledToFit().frame(height: 190).frame(maxWidth: .infinity)
                Text(file.lastPathComponent).font(.system(size: 14, weight: .semibold)).textSelection(.enabled)
                Text("\(image.width) × \(image.height) pixels").font(.system(size: 12))
                if let source = CGImageSourceCreateWithURL(file as CFURL, nil), let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [String: Any] {
                    Text(properties.sorted { $0.key < $1.key }.map { "\($0.key): \($0.value)" }.joined(separator: "\n\n"))
                        .font(.system(size: 10, design: .monospaced)).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
                }
            }.padding(24)
        }
    }

    private var footer: some View {
        HStack {
            if tool != .metadata { Button("Reset", action: reset).buttonStyle(.bordered).controlSize(.small) }
            Spacer()
            Button(tool == .metadata ? "Done" : tool == .background ? "Save with Background" : tool == .crop ? "Apply" : "Save Copy", action: save)
                .buttonStyle(.borderedProminent).controlSize(.small).keyboardShortcut(.defaultAction)
        }.padding(.horizontal, 20).frame(height: 52)
    }

    private func swatch(_ index: Int) -> some View {
        Button { backgroundIndex = index } label: {
            RoundedRectangle(cornerRadius: 4)
                .fill(LinearGradient(colors: palettes[index].map(Color.init(nsColor:)), startPoint: .topLeading, endPoint: .bottomTrailing))
                .frame(width: 25, height: 26)
                .overlay(RoundedRectangle(cornerRadius: 4).stroke(backgroundIndex == index ? ember : .white.opacity(0.4), lineWidth: backgroundIndex == index ? 2.5 : 0.5))
        }.buttonStyle(.plain).accessibilityLabel("Background \(index + 1)")
    }
    private func slider(_ title: String, value: Binding<Double>, range: ClosedRange<Double>, unit: String, multiplier: Double = 1) -> some View {
        HStack(spacing: 12) {
            Text(title).frame(width: 76, alignment: .leading)
            Slider(value: value, in: range).controlSize(.mini).accessibilityLabel(title)
            Text("\(Int((value.wrappedValue * multiplier).rounded()))\(unit.isEmpty ? "" : " " + unit)").monospacedDigit().opacity(0.65).frame(width: 48, alignment: .trailing)
        }.font(.system(size: 11)).frame(height: 27)
    }
    private func ratioPicker(selection: Binding<String>, values: [String]) -> some View {
        HStack(spacing: 0) {
            ForEach(values, id: \.self) { value in
                Button { selection.wrappedValue = value } label: {
                    Text(value).font(.system(size: 10.5, weight: selection.wrappedValue == value ? .medium : .regular))
                        .frame(minWidth: value.count > 3 ? 35 : 29).padding(.vertical, 4)
                        .background(selection.wrappedValue == value ? ember : .clear, in: RoundedRectangle(cornerRadius: 4))
                        .foregroundStyle(selection.wrappedValue == value ? .white : Color.primary.opacity(0.75))
                }.buttonStyle(.plain).accessibilityLabel("\(value) ratio").accessibilityAddTraits(selection.wrappedValue == value ? [.isSelected] : [])
            }
        }.padding(2).background(.black.opacity(0.04), in: RoundedRectangle(cornerRadius: 5))
    }

    private var cropAspect: Double? { aspect(cropRatio) }
    private func aspect(_ value: String) -> Double? {
        let pieces = value.split(separator: ":").compactMap { Double($0) }
        return pieces.count == 2 ? pieces[0] / pieces[1] : nil
    }
    private func fitCropRatio() {
        guard let ratio = cropAspect else { return }
        let normalized = ratio * Double(image.height) / Double(image.width)
        let width = min(1.0, normalized), height = min(1.0, 1 / normalized)
        crop = CGRect(x: (1 - width) / 2, y: (1 - height) / 2, width: width, height: height)
    }
    private func constrainCropHeight() {
        if let ratio = cropAspect {
            let normalized = ratio * Double(image.height) / Double(image.width)
            crop.size.height = min(1 - crop.minY, crop.width / normalized)
            crop.size.width = crop.height * normalized
        }
    }
    private func reset() {
        crop = CGRect(x: 0, y: 0, width: 1, height: 1); cropRatio = "Free"
        backgroundIndex = 0; padding = 160; corners = 40; shadow = 24; backgroundRatio = "Auto"
        quality = 0.7; brightness = 0; contrast = 1; saturation = 1; rotation = 0; flipped = false
        strokes = []; redactions = []; updatePreview()
    }
    private func updatePreview() {
        guard tool == .background || tool == .edit else { return }
        do { preview = try rendered(previewOnly: true) } catch { errorMessage = error.localizedDescription }
    }
    private func save() {
        if tool == .metadata { onClose(); return }
        do {
            let rendered = try rendered(previewOnly: false)
            let suffix: String
            switch tool {
            case .crop: suffix = " Cropped"
            case .background: suffix = " Background"
            case .compress: suffix = " Compressed"
            case .edit: suffix = " Edited"
            case .annotate: suffix = " Annotated"
            case .redact: suffix = " Redacted"
            case .metadata: suffix = ""
            }
            let format: OutputFormat = tool == .compress ? outputFormat : tool == .crop && ["jpg", "jpeg"].contains(file.pathExtension.lowercased()) ? .jpg : .png
            onSave(rendered, suffix, format, tool == .compress ? quality : 0.94)
        } catch { errorMessage = error.localizedDescription }
    }

    private func rendered(previewOnly: Bool) throws -> CGImage {
        let engine = ConversionEngine.shared
        if tool == .crop {
            let rect = CGRect(x: (crop.minX * Double(image.width)).rounded(.down), y: (crop.minY * Double(image.height)).rounded(.down), width: max(1, (crop.width * Double(image.width)).rounded(.down)), height: max(1, (crop.height * Double(image.height)).rounded(.down)))
            guard let output = image.cropping(to: rect) else { throw ConversionError.message("Choose a crop area inside the image.") }
            return output
        }
        if tool == .background {
            let pad = padding
            var width = Double(image.width) + pad * 2, height = Double(image.height) + pad * 2
            if let ratio = aspect(backgroundRatio) {
                if width / height > ratio { height = width / ratio } else { width = height * ratio }
            }
            let scale = previewOnly ? min(1, 1000 / max(width, height)) : 1
            let w = Int((width * scale).rounded()), h = Int((height * scale).rounded())
            return try engine.raster(width: w, height: h) { context in
                let colors = backgroundIndex == 18 ? [NSColor(customColor)] : palettes[backgroundIndex]
                if colors.count == 1 { context.setFillColor(colors[0].cgColor); context.fill(CGRect(x: 0, y: 0, width: w, height: h)) }
                else if let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors.map(\.cgColor) as CFArray, locations: nil) {
                    context.drawLinearGradient(gradient, start: CGPoint(x: 0, y: h), end: CGPoint(x: w, y: 0), options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
                    if colors.count > 3 {
                        let glows: [(NSColor, CGPoint, CGFloat)] = [
                            (.systemYellow, CGPoint(x: w, y: h), 0.85),
                            (.systemPurple, CGPoint(x: w, y: 0), 0.7),
                            (.systemBlue, CGPoint(x: w, y: 0), 0.42),
                            (NSColor(red: 1, green: 0.72, blue: 0.62, alpha: 1), CGPoint(x: 0, y: 0), 0.5)
                        ]
                        for (color, point, radius) in glows {
                            let glow = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: [color.withAlphaComponent(0.95).cgColor, color.withAlphaComponent(0).cgColor] as CFArray, locations: [0, 1])!
                            context.drawRadialGradient(glow, startCenter: point, startRadius: 0, endCenter: point, endRadius: CGFloat(max(w, h)) * radius, options: [])
                        }
                    }
                }
                let rect = CGRect(x: (width - Double(image.width)) / 2 * scale, y: (height - Double(image.height)) / 2 * scale, width: Double(image.width) * scale, height: Double(image.height) * scale)
                let radius = min(corners * scale, min(rect.width, rect.height) / 2)
                let path = CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil)
                context.saveGState()
                context.setShadow(offset: CGSize(width: 0, height: -shadow * scale / 3), blur: shadow * scale, color: NSColor.black.withAlphaComponent(0.38).cgColor)
                context.setFillColor(NSColor.white.cgColor); context.addPath(path); context.fillPath()
                context.restoreGState()
                context.addPath(path); context.clip(); context.interpolationQuality = .high; context.draw(image, in: rect)
            }
        }
        if tool == .edit {
            var ci = CIImage(cgImage: image).applyingFilter("CIColorControls", parameters: [kCIInputBrightnessKey: brightness, kCIInputContrastKey: contrast, kCIInputSaturationKey: saturation])
            if flipped { ci = ci.oriented(.upMirrored) }
            for _ in 0..<rotation { ci = ci.oriented(.right) }
            if previewOnly { ci = ci.transformed(by: CGAffineTransform(scaleX: min(1, 1000 / ci.extent.width), y: min(1, 1000 / ci.extent.width))) }
            guard let result = CIContext().createCGImage(ci, from: ci.extent) else { throw ConversionError.message("Could not apply the image adjustments.") }
            return result
        }
        if tool == .annotate || tool == .redact {
            return try engine.raster(width: image.width, height: image.height) { context in
                context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
                context.translateBy(x: 0, y: CGFloat(image.height)); context.scaleBy(x: CGFloat(image.width), y: -CGFloat(image.height))
                if tool == .redact {
                    context.setFillColor(NSColor.black.cgColor)
                    for rect in redactions { context.fill(rect) }
                } else {
                    context.setStrokeColor(NSColor(red: 0.93, green: 0.24, blue: 0.055, alpha: 1).cgColor)
                    context.setLineWidth(3.0 / 380); context.setLineCap(.round); context.setLineJoin(.round)
                    for stroke in strokes {
                        guard let first = stroke.first else { continue }; context.move(to: first)
                        if stroke.count == 1 { context.addLine(to: CGPoint(x: first.x + 0.0001, y: first.y)) }
                        else { for point in stroke.dropFirst() { context.addLine(to: point) } }
                        context.strokePath()
                    }
                }
            }
        }
        return image
    }
}

func imageRect(in size: CGSize, image: CGImage) -> CGRect {
    let scale = min(size.width / CGFloat(image.width), size.height / CGFloat(image.height))
    let width = CGFloat(image.width) * scale, height = CGFloat(image.height) * scale
    return CGRect(x: (size.width - width) / 2, y: (size.height - height) / 2, width: width, height: height)
}

struct CropCanvas: View {
    let image: CGImage
    @Binding var crop: CGRect
    let ratio: Double?
    @State private var initial: CGRect?
    @State private var handle = -1

    var body: some View {
        GeometryReader { geometry in
            let rect = imageRect(in: geometry.size, image: image)
            let selection = CGRect(x: rect.minX + crop.minX * rect.width, y: rect.minY + crop.minY * rect.height, width: crop.width * rect.width, height: crop.height * rect.height)
            ZStack(alignment: .topLeading) {
                Image(nsImage: NSImage(cgImage: image, size: .zero)).resizable().frame(width: rect.width, height: rect.height).position(x: rect.midX, y: rect.midY)
                Path { path in path.addRect(rect); path.addRect(selection) }.fill(.black.opacity(0.55), style: FillStyle(eoFill: true)).allowsHitTesting(false)
                Rectangle().stroke(ember, lineWidth: 1.5).frame(width: selection.width, height: selection.height).position(x: selection.midX, y: selection.midY)
                Path { path in
                    for factor in [1.0 / 3, 2.0 / 3] {
                        path.move(to: CGPoint(x: selection.minX + selection.width * factor, y: selection.minY)); path.addLine(to: CGPoint(x: selection.minX + selection.width * factor, y: selection.maxY))
                        path.move(to: CGPoint(x: selection.minX, y: selection.minY + selection.height * factor)); path.addLine(to: CGPoint(x: selection.maxX, y: selection.minY + selection.height * factor))
                    }
                }.stroke(.white.opacity(0.35), lineWidth: 0.6).allowsHitTesting(false)
                ForEach(0..<8) { index in
                    let point = handles(selection)[index]
                    RoundedRectangle(cornerRadius: 1.5).fill(ember)
                        .frame(width: index % 2 == 0 ? 9 : index == 1 || index == 5 ? 18 : 5, height: index % 2 == 0 ? 9 : index == 1 || index == 5 ? 5 : 18)
                        .position(point)
                }
            }
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0).onChanged { value in
                if initial == nil {
                    initial = crop
                    let points = handles(selection)
                    handle = points.indices.min { hypot(points[$0].x - value.startLocation.x, points[$0].y - value.startLocation.y) < hypot(points[$1].x - value.startLocation.x, points[$1].y - value.startLocation.y) } ?? -1
                    if handle >= 0, hypot(points[handle].x - value.startLocation.x, points[handle].y - value.startLocation.y) > 20 { handle = selection.contains(value.startLocation) ? 8 : 9 }
                }
                guard let initial else { return }
                let dx = value.translation.width / rect.width, dy = value.translation.height / rect.height
                if handle == 8 {
                    crop.origin = CGPoint(x: min(1 - initial.width, max(0, initial.minX + dx)), y: min(1 - initial.height, max(0, initial.minY + dy)))
                    return
                }
                if handle == 9 {
                    let start = CGPoint(x: min(1, max(0, (value.startLocation.x - rect.minX) / rect.width)), y: min(1, max(0, (value.startLocation.y - rect.minY) / rect.height)))
                    let end = CGPoint(x: min(1, max(0, (value.location.x - rect.minX) / rect.width)), y: min(1, max(0, (value.location.y - rect.minY) / rect.height)))
                    crop = CGRect(x: min(start.x, end.x), y: min(start.y, end.y), width: max(0.005, abs(end.x - start.x)), height: max(0.005, abs(end.y - start.y)))
                } else {
                    var x0 = initial.minX, x1 = initial.maxX, y0 = initial.minY, y1 = initial.maxY
                    if [0, 6, 7].contains(handle) { x0 = min(x1 - 0.005, max(0, x0 + dx)) }
                    if [2, 3, 4].contains(handle) { x1 = max(x0 + 0.005, min(1, x1 + dx)) }
                    if [0, 1, 2].contains(handle) { y0 = min(y1 - 0.005, max(0, y0 + dy)) }
                    if [4, 5, 6].contains(handle) { y1 = max(y0 + 0.005, min(1, y1 + dy)) }
                    crop = CGRect(x: x0, y: y0, width: x1 - x0, height: y1 - y0)
                }
                if let ratio {
                    let normalized = ratio * Double(image.height) / Double(image.width)
                    let height = crop.width / normalized
                    if crop.minY + height <= 1 { crop.size.height = height }
                    else { crop.size.height = 1 - crop.minY; crop.size.width = crop.height * normalized }
                }
            }.onEnded { _ in initial = nil })
            .accessibilityLabel("Crop selection. Drag its edges or enter pixel dimensions below.")
        }
    }
    private func handles(_ rect: CGRect) -> [CGPoint] {
        [CGPoint(x: rect.minX, y: rect.minY), CGPoint(x: rect.midX, y: rect.minY), CGPoint(x: rect.maxX, y: rect.minY), CGPoint(x: rect.maxX, y: rect.midY), CGPoint(x: rect.maxX, y: rect.maxY), CGPoint(x: rect.midX, y: rect.maxY), CGPoint(x: rect.minX, y: rect.maxY), CGPoint(x: rect.minX, y: rect.midY)]
    }
}
