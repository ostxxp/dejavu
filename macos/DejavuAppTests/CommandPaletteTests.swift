import AppKit
import SwiftData
import XCTest
@testable import DejavuApp

@MainActor final class CommandPaletteTests: XCTestCase {
    func testCacheExpiresWithoutExtendingLifetimeOnRead() {
        var now = Date(timeIntervalSince1970: 100)
        let cache = AnalysisCache(capacity: 2, lifetime: 30, now: { now })
        let key = cacheKey("a")
        cache.insert(PersistenceTests.analysis(), for: key)
        now = now.addingTimeInterval(29)
        XCTAssertNotNil(cache.value(for: key))
        now = now.addingTimeInterval(1)
        XCTAssertNil(cache.value(for: key))
    }

    func testLiteralNullMetadataIsNotExposedToTheInterface() throws {
        var analysis = PersistenceTests.analysis()
        analysis.ipa = "null"
        analysis.gender = " NULL "
        analysis.article = ""
        let clean = try analysis.validated()
        XCTAssertNil(clean.ipa)
        XCTAssertNil(clean.gender)
        XCTAssertNil(clean.article)
        XCTAssertEqual(clean.original, "tu devrais")
    }

    func testCacheEvictsLeastRecentlyUsedAndClears() {
        let cache = AnalysisCache(capacity: 2)
        cache.insert(PersistenceTests.analysis(), for: cacheKey("a"))
        cache.insert(PersistenceTests.analysis(), for: cacheKey("b"))
        _ = cache.value(for: cacheKey("a"))
        cache.insert(PersistenceTests.analysis(), for: cacheKey("c"))
        XCTAssertNil(cache.value(for: cacheKey("b")))
        XCTAssertNotNil(cache.value(for: cacheKey("a")))
        cache.clear()
        XCTAssertNil(cache.value(for: cacheKey("a")))
        XCTAssertNil(cache.value(for: cacheKey("c")))
        XCTAssertEqual(cache.generation, 1)
    }

    func testRequestIdentityPreservesCaseAccentsAndFollowUpContext() throws {
        XCTAssertEqual(try AnalysisRequest(query: " tu devrais \n").fingerprint(),
                       try AnalysisRequest(query: "tu devrais").fingerprint())
        XCTAssertNotEqual(try AnalysisRequest(query: "a").fingerprint(), try AnalysisRequest(query: "à").fingerprint())
        XCTAssertNotEqual(try AnalysisRequest(query: "Paris").fingerprint(), try AnalysisRequest(query: "paris").fingerprint())
        let context = FollowUpContext(originalQuery: "tu devrais", analysis: PersistenceTests.analysis())
        XCTAssertNotEqual(try AnalysisRequest(query: "почему?").fingerprint(),
                          try AnalysisRequest(query: "почему?", context: context).fingerprint())
    }

    func testSharedServiceCachesSeparatesModelAndForcesRefresh() async throws {
        let container = try PersistenceController.makeContainer(inMemory: true)
        let settings = try SettingsStore(context: container.mainContext)
        let provider = CountingProvider(analysis: PersistenceTests.analysis())
        let service = LanguageAnalysisService(settings: settings, keychain: UnusedKeyStore(),
                                              providerFactory: { _, _ in provider })
        let request = AnalysisRequest(query: "tu devrais")
        let first = try await service.analyze(request)
        let second = try await service.analyze(request)
        XCTAssertFalse(first.fromCache)
        XCTAssertTrue(second.fromCache)
        _ = try await service.analyze(request, forceRefresh: true)
        try settings.update(provider: .openAI, model: "another-model", saveHistory: true)
        let changedModel = try await service.analyze(request)
        XCTAssertFalse(changedModel.fromCache)
        service.clearCache()
        _ = try await service.analyze(request)
        let count = await provider.count
        XCTAssertEqual(count, 4)
    }

    func testHistoryCursorRestoresDraftAndStopsAtBoundaries() {
        var cursor = QueryHistoryCursor()
        let first = AnalysisRequest(query: "bonjour")
        let second = AnalysisRequest(query: "tu devrais")
        let draft = AnalysisRequest(query: "мой черновик")
        cursor.reset([first, second])
        XCTAssertEqual(cursor.previous(from: draft), first)
        XCTAssertEqual(cursor.previous(from: first), second)
        XCTAssertEqual(cursor.previous(from: second), second)
        XCTAssertEqual(cursor.next(), first)
        XCTAssertEqual(cursor.next(), draft)
        XCTAssertNil(cursor.next())
    }

