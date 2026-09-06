import AppKit
import Carbon
import SwiftUI

enum PalettePlacement {
    static func frame(in visibleFrame: NSRect, preferredHeight: CGFloat, top: CGFloat? = nil) -> NSRect {
        let margin: CGFloat = 16
        let width = min(640, max(1, visibleFrame.width - margin * 2))
        let height = min(preferredHeight, max(1, visibleFrame.height - margin * 2))
        let upper = min(top ?? visibleFrame.maxY - visibleFrame.height * 0.18, visibleFrame.maxY - margin)
        let y = max(visibleFrame.minY + margin, upper - height)
        return NSRect(x: visibleFrame.midX - width / 2, y: y, width: width, height: height)
    }
}

@MainActor final class CommandPaletteController: NSObject, NSWindowDelegate {
    let shortcut = GlobalShortcut()
    private unowned let app: AppEnvironment
    private var panel: PalettePanel?
    private var started = false
    private var hiding = false

    init(app: AppEnvironment) { self.app = app }

    func start() {
        guard !started else { return }
        started = true
        retryShortcut()
    }

    func retryShortcut() {
        shortcut.register { [weak self] in self?.toggle() }
    }

    func toggle() {
        if panel?.isVisible == true { hide() } else { show() }
    }

    func show() {
        if panel == nil { createPanel() }
        guard let panel else { return }
        let screen = NSScreen.screens.first { $0.frame.contains(NSEvent.mouseLocation) } ?? NSScreen.main
        if let screen {
            panel.setFrame(PalettePlacement.frame(in: screen.visibleFrame,
                                                  preferredHeight: app.commandPaletteModel.preferredHeight), display: false)
        }
        panel.makeKeyAndOrderFront(nil)
        app.commandPaletteModel.prepareToShow()
    }

    func hide() {
        guard !hiding else { return }
        hiding = true
        app.commandPaletteModel.cancel()
        panel?.orderOut(nil)
        hiding = false
    }

    func windowDidResignKey(_ notification: Notification) { hide() }

    private func resize() {
        guard let panel, panel.isVisible, let screen = panel.screen ?? NSScreen.main else { return }
        let frame = PalettePlacement.frame(in: screen.visibleFrame,
                                           preferredHeight: app.commandPaletteModel.preferredHeight,
                                           top: panel.frame.maxY)
        panel.setFrame(frame, display: true)
    }

    private func createPanel() {
        let panel = PalettePanel(contentRect: NSRect(x: 0, y: 0, width: 640, height: 235),
                                 styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.title = "Быстрый помощник — DéjàVu"
        panel.identifier = NSUserInterfaceItemIdentifier("command-palette")
        panel.isReleasedWhenClosed = false
        panel.level = .floating
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.animationBehavior = .none
        panel.delegate = self
        panel.onClose = { [weak self] in self?.hide() }
        panel.onCommand = { [weak self] keyCode in
            guard let self else { return false }
            switch Int(keyCode) {
            case kVK_ANSI_S: self.app.commandPaletteModel.save()
            case kVK_ANSI_L: self.app.commandPaletteModel.listen()
            case kVK_ANSI_K: self.app.commandPaletteModel.clear()
            default: return false
            }
            return true
        }
        panel.contentView = NSHostingView(rootView:
            CommandPaletteView(onClose: { [weak self] in self?.hide() },
                               onResize: { [weak self] in self?.resize() })
                .environment(app)
                .modelContainer(app.container)
                .environment(\.locale, Locale(identifier: "ru_RU")))
        self.panel = panel
    }
}

private final class PalettePanel: NSPanel {
    var onClose: (() -> Void)?
    var onCommand: ((UInt16) -> Bool)?
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    override func cancelOperation(_ sender: Any?) { onClose?() }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        let modifiers = event.modifierFlags.intersection([.command, .shift, .option, .control])
        if modifiers == .command, onCommand?(event.keyCode) == true { return true }
        return super.performKeyEquivalent(with: event)
    }
}
