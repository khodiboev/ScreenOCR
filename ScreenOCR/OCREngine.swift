import AppKit
import ScreenCaptureKit
import Vision

struct OCRResult {
    let text: String
    let qrPayload: String?

    var wordCount: Int { text.split(whereSeparator: { $0.isWhitespace }).count }
}

enum OCRError: LocalizedError {
    case displayNotFound

    var errorDescription: String? {
        switch self {
        case .displayNotFound: return "The selected screen is no longer available."
        }
    }
}

enum OCREngine {

    // MARK: - Permission

    static func hasScreenAccess() -> Bool { CGPreflightScreenCaptureAccess() }

    static func requestScreenAccess() { CGRequestScreenCaptureAccess() }

    // MARK: - Capture

    /// Takes a picture of just the selected area. Our own windows are left out of the shot.
    static func capture(_ selection: ScreenSelection) async throws -> CGImage {
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        guard let display = content.displays.first(where: { $0.displayID == selection.displayID }) else {
            throw OCRError.displayNotFound
        }
        let ownApp = content.applications.filter { $0.bundleIdentifier == Bundle.main.bundleIdentifier }
        let filter = SCContentFilter(display: display, excludingApplications: ownApp, exceptingWindows: [])

        let config = SCStreamConfiguration()
        config.sourceRect = selection.rectInDisplay
        config.width = max(1, Int(selection.rectInDisplay.width * selection.scale))
        config.height = max(1, Int(selection.rectInDisplay.height * selection.scale))
        config.showsCursor = false

        return try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
    }

    // MARK: - Recognition (runs off the main thread)

    nonisolated static func recognize(_ image: CGImage) async -> OCRResult {
        await Task.detached(priority: .userInitiated) {
            recognizeNow(image)
        }.value
    }

    nonisolated private static func recognizeNow(_ image: CGImage) -> OCRResult {
        let textRequest = VNRecognizeTextRequest()
        textRequest.recognitionLevel = .accurate
        textRequest.usesLanguageCorrection = true
        textRequest.recognitionLanguages = ["ko-KR", "en-US", "ru-RU"]
        textRequest.automaticallyDetectsLanguage = true

        let qrRequest = VNDetectBarcodesRequest()
        qrRequest.symbologies = [.qr]

        let handler = VNImageRequestHandler(cgImage: image, options: [:])
        try? handler.perform([textRequest, qrRequest])

        let text = readingOrder(textRequest.results ?? [])
        let qr = qrRequest.results?.compactMap { $0.payloadStringValue }.first
        return OCRResult(text: text, qrPayload: qr)
    }

    /// Puts recognized pieces back into lines, top to bottom and left to right
    nonisolated private static func readingOrder(_ observations: [VNRecognizedTextObservation]) -> String {
        let items: [(box: CGRect, text: String)] = observations.compactMap { observation in
            guard let best = observation.topCandidates(1).first?.string else { return nil }
            return (observation.boundingBox, best)
        }

        // Vision uses a bottom-left origin, so a higher midY means higher on the screen
        let sorted = items.sorted { $0.box.midY > $1.box.midY }
        var lines: [[(box: CGRect, text: String)]] = []
        for item in sorted {
            if let last = lines.last?.last,
               abs(last.box.midY - item.box.midY) < min(last.box.height, item.box.height) * 0.5 {
                lines[lines.count - 1].append(item)
            } else {
                lines.append([item])
            }
        }

        return lines
            .map { line in line.sorted { $0.box.minX < $1.box.minX }.map { $0.text }.joined(separator: " ") }
            .joined(separator: "\n")
    }
}