    func testQueryStoreDeduplicatesBoundsAndKeepsContext() throws {
        let container = try PersistenceController.makeContainer(inMemory: true)
        let store = CommandPaletteHistoryStore(context: container.mainContext, capacity: 2)
        let context = FollowUpContext(originalQuery: "tu devrais", analysis: PersistenceTests.analysis())
        let followUp = AnalysisRequest(query: "почему?", context: context)
        for (i, request) in [AnalysisRequest(query: "bonjour"), AnalysisRequest(query: "leurs"), followUp, followUp].enumerated() {
            try store.stage(request, now: Date(timeIntervalSince1970: Double(i)))
            try PersistenceController.save(container.mainContext)
        }
        XCTAssertEqual(try store.recentRequests(), [followUp, AnalysisRequest(query: "leurs")])
        let vocabulary = VocabularyStore(context: container.mainContext)
        try HistoryStore(context: container.mainContext, vocabulary: vocabulary).clear()
        XCTAssertTrue(try store.recentRequests().isEmpty)
    }

    func testPaletteAllowsExactlyOneSuccessfulFollowUpAndUsesSharedVocabulary() async throws {
        let h = try Harness()
        h.model.input = "tu devrais"
        h.model.submit()
        await settle { !h.model.isLoading }
        XCTAssertTrue(h.model.canFollowUp)
        h.model.beginFollowUp()
        XCTAssertEqual(h.model.context?.originalQuery, "tu devrais")
        h.model.input = "почему мягче?"
        h.model.submit()
        await settle { !h.model.isLoading }
        XCTAssertTrue(h.model.completedFollowUp)
        XCTAssertFalse(h.model.canFollowUp)
        XCTAssertFalse(h.model.canSubmit)
        XCTAssertEqual(h.service.requests.count, 2)
        XCTAssertNotNil(h.service.requests.last?.context)
        h.model.save()
        h.model.save()
        h.model.listen()
        let entry = try XCTUnwrap(h.vocabulary.find("tu devrais"))
        XCTAssertTrue(entry.savedByUser)
        XCTAssertEqual(entry.seenCount, 2)
        XCTAssertEqual(entry.source, .commandPalette)
        XCTAssertEqual(h.speech.spoken, ["tu devrais"])
        h.model.clear()
        XCTAssertNil(h.model.result)
        XCTAssertNil(h.model.context)
        XCTAssertEqual(h.model.input, "")
    }

    func testCancellationDropsLateAnswerAndDoesNotSaveHistory() async throws {
        let h = try Harness()
        h.service.suspend = true
        h.model.input = "bonjour"
        h.model.submit()
        await settle { h.service.continuation != nil }
        h.model.clear()
        h.service.finish()
        await settle { h.service.finished }
        XCTAssertNil(h.model.result)
        XCTAssertFalse(h.model.isLoading)
        XCTAssertEqual(try h.container.mainContext.fetchCount(FetchDescriptor<AnalysisHistoryEntry>()), 0)
        XCTAssertEqual(try h.container.mainContext.fetchCount(FetchDescriptor<CommandPaletteHistoryEntry>()), 0)
    }

    func testPrivacyChangeDuringRequestPreventsPersistenceEvenIfReenabled() async throws {
        let h = try Harness()
        h.service.suspend = true
        h.model.input = "tu devrais"
        h.model.submit()
        await settle { h.service.continuation != nil }
        try h.settings.update(provider: .openAI, model: h.settings.model, saveHistory: false)
        try h.settings.update(provider: .openAI, model: h.settings.model, saveHistory: true)
        h.service.finish()
        await settle { !h.model.isLoading }
        XCTAssertNotNil(h.model.result)
        XCTAssertEqual(try h.container.mainContext.fetchCount(FetchDescriptor<VocabularyEntry>()), 0)
        XCTAssertEqual(try h.container.mainContext.fetchCount(FetchDescriptor<CommandPaletteHistoryEntry>()), 0)
    }

