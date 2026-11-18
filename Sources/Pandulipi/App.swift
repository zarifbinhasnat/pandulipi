import AppKit
import SwiftUI

@main
struct PandulipiApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @StateObject private var model = AppModel.shared
    @StateObject private var monitor = SystemMonitor()

    var body: some Scene {
        Window("Pandulipi", id: "main") {
            ContentView()
                .environmentObject(model)
                .environmentObject(monitor)
                .frame(minWidth: 1080, minHeight: 680)
        }
        .defaultSize(width: 1380, height: 860)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("Open PDF or Images…") { model.presentOpenPanel() }
                    .keyboardShortcut("o")
            }
            CommandMenu("Book") {
                Button("Compare Random Page") { model.compareRandomPage() }
                    .keyboardShortcut("r")
                    .disabled(model.document == nil)
                Button(model.jobRunning ? "Stop Transcription" : "Start Transcription") {
                    model.jobRunning ? model.stopJob() : model.startJob()
                }
                .keyboardShortcut(.return, modifiers: .command)
                .disabled(model.document == nil)
                Divider()
                Button("Export EPUB…") { model.exportEPUB() }
                    .keyboardShortcut("e")
                    .disabled(model.results.isEmpty)
                Button("Export Text…") { model.exportText() }
                    .keyboardShortcut("e", modifiers: [.command, .shift])
                    .disabled(model.results.isEmpty)
            }
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        Task { @MainActor in AppModel.shared.open(urls: urls) }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}
