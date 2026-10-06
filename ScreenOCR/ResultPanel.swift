import AppKit
import SwiftUI
import Translation
import Combine

/// What the floating panel is showing right now
@MainActor
final class ResultModel: ObservableObject {
    @Published var title = ""
    @Published var detail = ""
    @Published var copiedText = ""
    @Published var success = true
    @Published var canTranslate = false
    @Published var qrURL: URL?
    @Published var alternativeText: String?

    var hovering = false
    var pinned = false          // set when you open Translate or History, so the panel stays
    var onClose: (@MainActor () -> Void)?
}

/// A small card near your selection: "Copied 42 words" + Translate / History / QR actions.
/// It hides by itself after a few seconds unless you hover over it or use it.
@MainActor
final class ResultPanel {
    private let model = ResultModel()
    private unowned let controller: AppController
    private var panel: NSPanel?
    private var hideTask: Task<Void, Never>?

    init(controller: AppController) {
        self.controller = controller
        model.onClose = { [weak self] in self?.hide() }
    }

    func show(title: String,
              detail: String,
              copiedText: String = "",
              success: Bool = true,
              canTranslate: Bool = false,
              qrURL: URL? = nil,
              alternativeText: String? = nil,
              near anchor: NSRect) {
        model.title = title
        model.detail = detail
        model.copiedText = copiedText
        model.success = success
        model.canTranslate = canTranslate && !copiedText.isEmpty
        model.qrURL = qrURL
        model.alternativeText = alternativeText
        model.pinned = false

        let panel = self.panel ?? makePanel()
        self.panel = panel
        place(panel, near: anchor)
        panel.orderFrontRegardless()

        // SwiftUI may finish laying out on the next run loop pass, so fit once more
        DispatchQueue.main.async { [weak self] in
            guard let self, let panel = self.panel else { return }
            self.place(panel, near: anchor)
        }
        scheduleHide()
    }

    func hide() {
        hideTask?.cancel()
        panel?.orderOut(nil)
    }

    // MARK: - Helpers

    private func makePanel() -> NSPanel {
        let panel = KeyablePanel(contentRect: NSRect(x: 0, y: 0, width: 340, height: 140),
                                 styleMask: [.borderless, .nonactivatingPanel],
                                 backing: .buffered, defer: false)
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.contentView = NSHostingView(rootView: ResultView(model: model, controller: controller))
        return panel
    }

    /// Below the selection's bottom-right corner, kept inside the visible screen area
    private func place(_ panel: NSPanel, near anchor: NSRect) {
        guard let host = panel.contentView else { return }
        host.layoutSubtreeIfNeeded()
        let size = host.fittingSize
        panel.setContentSize(size)

        let center = NSPoint(x: anchor.midX, y: anchor.midY)
        let visible = (NSScreen.screens.first { NSMouseInRect(center, $0.frame, false) } ?? NSScreen.main)?
            .visibleFrame ?? .zero

        var origin = NSPoint(x: anchor.maxX - size.width, y: anchor.minY - size.height - 12)
        if origin.y < visible.minY { origin.y = anchor.maxY + 12 }               // no room below → go above
        origin.x = min(max(origin.x, visible.minX + 8), visible.maxX - size.width - 8)
        origin.y = min(max(origin.y, visible.minY + 8), visible.maxY - size.height - 8)
        panel.setFrameOrigin(origin)
    }

    private func scheduleHide(after seconds: Double = 6) {
        hideTask?.cancel()
        hideTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            guard let self, !Task.isCancelled else { return }
            if self.model.hovering || self.model.pinned {
                self.scheduleHide(after: 2)
            } else {
                self.hide()
            }
        }
    }
}

final class KeyablePanel: NSPanel {
    override var canBecomeKey: Bool { true }
}

// MARK: - SwiftUI card

struct ResultView: View {
    @ObservedObject var model: ResultModel
    @ObservedObject var controller: AppController
    @State private var showTranslation = false
    @State private var showHistory = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: model.success ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                    .foregroundStyle(model.success ? Color.green : Color.orange)
                Text(model.title).font(.headline)
                Spacer()
                Button { model.onClose?() } label: {
                    Image(systemName: "xmark").font(.caption.weight(.bold))
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
            }

            if !model.detail.isEmpty {
                Text(model.detail)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            HStack(spacing: 8) {
                if model.canTranslate {
                    Button {
                        model.pinned = true
                        showTranslation = true
                    } label: {
                        Label("Translate", systemImage: "translate")
                    }
                    .translationPresentation(isPresented: $showTranslation, text: model.copiedText) { translated in
                        controller.recopy(translated, title: "Translation copied")
                    }
                }

                Button {
                    model.pinned = true
                    showHistory.toggle()
                } label: {
                    Label("History", systemImage: "clock.arrow.circlepath")
                }
                .popover(isPresented: $showHistory, arrowEdge: .bottom) {
                    HistoryList(controller: controller) { showHistory = false }
                }

                if let url = model.qrURL {
                    Button {
                        NSWorkspace.shared.open(url)
                    } label: {
                        Label("Open link", systemImage: "safari")
                    }
                }

                if let text = model.alternativeText {
                    Button("Copy text instead") { controller.recopy(text) }
                }
            }
            .controlSize(.small)
        }
        .padding(14)
        .frame(width: 340)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
        .onHover { model.hovering = $0 }
    }
}

/// The last 10 copies. Click one to copy it again.
struct HistoryList: View {
    @ObservedObject var controller: AppController
    var onPick: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Recent copies")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.bottom, 4)

            if controller.history.isEmpty {
                Text("Nothing copied yet").foregroundStyle(.secondary)
            }

            ForEach(Array(controller.history.enumerated()), id: \.offset) { index, item in
                Button {
                    controller.recopy(item)
                    onPick()
                } label: {
                    HStack(spacing: 8) {
                        Text("\(index + 1)")
                            .foregroundStyle(.secondary)
                            .frame(width: 18, alignment: .trailing)
                        Text(item.preview(60)).lineLimit(1)
                        Spacer(minLength: 0)
                    }
                    .padding(.vertical, 5)
                    .padding(.horizontal, 6)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(10)
        .frame(width: 320)
    }
}
