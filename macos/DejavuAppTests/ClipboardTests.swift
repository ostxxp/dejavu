import AppKit
import SwiftData
import XCTest
@testable import DejavuApp

@MainActor final class ClipboardTests: XCTestCase {
    func testPolicyRejectsNonFrenchOversizeSecretsAndTechnicalText() {
        for text in ["", String(repeating: "a", count: 4_001), "https://example.com/bonjour",
                     "mon mot de passe: placeholder", "bonjour test@example.com", "123456789", "const bonjour = {}"] {
            XCTAssertNil(ClipboardPolicy.candidate(text, confidence: { _ in 1 }))
        }
        XCTAssertNil(ClipboardPolicy.candidate("Good morning, how are you today?"))
        XCTAssertNil(ClipboardPolicy.candidate("Привет, как сегодня дела?"))
        XCTAssertNotNil(ClipboardPolicy.candidate("Je voudrais apprendre le français avec toi tous les jours."))
        XCTAssertNil(ClipboardPolicy.candidate("bonjour", confidence: { _ in 0.79 }))
        XCTAssertEqual(ClipboardPolicy.candidate(" bonjour \n", confidence: { _ in 1 }), "bonjour")
    }

    func testDuplicateWindowPreservesAccentsAndExpires() {
        var duplicates = ClipboardDuplicates()
        let now = Date(timeIntervalSince1970: 1_000)
        XCTAssertTrue(duplicates.accept("ou", now: now))
        XCTAssertFalse(duplicates.accept("ou", now: now.addingTimeInterval(599)))
        XCTAssertTrue(duplicates.accept("où", now: now))
        XCTAssertTrue(duplicates.accept("ou", now: now.addingTimeInterval(600)))
    }

    func testMonitorNeverReadsExistingOrDisabledClipboardAndDebouncesChanges() {
        let reader = FakeClipboard()
        let monitor = ClipboardMonitor(reader: reader, filter: { $0 })
        var received: [String] = []
        monitor.onCandidate = { received.append($0) }
        monitor.poll()
        monitor.start(schedule: false)
        monitor.poll()
        XCTAssertEqual(reader.reads, 0)
        reader.copy("first")
        monitor.poll()
        reader.copy("second")
        monitor.poll()
        XCTAssertEqual(reader.reads, 0)
        monitor.poll()
        monitor.poll()
        XCTAssertEqual(received, ["second"])
        XCTAssertEqual(reader.reads, 1)
        reader.copy("second")
        monitor.poll(); monitor.poll()
        XCTAssertEqual(received, ["second"])
        monitor.stop()
        reader.copy("third")
        monitor.poll()
        XCTAssertEqual(reader.reads, 2)
        monitor.start(schedule: false)
        monitor.poll()
        XCTAssertEqual(reader.reads, 2)
    }

    func testMonitorRejectsFilteredTextAndClipboardChangesDuringRead() {
        let reader = FakeClipboard()
        let monitor = ClipboardMonitor(reader: reader, filter: { $0 == "bonjour" ? $0 : nil })
        var received: [String] = []
        monitor.onCandidate = { received.append($0) }
        monitor.start(schedule: false)
        reader.copy("not French")
        monitor.poll(); monitor.poll()
        reader.copy("bonjour")
        reader.changeDuringRead = true
        monitor.poll(); monitor.poll()
        XCTAssertTrue(received.isEmpty)
    }

    func testDefaultsAreOptInAndOptionsPersist() throws {
        let h = try ClipboardHarness()
        XCTAssertFalse(h.settings.clipboardEnabled)
        XCTAssertFalse(h.settings.clipboardAutomatic)
        try h.enable(automatic: true)
        let reloaded = try SettingsStore(context: h.container.mainContext)
        XCTAssertTrue(reloaded.clipboardEnabled)
        XCTAssertTrue(reloaded.clipboardAutomatic)
        XCTAssertTrue(reloaded.clipboardShowPanel)
    }

    func testManualAndLongCandidatesDoNotSendUntilConfirmed() async throws {
        let h = try ClipboardHarness()
        h.model.receive("bonjour")
        XCTAssertNil(h.model.candidate)
        try h.enable(automatic: false)
        h.model.receive("bonjour")
        XCTAssertTrue(h.provider.requests.isEmpty)
        h.model.analyze()
        await settle { !h.model.isLoading }
        XCTAssertEqual(h.provider.requests.count, 1)
        try h.enable(automatic: true)
        h.model.receive(String(repeating: "bonjour ", count: 70))
        XCTAssertFalse(h.model.isLoading)
        XCTAssertEqual(h.provider.requests.count, 1)
        h.model.clear()
        XCTAssertNil(h.model.candidate)
    }

