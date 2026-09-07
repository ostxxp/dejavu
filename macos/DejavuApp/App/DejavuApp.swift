import AppKit
import SwiftUI

@main struct DejavuApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @State private var bootstrap = AppBootstrap()

    var body: some Scene {
        Window("DéjàVu", id: "main") {
            if let environment = bootstrap.environment {
                RootView()
                    .environment(environment)
                    .modelContainer(environment.container)
                    .environment(\.locale, Locale(identifier: "ru_RU"))
            } else {
                ContentUnavailableView {
                    Label("Не удалось открыть данные", systemImage: "externaldrive.badge.exclamationmark")
                } description: {
                    Text("Проверьте свободное место и права доступа. Ваши данные не будут сброшены.")
                } actions: {
                    Button("Повторить") { bootstrap.start() }
                }
                .frame(width: 620, height: 380)
            }
        }
        .defaultSize(width: 980, height: 740)
        .commands { AppCommands() }

        Window("Настройки", id: "settings") {
            if let environment = bootstrap.environment {
                SettingsView()
                    .modifier(DejavuAppearance())
                    .environment(environment)
                    .environment(\.locale, Locale(identifier: "ru_RU"))
                    .frame(minWidth: 560, minHeight: 600)
            }
        }
        .defaultSize(width: 640, height: 740)

        MenuBarExtra("DéjàVu", systemImage: "text.bubble") {
            MenuBarContent(bootstrap: bootstrap)
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Local build paths can retain Launch Services' previous generic icon.
        if let url = Bundle.main.url(forResource: "AppIcon", withExtension: "icns"),
           let icon = NSImage(contentsOf: url) {
            NSApp.applicationIconImage = icon
        }
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
}

private struct AppCommands: Commands {
    @Environment(\.openWindow) private var openWindow
    var body: some Commands {
        CommandGroup(replacing: .appInfo) {
            Button("О приложении DéjàVu") { NSApp.orderFrontStandardAboutPanel() }
        }
        CommandGroup(replacing: .appSettings) {
            Button("Настройки…") {
                openWindow(id: "settings")
                NSApp.activate(ignoringOtherApps: true)
            }.keyboardShortcut(",")
        }
        CommandGroup(replacing: .appTermination) {
            Button("Выход из DéjàVu") { NSApp.terminate(nil) }.keyboardShortcut("q")
        }
    }
}

private struct MenuBarContent: View {
    let bootstrap: AppBootstrap
    @Environment(\.openWindow) private var openWindow
    var body: some View {
        Button("Открыть DéjàVu") { show(.home) }
        Button("Быстрый помощник") { bootstrap.environment?.commandPalette.show() }
        if let app = bootstrap.environment {
            Toggle("Разбор скопированного", isOn: Binding(
                get: { app.settings.clipboardEnabled },
                set: { value in
                    do { try app.setClipboard(enabled: value) }
                    catch { show(.settings) }
                }))
            Button("Последний разбор скопированного") { app.clipboardPanel.show() }
                .disabled(!app.clipboardModel.hasContent)
        }
        Button("Сохранённое") { show(.saved) }
        Button("История") { show(.history) }
        Divider()
        Button("Настройки…") {
            openWindow(id: "settings")
            NSApp.activate(ignoringOtherApps: true)
        }
        Divider()
        if let app = bootstrap.environment {
            Button("Мини-диалог сейчас") { app.dialogueController.triggerNow() }
            Button("Мини-диалоги: пауза на час") { app.dialogueController.pause(until: .now.addingTimeInterval(3600)) }
        }
        Button("Выход") { NSApp.terminate(nil) }
    }

    private func show(_ section: AppSection) {
        bootstrap.environment?.section = section
        openWindow(id: "main")
        NSApp.activate(ignoringOtherApps: true)
    }
}