    func testDisabledHistoryStillAllowsExplicitSaveAndFailedRequestsAreNotPersisted() async throws {
        let h = try Harness()
        try h.settings.update(provider: .openAI, model: h.settings.model, saveHistory: false)
        h.model.input = "tu devrais"
        h.model.submit()
        await settle { !h.model.isLoading }
        h.model.save()
        XCTAssertTrue(try XCTUnwrap(h.vocabulary.find("tu devrais")).savedByUser)
        XCTAssertEqual(try h.container.mainContext.fetchCount(FetchDescriptor<AnalysisHistoryEntry>()), 0)
        h.model.clear()
        h.service.error = AppError.network
        h.model.input = "bonjour"
        h.model.submit()
        await settle { !h.model.isLoading }
        XCTAssertEqual(h.model.errorMessage, AppError.network.errorDescription)
        XCTAssertNil(h.model.result)
        XCTAssertEqual(try h.container.mainContext.fetchCount(FetchDescriptor<CommandPaletteHistoryEntry>()), 0)
    }

    func testPhaseOneStoreMigratesWithoutLosingVocabularyOrSettings() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("migration.store")
        try autoreleasepool {
            let oldSchema = Schema([VocabularyEntry.self, AnalysisHistoryEntry.self, AppSettings.self])
            let configuration = ModelConfiguration(schema: oldSchema, url: url, cloudKitDatabase: .none)
            let old = try ModelContainer(for: oldSchema, configurations: [configuration])
            let settings = try SettingsStore(context: old.mainContext)
            try settings.update(provider: .openAI, model: "gpt-4o-mini", saveHistory: false)
            _ = try VocabularyStore(context: old.mainContext).save(PersistenceTests.analysis(), source: .manual)
        }
        let current = try PersistenceController.makeContainer(url: url)
        XCTAssertFalse(try SettingsStore(context: current.mainContext).saveHistory)
        XCTAssertTrue(try XCTUnwrap(VocabularyStore(context: current.mainContext).find("tu devrais")).savedByUser)
        let history = CommandPaletteHistoryStore(context: current.mainContext)
        try history.stage(AnalysisRequest(query: "bonjour"), now: .now)
        try PersistenceController.save(current.mainContext)
        XCTAssertEqual(try history.recentRequests().count, 1)
    }

    func testPanelFitsSmallAndSecondaryScreens() {
        for screen in [NSRect(x: 0, y: 60, width: 1440, height: 800),
                       NSRect(x: -1024, y: -200, width: 1024, height: 700),
                       NSRect(x: 100, y: 0, width: 500, height: 400)] {
            let frame = PalettePlacement.frame(in: screen, preferredHeight: 720)
            XCTAssertTrue(screen.contains(frame))
            XCTAssertLessThanOrEqual(frame.width, 640)
        }
    }

    private func cacheKey(_ value: String) -> AnalysisCache.Key {
        .init(provider: "openAI", model: "gpt-4o-mini", requestFingerprint: value)
    }

    private func settle(_ predicate: () -> Bool) async {
        let deadline = ContinuousClock.now + .seconds(2)
        while !predicate(), ContinuousClock.now < deadline { try? await Task.sleep(for: .milliseconds(1)) }
        XCTAssertTrue(predicate(), "Asynchronous state did not settle")
    }
}

@MainActor private struct Harness {
    let container: ModelContainer
    let settings: SettingsStore
    let vocabulary: VocabularyStore
    let service = TestAnalysisService()
    let speech = TestSpeech()
    let model: CommandPaletteModel

    init() throws {
        container = try PersistenceController.makeContainer(inMemory: true)
        settings = try SettingsStore(context: container.mainContext)
        vocabulary = VocabularyStore(context: container.mainContext)
        model = CommandPaletteModel(service: service, vocabulary: vocabulary,
                                    history: HistoryStore(context: container.mainContext, vocabulary: vocabulary),
                                    queryHistory: CommandPaletteHistoryStore(context: container.mainContext),
                                    settings: settings, speech: speech)
    }
}

@MainActor private final class TestAnalysisService: LanguageAnalyzing {
    var requests: [AnalysisRequest] = []
    var suspend = false
    var finished = false
    var error: AppError?
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

@MainActor private final class TestSpeech: FrenchSpeaking {
    var spoken: [String] = []
    func speak(_ text: String) throws { spoken.append(text) }
    func stop() {}
}

@MainActor private final class UnusedKeyStore: APIKeyStore {
    func load() throws -> String? { throw AppError.keychain }
    func save(_ key: String) throws { throw AppError.keychain }
    func delete() throws {}
}

private actor CountingProvider: LanguageModelProvider {
    var count = 0
    let analysis: FrenchAnalysis
    init(analysis: FrenchAnalysis) { self.analysis = analysis }
    func analyze(_ request: AnalysisRequest) async throws -> FrenchAnalysis { count += 1; return analysis }
    func testConnection() async throws {}
}
