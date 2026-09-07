import AppKit
import SwiftUI

@MainActor final class ClipboardPanelController {
    private let motion = PanelMotion()
    private unowned let app: AppEnvironment
    private var panel: ClipboardPanel?
    private var dismissal: Task<Void, Never>?
    private var hovering = false
    private let resultLifetime: Duration
    private let candidateLifetime: Duration

    init(app: AppEnvironment, resultLifetime: Duration = .seconds(20), candidateLifetime: Duration = .seconds(60)) {
        self.app = app
        self.resultLifetime = resultLifetime
        self.candidateLifetime = candidateLifetime
    }

    func update() {
        guard app.clipboardModel.hasContent else {
            dismissal?.cancel()
            motion.hide(panel)
            hovering = false
            return
        }
        if app.settings.clipboardShowPanel { show() }
        scheduleDismissal()
    }

    func show() {
        guard app.clipboardModel.hasContent else { return }
        if panel == nil {
            let panel = ClipboardPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
            panel.title = "Разбор скопированного — DéjàVu"
            panel.identifier = NSUserInterfaceItemIdentifier("clipboard-result")
            panel.level = .floating
            panel.isReleasedWhenClosed = false
            panel.hidesOnDeactivate = false
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            panel.isOpaque = false
            panel.backgroundColor = .clear
            panel.hasShadow = true
            panel.onClose = { [weak self] in self?.app.clipboardModel.clear() }
            panel.contentView = NSHostingView(rootView: ClipboardResultView(
                onClose: { [weak self] in self?.app.clipboardModel.clear() },
                onHover: { [weak self] value in self?.setHovering(value) },
                onResize: { [weak self] in self?.position() })
                .modifier(DejavuAppearance()).environment(app).modelContainer(app.container)
                .environment(\.locale, Locale(identifier: "ru_RU")))
            self.panel = panel
        }
        position()
        // Do not activate the app or take keyboard focus from the foreground app.
        if let panel { motion.show(panel, takesFocus: false) }
        scheduleDismissal()
    }

    private func position() {
        guard let screen = panel?.screen ?? NSScreen.screens.first(where: { $0.frame.contains(NSEvent.mouseLocation) }) ?? NSScreen.main else { return }
        var frame = PalettePlacement.frame(in: screen.visibleFrame,
                                            preferredHeight: app.clipboardModel.result == nil ? 300 : (app.clipboardModel.showsDetails ? 700 : 570))
        frame.size.width = min(frame.width, 560)
        frame.origin.x = screen.visibleFrame.maxX - frame.width - 16
        panel?.setFrame(frame, display: true)
    }

    func setHovering(_ value: Bool) {
        hovering = value
        scheduleDismissal()
    }

    private func scheduleDismissal() {
        dismissal?.cancel()
        guard !hovering, !app.clipboardModel.isLoading else { return }
        let lifetime = app.clipboardModel.result == nil ? candidateLifetime : resultLifetime
        dismissal = Task { [weak self] in
            do { try await Task.sleep(for: lifetime) } catch { return }
            self?.app.clipboardModel.clear()
        }
    }
}

private final class ClipboardPanel: NSPanel {
    var onClose: (() -> Void)?
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
    override func cancelOperation(_ sender: Any?) { onClose?() }
}