    func testAutoResultStoresAnalysisButNeverRawClipboardQuery() async throws {
        let h = try ClipboardHarness()
        try h.enable(automatic: true)
        h.model.receive("Je voudrais apprendre le français.")
        await settle { !h.model.isLoading }
        XCTAssertNotNil(h.model.result)
        XCTAssertNil(h.model.candidate)
        let entries = try h.container.mainContext.fetch(FetchDescriptor<AnalysisHistoryEntry>())
        XCTAssertEqual(entries.count, 1)
        XCTAssertEqual(entries.first?.source, .clipboard)
        XCTAssertEqual(entries.first?.french, "tu devrais")
        XCTAssertEqual(try h.container.mainContext.fetchCount(FetchDescriptor<CommandPaletteHistoryEntry>()), 0)
    }

    func testCancellationAndDisablingDiscardLateResponses() async throws {
        let h = try ClipboardHarness()
        try h.enable(automatic: true)
        h.provider.suspend = true
        h.model.receive("bonjour")
        await settle { h.provider.continuation != nil }
        try h.settings.updateClipboard(enabled: false, automatic: true, showPanel: true, history: true)
        h.model.clear()
        h.provider.finish()
        await settle { h.provider.finished }
        XCTAssertNil(h.model.result)
        XCTAssertEqual(try h.container.mainContext.fetchCount(FetchDescriptor<AnalysisHistoryEntry>()), 0)
    }

    func testGlobalPrivacyChangesDuringRequestPreventHistory() async throws {
        let h = try ClipboardHarness()
        try h.enable(automatic: true)
        h.provider.suspend = true
        h.model.receive("bonjour")
        await settle { h.provider.continuation != nil }
        try h.settings.update(provider: .openAI, model: h.settings.model, saveHistory: false)
        try h.settings.update(provider: .openAI, model: h.settings.model, saveHistory: true)
        h.provider.finish()
        await settle { !h.model.isLoading }
        XCTAssertNotNil(h.model.result)
        XCTAssertEqual(try h.container.mainContext.fetchCount(FetchDescriptor<AnalysisHistoryEntry>()), 0)
    }

    func testClipboardHistoryCanBeDisabledAndFailuresAreNotSaved() async throws {
        let h = try ClipboardHarness()
        try h.settings.updateClipboard(enabled: true, automatic: true, showPanel: false, history: false)
        h.model.receive("bonjour")
        await settle { !h.model.isLoading }
        XCTAssertNotNil(h.model.result)
        XCTAssertEqual(try h.container.mainContext.fetchCount(FetchDescriptor<AnalysisHistoryEntry>()), 0)
        h.provider.error = AppError.network
        h.model.receive("salut")
        await settle { !h.model.isLoading }
        XCTAssertNotNil(h.model.errorMessage)
        XCTAssertNil(h.model.result)
        XCTAssertEqual(try h.container.mainContext.fetchCount(FetchDescriptor<AnalysisHistoryEntry>()), 0)
    }

    func testNativePrivatePasteboardRespectsConcealedAndFileMarkers() {
        let board = NSPasteboard.withUniqueName()
        defer { board.releaseGlobally() }
        let reader = SystemClipboard(board: board, sourceIsOwnApp: { false })
        board.setString("bonjour", forType: .string)
        XCTAssertEqual(reader.readText(), "bonjour")
        board.setData(Data(), forType: NSPasteboard.PasteboardType("org.nspasteboard.ConcealedType"))
        XCTAssertNil(reader.readText())
        board.clearContents()
        board.setString("bonjour", forType: .string)
        board.setString("file:///example", forType: .fileURL)
        XCTAssertNil(reader.readText())
        board.clearContents()
        board.setString("bonjour", forType: .string)
        XCTAssertNil(SystemClipboard(board: board, sourceIsOwnApp: { true }).readText())
    }

    func testNativePanelReplacesContentPreservesFocusAndPausesDismissal() async throws {
        let app = try AppEnvironment(inMemory: true)
        try app.settings.updateClipboard(enabled: true, automatic: false, showPanel: true, history: false)
        let controller = ClipboardPanelController(app: app, candidateLifetime: .milliseconds(100))
        app.clipboardModel.onUpdate = { [weak controller] in controller?.update() }
        let keyWindow = NSApp.keyWindow
        app.clipboardModel.receive("Je voudrais apprendre le français.")
        let panel = try XCTUnwrap(NSApp.windows.first { $0.identifier?.rawValue == "clipboard-result" && $0.isVisible })
        XCTAssertFalse(panel.isKeyWindow)
        XCTAssertTrue(NSApp.keyWindow === keyWindow)
        controller.setHovering(true)
        try await Task.sleep(for: .milliseconds(150))
        XCTAssertTrue(panel.isVisible)
        app.clipboardModel.receive("Nous parlons français tous les jours.")
        XCTAssertEqual(NSApp.windows.filter { $0.identifier?.rawValue == "clipboard-result" && $0.isVisible }.count, 1)
        XCTAssertTrue(panel.isVisible)
        controller.setHovering(false)
        await settle { !app.clipboardModel.hasContent }
        await settle { !panel.isVisible }
        XCTAssertFalse(panel.isVisible)
    }

