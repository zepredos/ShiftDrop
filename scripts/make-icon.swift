import AppKit

let output = CommandLine.arguments.dropFirst().first ?? ".reference/AppIcon.iconset"
try FileManager.default.createDirectory(atPath: output, withIntermediateDirectories: true)
for size in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let pixels = size * scale
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        let factor = CGFloat(pixels) / 1024
        let context = NSGraphicsContext.current!.cgContext
        context.scaleBy(x: factor, y: factor)
        let base = NSBezierPath(roundedRect: NSRect(x: 60, y: 60, width: 904, height: 904), xRadius: 206, yRadius: 206)
        let gradient = NSGradient(starting: NSColor(red: 1, green: 0.72, blue: 0.37, alpha: 1), ending: NSColor(red: 0.91, green: 0.22, blue: 0.08, alpha: 1))!
        gradient.draw(in: base, angle: -65)
        let center = CGPoint(x: 512, y: 512)
        for index in 0..<8 {
            let middle = CGFloat.pi / 2 - CGFloat(index) * .pi / 4
            let start = middle - .pi / 8 + 0.024, end = middle + .pi / 8 - 0.024
            let path = CGMutablePath()
            path.addArc(center: center, radius: 338, startAngle: start, endAngle: end, clockwise: false)
            path.addArc(center: center, radius: 152, startAngle: end, endAngle: start, clockwise: true)
            path.closeSubpath()
            context.addPath(path); context.setFillColor(NSColor.white.withAlphaComponent(index == 1 ? 0.96 : 0.55).cgColor); context.fillPath()
        }
        let arrow = NSBezierPath()
        arrow.move(to: CGPoint(x: 512, y: 432)); arrow.line(to: CGPoint(x: 512, y: 589))
        arrow.move(to: CGPoint(x: 457, y: 535)); arrow.line(to: CGPoint(x: 512, y: 590)); arrow.line(to: CGPoint(x: 567, y: 535))
        arrow.lineWidth = 25; arrow.lineCapStyle = .round; arrow.lineJoinStyle = .round; NSColor.white.setStroke(); arrow.stroke()
        NSGraphicsContext.restoreGraphicsState()
        let filename = "icon_\(size)x\(size)\(scale == 2 ? "@2x" : "").png"
        try rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: output).appendingPathComponent(filename))
    }
}
