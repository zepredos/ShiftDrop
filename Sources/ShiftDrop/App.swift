import AppKit
import SwiftUI

@main
struct ShiftDropMain {
    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        app.run()
        withExtendedLifetime(delegate) {}
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var timer: Timer?
    private var wheelPanel: FloatingPanel?
    private var wheelView: WheelView?
    private var editorPanel: FloatingPanel?
    private var toastPanel: FloatingPanel?
    private var welcomePanel: FloatingPanel?
    private var dragMonitor: Any?
    private var localMonitor: Any?
    private var isDragging = false
    private var wasShiftDown = false
    private var idleDragChangeCount = NSPasteboard(name: .drag).changeCount
    private var activatedDragChangeCount: Int?
    private var showsTools = false
    private var manuallyOpened = false
    private var paused = false
    private var busy = false
    private var lastOutputs: [URL] = []
    private var toastID = UUID()

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = NSImage(systemSymbolName: "arrow.triangle.2.circlepath", accessibilityDescription: "ShiftDrop")
        statusItem.button?.toolTip = "ShiftDrop · Drag a file + Shift"
        let menu = NSMenu()
        menu.addItem(withTitle: "ShiftDrop", action: nil, keyEquivalent: "")
        menu.addItem(withTitle: "Choose File…", action: #selector(chooseFile), keyEquivalent: "o")
        menu.addItem(withTitle: "How to Use", action: #selector(showWelcome), keyEquivalent: "")
        menu.addItem(withTitle: "Reveal Last Result", action: #selector(revealLast), keyEquivalent: "r")
        menu.addItem(.separator())
        menu.addItem(withTitle: "Pause Drag + Shift", action: #selector(togglePause(_:)), keyEquivalent: "")
        menu.addItem(withTitle: "Quit ShiftDrop", action: #selector(quit), keyEquivalent: "q")
        for item in menu.items { item.target = self }
        statusItem.menu = menu
        let mainMenu = NSMenu()
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "About ShiftDrop", action: #selector(showWelcome), keyEquivalent: "")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Quit ShiftDrop", action: #selector(quit), keyEquivalent: "q")
        appMenu.items.forEach { $0.target = self }
        let appItem = NSMenuItem(); appItem.submenu = appMenu; mainMenu.addItem(appItem)
        let fileMenu = NSMenu(title: "File")
        fileMenu.addItem(withTitle: "Choose File…", action: #selector(chooseFile), keyEquivalent: "o").target = self
        let fileItem = NSMenuItem(); fileItem.submenu = fileMenu; mainMenu.addItem(fileItem)
        NSApp.mainMenu = mainMenu
        timer = Timer(timeInterval: 0.035, repeats: true) { [weak self] _ in self?.checkDrag() }
        RunLoop.main.add(timer!, forMode: .common)
        dragMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDragged, .flagsChanged, .leftMouseUp]) { [weak self] _ in self?.checkDrag() }
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { [weak self] event in
            guard let self, self.wheelPanel?.isVisible == true else { return event }
            if event.keyCode == 53 { self.hideWheel(); return nil }
            if event.keyCode == 48 { self.toggleWheel(); return nil }
            return event
        }
        let args = ProcessInfo.processInfo.arguments
        if let index = args.firstIndex(of: "--preview"), args.count > index + 1 {
            let url = URL(fileURLWithPath: args[index + 1])
            showWheel(files: [url], at: NSScreen.main.map { CGPoint(x: $0.visibleFrame.midX, y: $0.visibleFrame.midY) } ?? NSEvent.mouseLocation, manual: true)
        } else if !UserDefaults.standard.bool(forKey: "hasLaunched") {
            showWelcome(); UserDefaults.standard.set(true, forKey: "hasLaunched")
        }
    }

    func application(_ sender: NSApplication, openFiles filenames: [String]) {
        showWheel(files: filenames.map { URL(fileURLWithPath: $0) }, at: NSEvent.mouseLocation, manual: true)
        sender.reply(toOpenOrPrint: .success)
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag { showWelcome() }
        return true
    }

    private func checkDrag() {
        let down = NSEvent.pressedMouseButtons & 1 != 0
        let shift = NSEvent.modifierFlags.contains(.shift)
        let pasteboard = NSPasteboard(name: .drag)
        defer { wasShiftDown = shift }
        guard !paused, !busy, editorPanel?.isVisible != true else { return }
        if down {
            if shift {
                if !wasShiftDown && wheelPanel?.isVisible == true && !manuallyOpened { toggleWheel() }
                else if wheelPanel?.isVisible != true && pasteboard.changeCount != idleDragChangeCount && pasteboard.changeCount != activatedDragChangeCount {
                    let urls = WheelView.urls(from: pasteboard)
                    guard !urls.isEmpty else { return }
                    activatedDragChangeCount = pasteboard.changeCount
                    isDragging = true
                    showWheel(files: urls, at: NSEvent.mouseLocation, manual: false)
                }
            }
        } else {
            idleDragChangeCount = pasteboard.changeCount
            if isDragging {
                isDragging = false
                // Let AppKit deliver performDragOperation before dismissing the destination.
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
                    guard self?.isDragging == false, self?.manuallyOpened == false else { return }
                    self?.hideWheel()
                }
            }
        }
    }

    private func showWheel(files: [URL], at point: CGPoint, manual: Bool) {
        guard let first = files.first else { return }
        do { for file in files { _ = try FileKind.detect(file) } }
        catch { showError(error); return }
        manuallyOpened = manual; showsTools = false
        let size = NSSize(width: 380, height: 380)
        if wheelPanel == nil {
            let panel = glassPanel(size: size)
            panel.hasShadow = false
            let container = NSView(frame: NSRect(origin: .zero, size: size))
            let material = NSVisualEffectView(frame: NSRect(x: 21, y: 21, width: 338, height: 338))
            material.material = .hudWindow; material.blendingMode = .behindWindow; material.state = .active
            material.wantsLayer = true; material.layer?.cornerRadius = 169; material.layer?.masksToBounds = true
            material.appearance = NSAppearance(named: .aqua)
            container.addSubview(material)
            let view = WheelView(frame: container.bounds)
            view.onAction = { [weak self] action, files in self?.perform(action, on: files) }
            view.onToggle = { [weak self] in self?.toggleWheel() }
            view.onCancel = { [weak self] in self?.hideWheel() }
            container.addSubview(view); panel.contentView = container
            wheelPanel = panel; wheelView = view
        }
        wheelView?.files = files
        let bytes = files.reduce(Int64(0)) { total, file in total + ((try? file.resourceValues(forKeys: [.fileSizeKey]).fileSize).map(Int64.init) ?? 0) }
        wheelView?.fileSize = files.count > 1 ? "\(files.count) FILES" : ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
        configureActions(first)
        let screen = NSScreen.screens.first { $0.frame.contains(point) } ?? NSScreen.main
        let visible = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let origin = CGPoint(x: min(max(point.x - 190, visible.minX), visible.maxX - 380), y: min(max(point.y - 190, visible.minY), visible.maxY - 380))
        wheelPanel?.setFrameOrigin(origin)
        wheelView?.refreshAccessibility()
        if manual { NSApp.activate(ignoringOtherApps: true); wheelPanel?.makeKeyAndOrderFront(nil); wheelPanel?.makeFirstResponder(wheelView) }
        else { wheelPanel?.orderFrontRegardless() }
    }

    private func configureActions(_ file: URL) {
        guard let kind = try? FileKind.detect(file) else { return }
        if showsTools && kind == .image { wheelView?.actions = ImageTool.allCases.map(WheelAction.tool) }
        else { wheelView?.actions = OutputFormat.wheel(for: kind, sourceExtension: file.pathExtension).map(WheelAction.convert) }
    }
    private func toggleWheel() {
        guard let first = wheelView?.files.first, (try? FileKind.detect(first)) == .image else { return }
        showsTools.toggle(); configureActions(first)
        if let view = wheelView, let panel = wheelPanel {
            view.update(at: view.convert(panel.convertPoint(fromScreen: NSEvent.mouseLocation), from: nil))
        }
    }
    private func hideWheel() { wheelPanel?.orderOut(nil); manuallyOpened = false }

    private func perform(_ action: WheelAction, on files: [URL]) {
        hideWheel()
        guard !busy, let file = files.first else { return }
        switch action {
        case .convert(let format):
            runConversion(title: "Converting to \(format.rawValue)", subtitle: files.count == 1 ? file.lastPathComponent : "\(files.count) files") {
                var results: [URL] = []
                var failures: [String] = []
                for url in files {
                    do { results += try ConversionEngine.shared.convert(url, to: format) }
                    catch { failures.append("\(url.lastPathComponent): \(error.localizedDescription)") }
                }
                return (results, failures)
            }
        case .tool(let tool):
            if files.count > 1 { showError(ConversionError.message("Select one image at a time for editing.")); return }
            do {
                guard let image = try ConversionEngine.shared.loadImages(file).first else { return }
                showEditor(tool: tool, file: file, image: image)
            } catch { showError(error) }
        }
    }

    func runConversion(title: String, subtitle: String, work: @escaping () throws -> ([URL], [String])) {
        busy = true
        showToast(title: title, subtitle: subtitle, progress: true)
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let result = Result { try work() }
            DispatchQueue.main.async {
                guard let self else { return }; self.busy = false
                switch result {
                case .success(let (outputs, failures)):
                    self.lastOutputs = outputs
                    if !failures.isEmpty {
                        self.showError(ConversionError.message((outputs.isEmpty ? "" : "Saved \(outputs.count) file(s).\n\n") + failures.joined(separator: "\n")))
                    } else {
                        self.showToast(title: outputs.count == 1 ? "Saved \(outputs[0].lastPathComponent)" : "Saved \(outputs.count) files", subtitle: "Beside your original · Click to reveal", progress: false)
                    }
                case .failure(let error): self.showError(error)
                }
            }
        }
    }

    private func showEditor(tool: ImageTool, file: URL, image: CGImage) {
        editorPanel?.close()
        let panel = glassPanel(size: NSSize(width: 460, height: tool == .background ? 656 : 654))
        panel.level = .floating
        let view = EditorView(tool: tool, file: file, image: image, onClose: { [weak self] in self?.editorPanel?.close() }, onSave: { [weak self] image, suffix, format, quality in
            guard let self else { return }
            self.editorPanel?.close()
            self.runConversion(title: "Saving image", subtitle: file.lastPathComponent) {
                let data = try ConversionEngine.shared.encode(image, as: format, quality: quality)
                return ([try ConversionEngine.shared.save(data, beside: file, suffix: suffix, extension: format.fileExtension)], [])
            }
        })
        panel.contentView = NSHostingView(rootView: view)
        panel.appearance = NSAppearance(named: .aqua)
        panel.center(); panel.isMovableByWindowBackground = true
        NSApp.activate(ignoringOtherApps: true); panel.makeKeyAndOrderFront(nil)
        editorPanel = panel
    }

    private func showToast(title: String, subtitle: String, progress: Bool) {
        toastPanel?.close()
        let panel = glassPanel(size: NSSize(width: 330, height: 92))
        let id = UUID(); toastID = id
        panel.contentView = NSHostingView(rootView: ToastView(title: title, subtitle: subtitle, progress: progress, onClick: { [weak self] in self?.revealLast() }))
        panel.appearance = NSAppearance(named: .aqua)
        if let screen = NSScreen.screens.first(where: { $0.frame.contains(NSEvent.mouseLocation) }) ?? NSScreen.main {
            panel.setFrameOrigin(CGPoint(x: screen.visibleFrame.midX - 165, y: screen.visibleFrame.midY - 46))
        }
        panel.orderFrontRegardless(); toastPanel = panel
        if !progress { DispatchQueue.main.asyncAfter(deadline: .now() + 4) { [weak self] in if self?.toastID == id { self?.toastPanel?.close() } } }
    }
    private func showError(_ error: Error) {
        toastPanel?.close()
        let alert = NSAlert(); alert.messageText = "ShiftDrop"; alert.informativeText = error.localizedDescription
        alert.alertStyle = .warning; alert.addButton(withTitle: "OK")
        NSApp.activate(ignoringOtherApps: true); alert.runModal()
    }
    @objc private func chooseFile() {
        let picker = NSOpenPanel(); picker.canChooseDirectories = false; picker.allowsMultipleSelection = true
        picker.message = "Choose images, PDFs, or text documents"
        NSApp.activate(ignoringOtherApps: true)
        if picker.runModal() == .OK { showWheel(files: picker.urls, at: NSEvent.mouseLocation, manual: true) }
    }
    @objc private func revealLast() { if !lastOutputs.isEmpty { NSWorkspace.shared.activateFileViewerSelecting(lastOutputs) } }
    @objc private func togglePause(_ sender: NSMenuItem) { paused.toggle(); sender.state = paused ? .on : .off; if paused { hideWheel() } }
    @objc private func quit() { NSApp.terminate(nil) }
    @objc private func showWelcome() {
        welcomePanel?.close()
        let panel = glassPanel(size: NSSize(width: 430, height: 434))
        panel.contentView = NSHostingView(rootView: WelcomeView(onChoose: { [weak self] in self?.welcomePanel?.close(); self?.chooseFile() }, onClose: { [weak self] in self?.welcomePanel?.close() }))
        panel.appearance = NSAppearance(named: .aqua); panel.center()
        NSApp.activate(ignoringOtherApps: true); panel.makeKeyAndOrderFront(nil); welcomePanel = panel
    }
}
