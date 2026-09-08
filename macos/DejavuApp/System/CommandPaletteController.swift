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
    private let motion = PanelMotion()
    private unowned let app: AppEnvironment
    private var panel: PalettePanel?
    var isVisible: Bool { panel?.isVisible == true && !motion.isClosing }
    private var celebration: NSPanel?
    private var celebrationTask: Task<Void, Never>?
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
        if isVisible { hide() } else { show() }
    }

    func show() {
        if panel == nil { createPanel() }
        guard let panel else { return }
        let screen = NSScreen.screens.first { $0.frame.contains(NSEvent.mouseLocation) } ?? NSScreen.main
        if let screen {
            panel.setFrame(PalettePlacement.frame(in: screen.visibleFrame,
                                                  preferredHeight: app.commandPaletteModel.preferredHeight), display: false)
        }
        motion.show(panel, takesFocus: true)
        app.commandPaletteModel.prepareToShow()
        showCelebration(around: panel)
    }

    func hide() {
        guard !hiding else { return }
        hiding = true
        clearCelebration()
        app.commandPaletteModel.cancel()
        motion.hide(panel)
        hiding = false
    }

    func windowDidResignKey(_ notification: Notification) { hide() }

    private func resize() {
        guard let panel, panel.isVisible, let screen = panel.screen ?? NSScreen.main else { return }
        let frame = PalettePlacement.frame(in: screen.visibleFrame,
                                           preferredHeight: app.commandPaletteModel.preferredHeight,
                                           top: panel.frame.maxY)
        panel.setFrame(frame, display: true)
        celebration?.setFrame(frame.insetBy(dx: -52, dy: -52), display: true)
    }

    private func clearCelebration() {
        celebrationTask?.cancel()
        celebrationTask = nil
        if let celebration { panel?.removeChildWindow(celebration); celebration.orderOut(nil) }
        celebration = nil
    }

    private func showCelebration(around panel: NSPanel) {
        clearCelebration()
        guard app.settings.playfulDetails,
              !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else { return }
        let decoration = NSPanel(contentRect: panel.frame.insetBy(dx: -52, dy: -52),
                                 styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        decoration.isReleasedWhenClosed = false
        decoration.isOpaque = false
        decoration.backgroundColor = .clear
        decoration.hasShadow = false
        decoration.ignoresMouseEvents = true
        decoration.animationBehavior = .none
        decoration.contentView = NSHostingView(rootView: PaletteEmojiBurst())
        celebration = decoration
        panel.addChildWindow(decoration, ordered: .above)
        decoration.orderFront(nil)
        celebrationTask = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(2.6)) } catch { return }
            self?.clearCelebration()
        }
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
                .modifier(DejavuAppearance()).environment(app)
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

// A separate click-through child panel lets the burst extend outside the input window.
private struct PaletteEmojiBurst: View {
    private let stickers = ["💗", "✨", "🌷", "💕", "🫧", "⭐️", "💖", "🎀"]
    var body: some View {
        GeometryReader { geometry in
            ForEach(stickers.indices, id: \.self) { index in
                BurstSticker(emoji: stickers[index], index: index)
                    .position(position(index, in: geometry.size))
            }
        }.accessibilityHidden(true).allowsHitTesting(false)
    }
    private func position(_ index: Int, in size: CGSize) -> CGPoint {
        let points: [CGPoint] = [.init(x: 0, y: -1), .init(x: 1, y: -1), .init(x: 1, y: 0),
                                 .init(x: 1, y: 1), .init(x: 0, y: 1), .init(x: -1, y: 1),
                                 .init(x: -1, y: 0), .init(x: -1, y: -1)]
        let point = points[index]
        return CGPoint(x: size.width / 2 + point.x * (size.width / 2 - 26),
                       y: size.height / 2 + point.y * (size.height / 2 - 26))
    }
}

private struct BurstSticker: View {
    let emoji: String
    let index: Int
    @State private var shown = false
    @State private var leaving = false
    var body: some View {
        Text(emoji).font(.system(size: 30))
            .scaleEffect(shown ? (leaving ? 0.65 : 1) : 0.05)
            .rotationEffect(.degrees(shown ? (index.isMultiple(of: 2) ? -12 : 12) : -35))
            .offset(y: leaving ? -14 : 0)
            .opacity(shown && !leaving ? 1 : 0)
            .task {
                do {
                    try await Task.sleep(for: .milliseconds(index * 85))
                    withAnimation(.spring(duration: 0.42, bounce: 0.48)) { shown = true }
                    try await Task.sleep(for: .milliseconds(1450))
                    withAnimation(.easeOut(duration: 0.35)) { leaving = true }
                } catch { return }
            }
    }
}
