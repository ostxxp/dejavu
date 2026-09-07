import AppKit
import SwiftUI

// Stable raw values are persisted; unknown values from a newer app fall back safely.
enum AppAccent: String, CaseIterable, Identifiable {
    case lavender, rose, sage, ocean, apricot
    var id: String { rawValue }
    var title: String {
        switch self {
        case .lavender: "Лаванда"
        case .rose: "Роза"
        case .sage: "Шалфей"
        case .ocean: "Океан"
        case .apricot: "Абрикос"
        }
    }
    var color: Color {
        let rgb: (Double, Double, Double) = switch self {
        case .lavender: (0.45, 0.34, 0.73)
        case .rose: (0.71, 0.28, 0.43)
        case .sage: (0.23, 0.48, 0.36)
        case .ocean: (0.19, 0.43, 0.69)
        case .apricot: (0.68, 0.36, 0.17)
        }
        return Color(red: rgb.0, green: rgb.1, blue: rgb.2)
    }
}

struct DejavuAppearance: ViewModifier {
    @Environment(AppEnvironment.self) private var app
    func body(content: Content) -> some View {
        content.tint(app.settings.accent.color).accentColor(app.settings.accent.color)
    }
}

// Small, isolated decorative subtree. No timers, geometry polling, or whole-screen blur.
struct FloatingGreeting: View {
    @Environment(AppEnvironment.self) private var app
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    var body: some View {
        HStack(spacing: 14) {
            charm("text.bubble.fill", size: 34, angle: -9)
            VStack(alignment: .leading, spacing: 4) {
                Text("Маленький шаг каждый день").font(.headline)
                Text("И французский становится ближе").font(.caption).foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            charm("sparkle", size: 23, angle: 12)
            charm("heart.fill", size: 18, angle: -12)
        }
        .padding(18)
        .background(app.settings.accent.color.opacity(0.09), in: RoundedRectangle(cornerRadius: 24))
    }
    @ViewBuilder private func charm(_ symbol: String, size: CGFloat, angle: Double) -> some View {
        let icon = Image(systemName: symbol).font(.system(size: size, weight: .medium))
            .foregroundStyle(app.settings.accent.color.gradient)
            .accessibilityHidden(true).allowsHitTesting(false)
        if reduceMotion || scenePhase != .active {
            icon
        } else {
            icon.phaseAnimator([false, true]) { content, up in
                content.offset(y: up ? -3 : 3).rotationEffect(.degrees(up ? angle : -angle / 2))
            } animation: { _ in .easeInOut(duration: 3.5) }
        }
    }
}

@MainActor final class PanelMotion {
    private var revision = 0
    private(set) var isClosing = false

    func show(_ panel: NSPanel, takesFocus: Bool) {
        let opening = !panel.isVisible || isClosing
        guard opening else {
            if takesFocus { panel.makeKeyAndOrderFront(nil) } else { panel.orderFrontRegardless() }
            return
        }
        revision += 1
        isClosing = false
        let target = panel.frame
        let animate = !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        if animate && !panel.isVisible {
            panel.alphaValue = 0
            panel.setFrame(target.offsetBy(dx: 0, dy: -8), display: false)
        }
        if takesFocus { panel.makeKeyAndOrderFront(nil) } else { panel.orderFrontRegardless() }
        if animate {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.22
                context.timingFunction = CAMediaTimingFunction(name: .easeOut)
                panel.animator().alphaValue = 1
                panel.animator().setFrame(target, display: true)
            }
        } else { panel.alphaValue = 1 }
    }

    func hide(_ panel: NSPanel?) {
        guard let panel, panel.isVisible, !isClosing else { return }
        revision += 1
        let current = revision
        isClosing = true
        if NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            panel.orderOut(nil)
            isClosing = false
            return
        }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.16
            context.timingFunction = CAMediaTimingFunction(name: .easeIn)
            panel.animator().alphaValue = 0
        } completionHandler: { [weak self, weak panel] in
            Task { @MainActor in
                guard let self, let panel, self.revision == current else { return }
                panel.orderOut(nil)
                panel.alphaValue = 1
                self.isClosing = false
            }
        }
    }
}

struct AccentSwatches: View {
    let selected: AppAccent
    let choose: (AppAccent) -> Void
    var body: some View {
        HStack(spacing: 14) {
            ForEach(AppAccent.allCases) { accent in
                Button { choose(accent) } label: {
                    VStack(spacing: 6) {
                        Circle().fill(accent.color.gradient)
                            .frame(width: 30, height: 30)
                            .overlay {
                                if selected == accent { Image(systemName: "checkmark").font(.system(size: 13, weight: .bold)).foregroundStyle(.white) }
                            }
                            .padding(4)
                            .overlay(Circle().stroke(selected == accent ? accent.color : .clear, lineWidth: 2))
                        Text(accent.title).font(.caption)
                    }
                    .frame(minWidth: 55)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(accent.title)
                .accessibilityValue(selected == accent ? "Выбран" : "Не выбран")
            }
        }
        .padding(.vertical, 6)
    }
}