    func testReopeningDuringFadeDoesNotDismissNewPanel() async throws {
        let panel = NSPanel(contentRect: NSRect(x: 100, y: 100, width: 100, height: 100),
                            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        let motion = PanelMotion()
        defer { panel.orderOut(nil) }
        motion.show(panel, takesFocus: false)
        motion.hide(panel)
        motion.show(panel, takesFocus: false)
        try await Task.sleep(for: .milliseconds(350))
        XCTAssertTrue(panel.isVisible)
        XCTAssertEqual(panel.alphaValue, 1, accuracy: 0.01)
        motion.hide(panel)
        await settle { !panel.isVisible }
    }

    func testPhaseTwoSettingsMigrateWithClipboardDisabled() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("migration.store")
        try autoreleasepool {
            let schema = Schema([PhaseTwo.AppSettings.self])
            let old = try ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema, url: url, cloudKitDatabase: .none)])
            let record = PhaseTwo.AppSettings()
            old.mainContext.insert(record)
            try old.mainContext.save()
        }
        let current = try PersistenceController.makeContainer(url: url)
        let settings = try SettingsStore(context: current.mainContext)
        XCTAssertEqual(settings.model, "example-model")
        XCTAssertFalse(settings.saveHistory)
        XCTAssertFalse(settings.clipboardEnabled)
        XCTAssertFalse(settings.clipboardAutomatic)
        XCTAssertTrue(settings.clipboardShowPanel)
        XCTAssertTrue(settings.clipboardHistory)
        XCTAssertEqual(settings.accent, .lavender)
        XCTAssertTrue(settings.playfulDetails)
        XCTAssertTrue(settings.welcomeCompleted) // Existing installations are not interrupted by first-run UI.
    }

    private func settle(_ predicate: () -> Bool) async {
        let deadline = ContinuousClock.now + .seconds(2)
        while !predicate(), ContinuousClock.now < deadline { try? await Task.sleep(for: .milliseconds(1)) }
        XCTAssertTrue(predicate())
    }
}

@MainActor private final class FakeClipboard: ClipboardReading {
    var changeCount = 0
    var text: String?
    var reads = 0
    var changeDuringRead = false
    func copy(_ value: String) { changeCount += 1; text = value }
    func readText() -> String? {
        reads += 1
        if changeDuringRead { changeCount += 1 }
        return text
    }
}

@MainActor private struct ClipboardHarness {
    let container: ModelContainer
    let settings: SettingsStore
    let model: ClipboardModel
    let provider = ClipboardProvider()
    init() throws {
        container = try PersistenceController.makeContainer(inMemory: true)
        settings = try SettingsStore(context: container.mainContext)
        let vocabulary = VocabularyStore(context: container.mainContext)
        model = ClipboardModel(service: provider, settings: settings,
                               history: HistoryStore(context: container.mainContext, vocabulary: vocabulary))
    }
    func enable(automatic: Bool) throws {
        try settings.updateClipboard(enabled: true, automatic: automatic, showPanel: true, history: true)
    }
}

@MainActor private final class ClipboardProvider: LanguageAnalyzing {
    var requests: [AnalysisRequest] = []
    var error: AppError?
    var suspend = false
    var finished = false
    var continuation: CheckedContinuation<AnalysisOutcome, Error>?
    func analyze(_ request: AnalysisRequest, forceRefresh: Bool) async throws -> AnalysisOutcome {
        requests.append(request)
        if let error { throw error }
        if suspend {
            let result = try await withCheckedThrowingContinuation { continuation = $0 }
            finished = true
            return result
        }
        return AnalysisOutcome(analysis: PersistenceTests.analysis(), fromCache: false)
    }
    func finish() {
        continuation?.resume(returning: AnalysisOutcome(analysis: PersistenceTests.analysis(), fromCache: false))
        continuation = nil
    }
}

// Historical persisted fields, before the opt-in clipboard preferences existed.
private enum PhaseTwo {
    @Model final class AppSettings {
        @Attribute(.unique) var identifier: String
        var providerRaw: String
        var model: String
        var saveHistory: Bool
        init() {
            identifier = "default"
            providerRaw = "openAI"
            model = "example-model"
            saveHistory = false
        }
    }
}
