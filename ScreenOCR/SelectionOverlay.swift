import AppKit

/// The area you selected, in the coordinates each part of the app needs
struct ScreenSelection {
    let displayID: CGDirectDisplayID
    let rectInDisplay: CGRect   // points, top-left origin, relative to that display (for capture)
    let cocoaRect: NSRect       // global AppKit coordinates (for placing the result panel)
    let scale: CGFloat          // pixels per point (2 on Retina)
}

/// Dims every screen and lets you drag a rectangle. Esc or a plain click cancels.
@MainActor
final class SelectionOverlay {
    private var windows: [NSWindow] = []
    private var completion: (@MainActor (ScreenSelection?) -> Void)?

    func begin(completion: @escaping @MainActor (ScreenSelection?) -> Void) {
        self.completion = completion
        NSApp.activate(ignoringOtherApps: true)

        for screen in NSScreen.screens {
            let window = OverlayWindow(screen: screen)
            let view = SelectionView(frame: NSRect(origin: .zero, size: screen.frame.size))
            view.onFinish = { [weak self] rect in self?.finish(rect, on: screen) }
            view.onCancel = { [weak self] in self?.finish(nil, on: screen) }
            window.contentView = view
            window.orderFrontRegardless()
            windows.append(window)
        }

        // The screen under the mouse gets keyboard focus, so Esc works right away
        let mouse = NSEvent.mouseLocation
        if let window = windows.first(where: { NSMouseInRect(mouse, $0.frame, false) }) ?? windows.first {
            window.makeKey()
            window.makeFirstResponder(window.contentView)
        }
    }

    private func finish(_ rect: NSRect?, on screen: NSScreen) {
        windows.forEach { $0.orderOut(nil) }
        windows.removeAll()
        let done = completion
        completion = nil

        guard let rect, rect.width >= 4, rect.height >= 4, let displayID = screen.displayID else {
            done?(nil)
            return
        }
        let local = CGRect(x: rect.minX, y: screen.frame.height - rect.maxY,
                           width: rect.width, height: rect.height)
        let global = rect.offsetBy(dx: screen.frame.minX, dy: screen.frame.minY)
        done?(ScreenSelection(displayID: displayID, rectInDisplay: local,
                              cocoaRect: global, scale: screen.backingScaleFactor))
    }
}

// MARK: - Window

final class OverlayWindow: NSWindow {
    init(screen: NSScreen) {
        super.init(contentRect: screen.frame, styleMask: .borderless, backing: .buffered, defer: false)
        setFrame(screen.frame, display: false)
        level = .screenSaver
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        isReleasedWhenClosed = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
    }

    override var canBecomeKey: Bool { true }
}

// MARK: - Drawing and mouse handling

final class SelectionView: NSView {
    var onFinish: (@MainActor (NSRect) -> Void)?
    var onCancel: (@MainActor () -> Void)?

    private var start: NSPoint?
    private var selection: NSRect?

    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func resetCursorRects() { addCursorRect(bounds, cursor: .crosshair) }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.black.withAlphaComponent(0.3).setFill()
        bounds.fill()

        guard let rect = selection else {
            drawHint()
            return
        }
        // Cut a clear hole where you're selecting, then outline it
        NSColor.clear.setFill()
        rect.fill(using: .copy)
        let outline = NSBezierPath(rect: rect.insetBy(dx: -1, dy: -1))
        outline.lineWidth = 2
        NSColor.white.setStroke()
        outline.stroke()
    }

    private func drawHint() {
        let text = "Drag over the text you want to copy.  Esc to cancel."
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 18, weight: .medium),
            .foregroundColor: NSColor.white
        ]
        let size = text.size(withAttributes: attributes)
        let origin = NSPoint(x: (bounds.width - size.width) / 2, y: bounds.height - size.height - 80)
        let pill = NSRect(x: origin.x - 18, y: origin.y - 10, width: size.width + 36, height: size.height + 20)
        NSColor.black.withAlphaComponent(0.55).setFill()
        NSBezierPath(roundedRect: pill, xRadius: pill.height / 2, yRadius: pill.height / 2).fill()
        text.draw(at: origin, withAttributes: attributes)
    }

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        start = point
        selection = NSRect(origin: point, size: .zero)
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        guard let start else { return }
        let point = convert(event.locationInWindow, from: nil)
        selection = NSRect(x: min(start.x, point.x), y: min(start.y, point.y),
                           width: abs(point.x - start.x), height: abs(point.y - start.y))
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        if let rect = selection, rect.width > 3, rect.height > 3 {
            onFinish?(rect)
        } else {
            onCancel?()
        }
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 {   // Esc
            onCancel?()
        } else {
            super.keyDown(with: event)
        }
    }
}

extension NSScreen {
    var displayID: CGDirectDisplayID? {
        (deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value
    }
}
