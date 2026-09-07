import Foundation
import Observation
import SwiftData

@MainActor @Observable final class SettingsStore {
    private let context: ModelContext
    private let record: AppSettings
    private(set) var historyRevision = 0
    private(set) var clipboardRevision = 0
    var welcomeCompleted: Bool { record.welcomeCompleted }
    var dialogueEnabled: Bool { record.dialogueEnabled }
    var dialogueMinutes: Int { record.dialogueMinutes }
    var dialoguePausedUntil: Date? { record.dialoguePausedUntil }
    var dialogueReuseVocabulary: Bool { record.dialogueReuseVocabulary }
    var bridgeEnabled: Bool { record.bridgeEnabled }
    var bridgeExtensionID: String { record.bridgeExtensionID }
    var clipboardEnabled: Bool { record.clipboardEnabled }
    var clipboardAutomatic: Bool { record.clipboardAutomatic }
    var clipboardShowPanel: Bool { record.clipboardShowPanel }
    var clipboardHistory: Bool { record.clipboardHistory }
    var provider: AIProvider { AIProvider(rawValue: record.providerRaw) ?? .openAI }
    var model: String { record.model }
    var saveHistory: Bool { record.saveHistory }

    init(context: ModelContext) throws {
        self.context = context
        var descriptor = FetchDescriptor<AppSettings>(predicate: #Predicate { $0.identifier == "default" })
        descriptor.fetchLimit = 1
        if let existing = try context.fetch(descriptor).first {
            record = existing
        } else {
            record = AppSettings()
            context.insert(record)
            try PersistenceController.save(context)
        }
    }

    func completeWelcome() throws {
        record.welcomeCompleted = true
        try PersistenceController.save(context)
    }

    func updateDialogue(enabled: Bool, minutes: Int, reuseVocabulary: Bool) throws {
        guard (10...240).contains(minutes) else { throw AppError.invalidDialogueInterval }
        record.dialogueEnabled = enabled
        record.dialogueMinutes = minutes
        record.dialogueReuseVocabulary = reuseVocabulary
        try PersistenceController.save(context)
    }

    func pauseDialogue(until: Date?) throws {
        record.dialoguePausedUntil = until
        try PersistenceController.save(context)
    }

    func updateBridge(enabled: Bool, extensionID: String) throws {
        let id = extensionID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard id.isEmpty || id.range(of: "^[a-p]{32}$", options: .regularExpression) != nil else { throw AppError.invalidExtensionID }
        record.bridgeEnabled = enabled
        record.bridgeExtensionID = id
        try PersistenceController.save(context)
    }

    func updateClipboard(enabled: Bool, automatic: Bool, showPanel: Bool, history: Bool) throws {
        clipboardRevision += 1
        record.clipboardEnabled = enabled
        record.clipboardAutomatic = automatic
        record.clipboardShowPanel = showPanel
        record.clipboardHistory = history
        try PersistenceController.save(context)
    }

    func update(provider: AIProvider, model: String, saveHistory: Bool) throws {
        let model = model.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !model.isEmpty, model.count <= 100,
              model.range(of: #"^[A-Za-z0-9][A-Za-z0-9._:-]*$"#, options: .regularExpression) != nil else {
            throw AppError.invalidModel
        }
        record.providerRaw = provider.rawValue
        record.model = model
        if record.saveHistory != saveHistory { historyRevision += 1 }
        record.saveHistory = saveHistory
        try PersistenceController.save(context)
    }
}
