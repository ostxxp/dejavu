import Foundation
import Observation
import SwiftData

@MainActor @Observable final class SettingsStore {
    private let context: ModelContext
    private let record: AppSettings
    private(set) var historyRevision = 0
    private(set) var clipboardRevision = 0
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
