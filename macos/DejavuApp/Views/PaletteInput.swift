import AppKit
import SwiftUI

/// Native field-editor commands make Enter and history arrows reliable in an NSPanel.
struct PaletteInput: NSViewRepresentable {
    @Binding var text: String
    var placeholder: String
    var isEnabled: Bool
    var focusToken: Int
    var onSubmit: () -> Void
    var onPrevious: () -> Void
    var onNext: () -> Void
    var onClose: () -> Void

    func makeNSView(context: Context) -> NSTextField {
        let field = NSTextField()
        field.isBordered = false
        field.drawsBackground = false
        field.font = .systemFont(ofSize: 21)
        field.focusRingType = .none
        field.usesSingleLineMode = true
        field.cell?.isScrollable = true
        field.delegate = context.coordinator
        field.setAccessibilityLabel("Вопрос о французском")
        field.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return field
    }

    func updateNSView(_ field: NSTextField, context: Context) {
        context.coordinator.parent = self
        if field.stringValue != text { field.stringValue = text }
        field.placeholderString = placeholder
        field.isEnabled = isEnabled
        if context.coordinator.focusToken != focusToken {
            context.coordinator.focusToken = focusToken
            DispatchQueue.main.async { [weak field] in
                guard let field, field.isEnabled, let window = field.window, window.isVisible else { return }
                window.makeFirstResponder(field)
                field.selectText(nil)
            }
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    final class Coordinator: NSObject, NSTextFieldDelegate {
        var parent: PaletteInput
        var focusToken: Int?
        init(parent: PaletteInput) { self.parent = parent }

        func controlTextDidChange(_ notification: Notification) {
            guard let field = notification.object as? NSTextField else { return }
            parent.text = field.stringValue
        }

        func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            // Let input methods finish composition before treating keys as app commands.
            guard !textView.hasMarkedText() else { return false }
            switch commandSelector {
            case #selector(NSResponder.insertNewline(_:)): parent.onSubmit()
            case #selector(NSResponder.moveUp(_:)): parent.onPrevious()
            case #selector(NSResponder.moveDown(_:)): parent.onNext()
            case #selector(NSResponder.cancelOperation(_:)): parent.onClose()
            default: return false
            }
            return true
        }
    }
}
