import AppKit

final class FloatingPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

final class WheelView: NSView {
    var actions: [WheelAction] = [] { didSet { selectedIndex = nil; needsDisplay = true; updateAccessibility() } }
    var fileSize = "" { didSet { needsDisplay = true } }
    var selectedIndex: Int? { didSet { if oldValue != selectedIndex { needsDisplay = true; setAccessibilityValue(selectedIndex.map { actions[$0].title } ?? fileSize) } } }
    var onAction: ((WheelAction, [URL]) -> Void)?
    var onToggle: (() -> Void)?
    var onCancel: (() -> Void)?
    var files: [URL] = []
    private var tracking: NSTrackingArea?
    private let wheelRadius: CGFloat = 164
    private let innerRadius: CGFloat = 60
    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }
    var center: CGPoint { CGPoint(x: bounds.midX, y: bounds.midY) }

    override init(frame: NSRect) {
        super.init(frame: frame)
        registerForDraggedTypes([.fileURL, NSPasteboard.PasteboardType("NSFilenamesPboardType")])
        setAccessibilityElement(true)
        setAccessibilityRole(.group)
        setAccessibilityLabel("Conversion wheel")
        setAccessibilityHelp("Arrow keys choose a format. Return converts. Tab switches between formats and tools. Escape closes.")
    }
    required init?(coder: NSCoder) { fatalError() }

    override func viewDidMoveToWindow() { super.viewDidMoveToWindow(); updateAccessibility() }
    func refreshAccessibility() { updateAccessibility() }
    override func accessibilityChildren() -> [Any]? { accessibleActions }
    private var accessibleActions: [WheelAccessibleButton] = []
    private func updateAccessibility() {
        accessibleActions = actions.enumerated().map { index, action in
            let button = WheelAccessibleButton()
            button.setAccessibilityRole(.button)
            button.setAccessibilityEnabled(true)
            button.setAccessibilityLabel(action.title)
            button.setAccessibilityParent(self)
            let point = polar(114, -.pi / 2 + CGFloat(index) * 2 * .pi / CGFloat(actions.count))
            let rect = convert(CGRect(x: point.x - 32, y: point.y - 24, width: 64, height: 48), to: nil)
            button.setAccessibilityFrame(window?.convertToScreen(rect) ?? rect)
            button.onPress = { [weak self] in guard let self else { return }; self.onAction?(action, self.files) }
            return button
        }
        if actions.first?.symbol != nil || actions.count == 8 {
            let toggle = WheelAccessibleButton()
            toggle.setAccessibilityRole(.button); toggle.setAccessibilityEnabled(true); toggle.setAccessibilityLabel("Switch formats and image tools")
            toggle.setAccessibilityParent(self)
            let rect = convert(CGRect(x: center.x - 48, y: center.y - 23, width: 96, height: 46), to: nil)
            toggle.setAccessibilityFrame(window?.convertToScreen(rect) ?? rect)
            toggle.onPress = { [weak self] in self?.onToggle?() }
            accessibleActions.append(toggle)
        }
    }

    override func updateTrackingAreas() {
        if let tracking { removeTrackingArea(tracking) }
        tracking = NSTrackingArea(rect: bounds, options: [.activeAlways, .mouseMoved, .mouseEnteredAndExited], owner: self)
        addTrackingArea(tracking!)
        super.updateTrackingAreas()
    }

    func update(at point: CGPoint) {
        selectedIndex = WheelGeometry.index(at: point, center: center, inner: innerRadius, outer: wheelRadius, count: actions.count)
    }
    override func mouseMoved(with event: NSEvent) { update(at: convert(event.locationInWindow, from: nil)) }
    override func mouseExited(with event: NSEvent) { selectedIndex = nil }
    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        if hypot(point.x - center.x, point.y - center.y) < innerRadius { onToggle?(); return }
        update(at: point)
        if let selectedIndex { onAction?(actions[selectedIndex], files) }
        else { onCancel?() }
    }
    override func keyDown(with event: NSEvent) {
        switch event.keyCode {
        case 53: onCancel?()
        case 48: onToggle?()
        case 123, 126: selectedIndex = ((selectedIndex ?? 0) + actions.count - 1) % actions.count
        case 124, 125: selectedIndex = ((selectedIndex ?? -1) + 1) % actions.count
        case 36, 76: if let selectedIndex { onAction?(actions[selectedIndex], files) }
        default: super.keyDown(with: event)
        }
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation { draggingUpdated(sender) }
    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        update(at: convert(sender.draggingLocation, from: nil))
        return selectedIndex == nil ? [] : .copy
    }
    override func draggingExited(_ sender: NSDraggingInfo?) { selectedIndex = nil }
    override func prepareForDragOperation(_ sender: NSDraggingInfo) -> Bool { selectedIndex != nil }
    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        update(at: convert(sender.draggingLocation, from: nil))
        guard let selectedIndex else { return false }
        let urls = Self.urls(from: sender.draggingPasteboard)
        guard !urls.isEmpty else { return false }
        onAction?(actions[selectedIndex], urls)
        return true
    }
    override func wantsPeriodicDraggingUpdates() -> Bool { true }

    static func urls(from pasteboard: NSPasteboard) -> [URL] {
        if let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL], !urls.isEmpty { return urls }
        if let paths = pasteboard.propertyList(forType: NSPasteboard.PasteboardType("NSFilenamesPboardType")) as? [String] {
            return paths.map { URL(fileURLWithPath: $0) }
        }
        return []
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let context = NSGraphicsContext.current?.cgContext, !actions.isEmpty else { return }
        let disk = NSBezierPath(ovalIn: CGRect(x: center.x - wheelRadius - 5, y: center.y - wheelRadius - 5, width: (wheelRadius + 5) * 2, height: (wheelRadius + 5) * 2))
        NSColor(calibratedRed: 0.93, green: 0.81, blue: 0.62, alpha: 0.28).setFill(); disk.fill()
        NSColor.white.withAlphaComponent(0.65).setStroke(); disk.lineWidth = 1; disk.stroke()
        let step = 2 * CGFloat.pi / CGFloat(actions.count)
        for (index, action) in actions.enumerated() {
            let middle = -.pi / 2 + CGFloat(index) * step
            let path = petal(start: middle - step / 2 + 0.014, end: middle + step / 2 - 0.014)
            context.saveGState(); context.addPath(path); context.clip()
            let selected = selectedIndex == index
            let colors: [CGColor] = selected ? [
                NSColor(calibratedRed: 0.99, green: 0.31, blue: 0.06, alpha: 0.98).cgColor,
                NSColor(calibratedRed: 0.86, green: 0.18, blue: 0.025, alpha: 0.95).cgColor
            ] : [
                NSColor(calibratedRed: 1, green: 0.96, blue: 0.83, alpha: 0.75).cgColor,
                NSColor(calibratedRed: 1, green: 0.86, blue: 0.77, alpha: 0.65).cgColor
            ]
            if let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors as CFArray, locations: [0, 1]) {
                context.drawLinearGradient(gradient, start: CGPoint(x: 0, y: 20), end: CGPoint(x: bounds.width, y: bounds.height), options: [])
            }
            context.restoreGState()
            context.addPath(path); context.setStrokeColor(NSColor.white.withAlphaComponent(selected ? 0.18 : 0.4).cgColor); context.setLineWidth(0.7); context.strokePath()
            let radius: CGFloat = actions.count == 4 ? 113 : 114
            let point = polar(radius, middle)
            let color = selected ? NSColor.white : NSColor(calibratedRed: 0.20, green: 0.15, blue: 0.10, alpha: 1)
            if let symbol = action.symbol, let icon = NSImage(systemSymbolName: symbol, accessibilityDescription: action.title) {
                let configured = icon.withSymbolConfiguration(.init(pointSize: 19, weight: .medium)) ?? icon
                let rect = CGRect(x: point.x - 11, y: point.y - 20, width: 22, height: 22)
                context.saveGState(); context.clip(to: rect, mask: configured.cgImage(forProposedRect: nil, context: nil, hints: nil)!)
                color.setFill(); rect.fill(); context.restoreGState()
                drawText(action.title, at: CGPoint(x: point.x, y: point.y + 14), font: .systemFont(ofSize: 10.5, weight: .bold), color: color, tracking: 0.7)
            } else {
                drawText(action.title, at: point, font: .systemFont(ofSize: actions.count == 4 ? 15 : 12.5, weight: .semibold), color: color)
            }
        }
        let pill = CGRect(x: center.x - 48, y: center.y - 23, width: 96, height: 46)
        NSColor(calibratedRed: 1, green: 0.92, blue: 0.78, alpha: 0.76).setFill()
        NSBezierPath(roundedRect: pill, xRadius: 23, yRadius: 23).fill()
        let title = selectedIndex.map { actions[$0].title } ?? fileSize
        drawText(title, at: center, font: .systemFont(ofSize: title.count > 8 ? 10 : 12, weight: .semibold), color: NSColor(calibratedRed: 0.20, green: 0.15, blue: 0.10, alpha: 1))
    }

    private func polar(_ radius: CGFloat, _ angle: CGFloat) -> CGPoint { CGPoint(x: center.x + cos(angle) * radius, y: center.y + sin(angle) * radius) }
    private func petal(start: CGFloat, end: CGFloat) -> CGPath {
        let path = CGMutablePath(), corner: CGFloat = 10
        let outer = wheelRadius, inner = innerRadius + 6
        let outerInset = corner / outer, innerInset = corner / inner
        path.move(to: polar(outer, start + outerInset))
        path.addArc(center: center, radius: outer, startAngle: start + outerInset, endAngle: end - outerInset, clockwise: false)
        path.addQuadCurve(to: polar(outer - corner, end), control: polar(outer, end))
        path.addLine(to: polar(inner + corner, end))
        path.addQuadCurve(to: polar(inner, end - innerInset), control: polar(inner, end))
        path.addArc(center: center, radius: inner, startAngle: end - innerInset, endAngle: start + innerInset, clockwise: true)
        path.addQuadCurve(to: polar(inner + corner, start), control: polar(inner, start))
        path.addLine(to: polar(outer - corner, start))
        path.addQuadCurve(to: polar(outer, start + outerInset), control: polar(outer, start))
        path.closeSubpath(); return path
    }
    private func drawText(_ text: String, at point: CGPoint, font: NSFont, color: NSColor, tracking: CGFloat = 0) {
        let string = NSAttributedString(string: text, attributes: [.font: font, .foregroundColor: color, .kern: tracking])
        let size = string.size()
        string.draw(at: CGPoint(x: point.x - size.width / 2, y: point.y - size.height / 2))
    }
}

final class WheelAccessibleButton: NSAccessibilityElement {
    var onPress: (() -> Void)?
    override func accessibilityPerformPress() -> Bool { onPress?(); return true }
}

func glassPanel(size: NSSize) -> FloatingPanel {
    let panel = FloatingPanel(contentRect: NSRect(origin: .zero, size: size), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
    panel.isOpaque = false; panel.backgroundColor = .clear; panel.hasShadow = true
    panel.level = .popUpMenu
    panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
    panel.isFloatingPanel = true; panel.hidesOnDeactivate = false
    return panel
}
