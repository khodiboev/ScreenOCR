import AppKit
import Combine

@MainActor
final class AppController: ObservableObject {

    /// The last 10 copies, newest first
    @Published private(set) var history: [String] = UserDefaults.standard.stringArray(forKey: "history") ?? []

    private let maxHistory = 10
    private var hotKey: HotKey?
    private let overlay = SelectionOverlay()
    private lazy var panel = ResultPanel(controller: self)
    private var busy = false

    init() {
        // ⌥S (Option + S) starts a capture from anywhere
        hotKey = HotKey(keyCode: HotKey.defaultKeyCode, modifiers: HotKey.defaultModifiers) { [weak self] in
            self?.startCapture()
        }
    }

    // MARK: - Capture flow

    func startCapture() {
        guard !busy else { return }

        guard OCREngine.hasScreenAccess() else {
            OCREngine.requestScreenAccess()
            panel.show(
                title: "Allow screen access",
                detail: "System Settings → Privacy & Security → Screen & System Audio Recording → turn on ScreenOCR, then quit and reopen the app.",
                success: false,
                near: Self.mouseAnchor())
            return
        }

        busy = true
        panel.hide()
        overlay.begin { [weak self] selection in
            guard let self else { return }
            guard let selection else { self.busy = false; return }
            Task { await self.process(selection) }
        }
    }

    private func process(_ selection: ScreenSelection) async {
        defer { busy = false }

        let image: CGImage
        do {
            image = try await OCREngine.capture(selection)
        } catch {
            panel.show(title: "Couldn't capture the screen", detail: error.localizedDescription,
                       success: false, near: selection.cocoaRect)
            return
        }

        let result = await OCREngine.recognize(image)

        if let qr = result.qrPayload {
            // A QR code is usually what you meant to grab, so its content is copied first
            copy(qr)
            remember(qr)
            let url = URL(string: qr).flatMap { ($0.scheme ?? "").hasPrefix("http") ? $0 : nil }
            panel.show(title: "QR code copied", detail: qr, copiedText: qr,
                       qrURL: url, alternativeText: result.text.isEmpty ? nil : result.text,
                       near: selection.cocoaRect)
        } else if !result.text.isEmpty {
            copy(result.text)
            remember(result.text)
            let words = result.wordCount
            panel.show(title: "Copied \(words) \(words == 1 ? "word" : "words")", detail: result.text,
                       copiedText: result.text, canTranslate: true, near: selection.cocoaRect)
        } else {
            panel.show(title: "No text found", detail: "Try selecting a larger or sharper area.",
                       success: false, near: selection.cocoaRect)
        }
    }

    // MARK: - Clipboard and history

    /// Copies an item again (from history, a translation, or the "Copy text" button)
    func recopy(_ text: String, title: String = "Copied again") {
        copy(text)
        remember(text)
        panel.show(title: title, detail: text, copiedText: text, canTranslate: true, near: Self.mouseAnchor())
    }

    func clearHistory() {
        history.removeAll()
        UserDefaults.standard.set(history, forKey: "history")
    }

    private func copy(_ text: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }

    private func remember(_ text: String) {
        history.removeAll { $0 == text }      // no duplicates: a repeated copy moves to the top
        history.insert(text, at: 0)
        if history.count > maxHistory { history.removeLast(history.count - maxHistory) }
        UserDefaults.standard.set(history, forKey: "history")
    }

    private static func mouseAnchor() -> NSRect {
        NSRect(origin: NSEvent.mouseLocation, size: .zero)
    }
}
