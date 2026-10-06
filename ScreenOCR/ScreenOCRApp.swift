import SwiftUI
import ServiceManagement
import Combine

@main
struct ScreenOCRApp: App {
    @StateObject private var controller = AppController()

    var body: some Scene {
        // No Dock icon: the app lives in the menu bar
        MenuBarExtra {
            MenuContent(controller: controller)
        } label: {
            Image(systemName: "text.viewfinder")
        }
    }
}

struct MenuContent: View {
    @ObservedObject var controller: AppController
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled

    var body: some View {
        Button("Capture text") {
            // Give the menu a moment to close before the selection overlay appears
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { controller.startCapture() }
        }
        .keyboardShortcut("s", modifiers: .option)

        Divider()

        Menu("Recent copies") {
            if controller.history.isEmpty {
                Text("Nothing copied yet")
            } else {
                ForEach(Array(controller.history.enumerated()), id: \.offset) { index, item in
                    Button("\(index + 1).  \(item.preview(48))") { controller.recopy(item) }
                }
                Divider()
                Button("Clear history") { controller.clearHistory() }
            }
        }

        Divider()

        Toggle("Launch at login", isOn: $launchAtLogin)
            .onChange(of: launchAtLogin) { newValue in
                do {
                    if newValue {
                        try SMAppService.mainApp.register()
                    } else {
                        try SMAppService.mainApp.unregister()
                    }
                } catch {
                    launchAtLogin = SMAppService.mainApp.status == .enabled
                }
            }

        Divider()

        Button("Quit") { NSApp.terminate(nil) }
            .keyboardShortcut("q")
    }
}

extension String {
    /// One-line preview for menus and lists
    func preview(_ limit: Int) -> String {
        let flat = replacingOccurrences(of: "\n", with: " ").trimmingCharacters(in: .whitespacesAndNewlines)
        return flat.count > limit ? String(flat.prefix(limit)) + "…" : flat
    }
}
