import AppKit
import SwiftUI
import CoreGraphics

@MainActor final class DialogueController {
    private let motion = PanelMotion()
    private unowned let app: AppEnvironment
    private var panel: DialoguePanel?
    private var timer: Task<Void, Never>?
    private var due = Date.distantFuture
    private var awakeAfter = Date.now.addingTimeInterval(90)
    private var suspended = false
    private var automatic = false
    private var observers: [NSObjectProtocol] = []

    init(app: AppEnvironment) { self.app = app }
    func start() {
        guard timer == nil else { return }
        app.dialogue.onUpdate = { [weak self] in self?.updatePanel() }
        app.dialogue.onClose = { [weak self] in
            self?.app.dialogueVoice.clear(); self?.app.speech.stop(); self?.schedule()
        }
        let center = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.willSleepNotification, NSWorkspace.screensDidSleepNotification, NSWorkspace.sessionDidResignActiveNotification] {
            observers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in self?.suspend() }
            })
        }
        for name in [NSWorkspace.didWakeNotification, NSWorkspace.screensDidWakeNotification, NSWorkspace.sessionDidBecomeActiveNotification] {
            observers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in self?.resume() }
            })
        }
        observers.append(DistributedNotificationCenter.default().addObserver(forName: Notification.Name("com.apple.screenIsLocked"), object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.suspend() }
        })
        observers.append(DistributedNotificationCenter.default().addObserver(forName: Notification.Name("com.apple.screenIsUnlocked"), object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.resume() }
        })
        observers.append(NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.updatePanel() }
        })
        schedule()
        timer = Task { [weak self] in
            while !Task.isCancelled {
                do { try await Task.sleep(for: .seconds(15)) } catch { return }
                self?.tick()
            }
        }
    }
    private func suspend() { suspended = true; app.dialogue.close() }
    private func resume() { suspended = false; awakeAfter = .now.addingTimeInterval(90); schedule() }
    func schedule() { due = DialogueTiming.next(now: .now, minutes: app.settings.dialogueMinutes, jitter: Double.random(in: 0...0.2)) }
    func configure(enabled: Bool, minutes: Int, reuse: Bool) {
        app.dialogue.close()
        do {
            try app.settings.updateDialogue(enabled: enabled, minutes: minutes, reuseVocabulary: reuse)
            app.dialogueSettingsError = nil; schedule()
        } catch { due = .distantFuture; app.dialogueSettingsError = AppError.message(for: error) }
    }
    func pause(until: Date?) {
        app.dialogue.close()
        do { try app.settings.pauseDialogue(until: until); app.dialogueSettingsError = nil; schedule() }
        catch { due = .distantFuture; app.dialogueSettingsError = AppError.message(for: error) }
    }
    func triggerNow() {
        guard !app.dialogue.isOpen else { updatePanel(); return }
        // Explicit testing bypasses interval/opt-in, never the microphone or screen lock.
        guard sessionAvailable else {
            app.dialogueSettingsError = "Разблокируйте экран и вернитесь в свою сессию Mac, затем повторите запуск."
            return
        }
        app.dialogueSettingsError = nil
        automatic = false
        app.dialogue.start()
    }
    private var sessionAvailable: Bool {
        guard !suspended, let session = CGSessionCopyCurrentDictionary() as? [String: Any],
              session[kCGSessionOnConsoleKey as String] as? Bool == true else { return false }
        // The session flag is optional; lifecycle notifications provide the other guard.
        return session["CGSSessionScreenIsLocked"] as? Bool != true
    }
    private var unobtrusive: Bool {
        guard sessionAvailable, Date.now >= awakeAfter else { return false }
        let front = NSWorkspace.shared.frontmostApplication
        let blocked = ["com.apple.iWork.Keynote", "com.microsoft.Powerpoint", "us.zoom.xos", "com.microsoft.teams2", "com.apple.ScreenSharing"]
        if blocked.contains(front?.bundleIdentifier ?? "") { return false }
        if NSScreen.screens.contains(where: { screen in
            guard let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else { return false }
            return CGDisplayIsInMirrorSet(number.uint32Value) != 0
        }) { return false }
        // Read bounds and owning PID only; never window titles or screen pixels, and request no screen recording access.
        guard let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else { return false }
        for window in windows where (window[kCGWindowOwnerPID as String] as? Int32) == front?.processIdentifier {
            guard let bounds = window[kCGWindowBounds as String] as? NSDictionary,
                  let frame = CGRect(dictionaryRepresentation: bounds),
                  (window[kCGWindowLayer as String] as? Int) == 0 else { continue }
            if NSScreen.screens.contains(where: { abs(frame.width - $0.frame.width) < 4 && abs(frame.height - $0.frame.height) < 4 }) { return false }
        }
        return !app.commandPalette.isVisible && !app.commandPaletteModel.isLoading && !app.clipboardModel.hasContent && !app.speech.isSpeaking
    }
    private func tick() {
        if !sessionAvailable { if app.dialogue.isOpen { app.dialogue.close() }; return }
        if app.dialogue.isOpen { return }
        let idle = CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: CGEventType(rawValue: UInt32.max)!)
        if DialogueTiming.shouldTrigger(now: .now, due: due, pausedUntil: app.settings.dialoguePausedUntil,
            enabled: app.settings.dialogueEnabled, isOpen: app.dialogue.isOpen, safe: unobtrusive, idleSeconds: idle) {
            schedule(); automatic = true; app.dialogue.start()
        }
    }
    private func updatePanel() {
        guard app.dialogue.isOpen else { motion.hide(panel); return }
        guard sessionAvailable else { app.dialogue.close(); return }
        // Recheck after generation too: the user may have entered a meeting while waiting.
        if automatic && app.dialogue.answer.isEmpty && !unobtrusive { app.dialogue.close(); return }
        if panel == nil {
            let value = DialoguePanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
            value.title = "Мини-диалог — DéjàVu"
            value.level = .floating; value.isReleasedWhenClosed = false; value.hidesOnDeactivate = false
            value.collectionBehavior = [.canJoinAllSpaces]
            value.isOpaque = false; value.backgroundColor = .clear; value.hasShadow = true
            value.onClose = { [weak self] in self?.app.dialogue.close() }
            value.contentView = NSHostingView(rootView: DialogueView().modifier(DejavuAppearance()).environment(app).environment(\.locale, Locale(identifier: "ru_RU")))
            panel = value
        }
        let screen = NSScreen.screens.first(where: { $0.frame.contains(NSEvent.mouseLocation) }) ?? NSScreen.main
        if let screen {
            let bounds = screen.visibleFrame
            let width = min(420, bounds.width - 32), height = min(640, bounds.height - 32)
            panel?.setFrame(NSRect(x: bounds.maxX - width - 16, y: bounds.minY + 16, width: width, height: height), display: true)
        }
        if let panel { motion.show(panel, takesFocus: !automatic) }
    }
}

private final class DialoguePanel: NSPanel {
    var onClose: (() -> Void)?
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
    override func cancelOperation(_ sender: Any?) { onClose?() }
}
