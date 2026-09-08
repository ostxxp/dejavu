import SwiftData
import XCTest
@testable import DejavuApp

@MainActor final class PersistenceTests: XCTestCase {
    func testAutomaticCollectionPreservesManualChoiceAndSupportsOldAnalysis() throws {
        let container = try PersistenceController.makeContainer(inMemory: true)
        let store = VocabularyStore(context: container.mainContext)
        var analysis = Self.analysis("une robe")
        analysis.suggestedCollection = "fashion"
        let entry = try store.save(analysis, source: .chromePopup)
        XCTAssertEqual(entry.collection, .fashion)
        try store.setCollection(entry, collection: .dates)
        _ = try store.save(analysis, source: .manual)
        XCTAssertEqual(entry.collection, .dates)
        try store.setCollection(entry, collection: nil)
        _ = try store.save(analysis, source: .manual)
        XCTAssertNil(entry.collection)
        var legacy = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(analysis)) as? [String: Any])
        legacy.removeValue(forKey: "suggestedCollection")
        let decoded = try JSONDecoder().decode(FrenchAnalysis.self, from: JSONSerialization.data(withJSONObject: legacy))
        XCTAssertNil(decoded.suggestedCollection)
        analysis.original = "un billet"
        analysis.suggestedCollection = "travel"
        let history = try store.recordEncounter(analysis, source: .manual)
        try store.update(history, saved: true, notes: "")
        XCTAssertEqual(history.collection, .travel)
        analysis.original = "bonjour"
        analysis.suggestedCollection = "invalid"
        XCTAssertNil(try store.save(analysis, source: .manual).collection)
    }

    func testNormalizationPreservesFrenchSpelling() {
        XCTAssertEqual(ExpressionNormalizer.normalize("  L’ANNÉE\n prochaine  "), "l'année prochaine")
        XCTAssertEqual(ExpressionNormalizer.normalize("e\u{301}te\u{301}"), "été")
        XCTAssertNotEqual(ExpressionNormalizer.normalize("a"), ExpressionNormalizer.normalize("à"))
        XCTAssertNotEqual(ExpressionNormalizer.normalize("ou"), ExpressionNormalizer.normalize("où"))
        XCTAssertNotEqual(ExpressionNormalizer.normalize("cœur"), ExpressionNormalizer.normalize("coeur"))
        XCTAssertNotEqual(ExpressionNormalizer.normalize("peut-être"), ExpressionNormalizer.normalize("peut être"))
    }

    func testEncounterDeduplicatesAcrossSourcesAndMergesMetadata() throws {
        let container = try PersistenceController.makeContainer(inMemory: true)
        let store = VocabularyStore(context: container.mainContext)
        var first = Self.analysis("l’année")
        first.ipa = nil
        let early = Date(timeIntervalSince1970: 100)
        let late = Date(timeIntervalSince1970: 200)
        let entry = try store.recordEncounter(first, source: .manual, now: early)
        try store.update(entry, saved: true, notes: "Запомнить артикль")
        var second = Self.analysis(" L'ANNÉE ")
        second.ipa = "/la.ne/"
        let repeated = try store.recordEncounter(second, source: .chromePopup, now: late)
        XCTAssertEqual(entry.id, repeated.id)
        XCTAssertEqual(repeated.seenCount, 2)
        XCTAssertEqual(repeated.createdAt, early)
        XCTAssertEqual(repeated.lastSeenAt, late)
        XCTAssertEqual(repeated.french, "l’année")
        XCTAssertEqual(repeated.ipa, "/la.ne/")
        XCTAssertEqual(repeated.analysis?.ipa, "/la.ne/")
        XCTAssertTrue(repeated.savedByUser)
        XCTAssertEqual(repeated.notes, "Запомнить артикль")
        XCTAssertEqual(try container.mainContext.fetchCount(FetchDescriptor<VocabularyEntry>()), 1)
    }

    func testSavingDoesNotCountAsAnotherEncounter() throws {
        let container = try PersistenceController.makeContainer(inMemory: true)
        let store = VocabularyStore(context: container.mainContext)
        let analysis = Self.analysis()
        _ = try store.recordEncounter(analysis, source: .manual)
        let entry = try store.save(analysis, source: .manual)
        _ = try store.save(analysis, source: .manual)
        XCTAssertEqual(entry.seenCount, 1)
        XCTAssertTrue(entry.savedByUser)
    }

    func testHistoryAndVocabularyShareStorageAndClearPreservesSaved() throws {
        let container = try PersistenceController.makeContainer(inMemory: true)
        let vocabulary = VocabularyStore(context: container.mainContext)
        let history = HistoryStore(context: container.mainContext, vocabulary: vocabulary)
        try history.record(Self.analysis(), source: .manual)
        try history.record(Self.analysis("leurs voitures"), source: .clipboard)
        let saved = try vocabulary.save(Self.analysis(), source: .manual)
        try vocabulary.update(saved, saved: true, notes: "Полезно")
        XCTAssertEqual(try container.mainContext.fetchCount(FetchDescriptor<AnalysisHistoryEntry>()), 2)
        XCTAssertEqual(try container.mainContext.fetchCount(FetchDescriptor<VocabularyEntry>()), 2)
        try history.clear()
        XCTAssertEqual(try container.mainContext.fetchCount(FetchDescriptor<AnalysisHistoryEntry>()), 0)
        XCTAssertEqual(try container.mainContext.fetchCount(FetchDescriptor<VocabularyEntry>()), 1)
        XCTAssertEqual(try vocabulary.find("tu devrais")?.notes, "Полезно")
    }

    func testInvalidAnalysisDoesNotPersist() throws {
        let container = try PersistenceController.makeContainer(inMemory: true)
        let vocabulary = VocabularyStore(context: container.mainContext)
        let history = HistoryStore(context: container.mainContext, vocabulary: vocabulary)
        XCTAssertThrowsError(try history.record(Self.analysis(" \n"), source: .manual))
        XCTAssertEqual(try container.mainContext.fetchCount(FetchDescriptor<AnalysisHistoryEntry>()), 0)
        XCTAssertEqual(try container.mainContext.fetchCount(FetchDescriptor<VocabularyEntry>()), 0)
    }

    func testSettingsAndVocabularySurviveReopeningDiskStore() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("test.store")
        try autoreleasepool {
            let container = try PersistenceController.makeContainer(url: url)
            let settings = try SettingsStore(context: container.mainContext)
            XCTAssertTrue(settings.saveHistory)
            try settings.update(provider: .openAI, model: "gpt-4o-mini", saveHistory: false)
            XCTAssertThrowsError(try settings.update(provider: .openAI, model: " \n", saveHistory: true))
            XCTAssertFalse(settings.saveHistory)
            let vocabulary = VocabularyStore(context: container.mainContext)
            _ = try vocabulary.save(Self.analysis(), source: .manual)
        }
        let reopened = try PersistenceController.makeContainer(url: url)
        let settings = try SettingsStore(context: reopened.mainContext)
        XCTAssertFalse(settings.saveHistory)
        XCTAssertEqual(settings.model, "gpt-4o-mini")
        XCTAssertEqual(try reopened.mainContext.fetchCount(FetchDescriptor<AppSettings>()), 1)
        let entry = try VocabularyStore(context: reopened.mainContext).find("tu devrais")
        XCTAssertTrue(try XCTUnwrap(entry).savedByUser)
        XCTAssertEqual(entry?.analysis, Self.analysis())
    }

    func testMissingKeyFailsWithoutNetwork() async throws {
        let container = try PersistenceController.makeContainer(inMemory: true)
        let service = LanguageAnalysisService(settings: try SettingsStore(context: container.mainContext),
                                              keychain: EmptyKeyStore())
        do {
            _ = try await service.analyze("bonjour")
            XCTFail("Expected a missing-key error")
        } catch {
            XCTAssertEqual(error as? AppError, .missingAPIKey)
        }
    }

    func testKeychainRoundTripInIsolatedNamespace() throws {
        let keychain = KeychainService(service: "com.dejavu.mac.tests." + UUID().uuidString)
        defer { try? keychain.delete() }
        XCTAssertNil(try keychain.load())
        try keychain.save("placeholder")
        XCTAssertEqual(try keychain.load(), "placeholder")
        try keychain.save("replacement")
        XCTAssertEqual(try keychain.load(), "replacement")
        XCTAssertThrowsError(try keychain.save("contains whitespace"))
        XCTAssertEqual(try keychain.load(), "replacement")
        try keychain.delete()
        XCTAssertNil(try keychain.load())
    }

    static func analysis(_ original: String = "tu devrais") -> FrenchAnalysis {
        FrenchAnalysis(original: original, translation: "тебе стоит", ipa: "/ty də.vʁɛ/",
                       lemma: "devoir", partOfSpeech: "глагол", gender: nil, article: nil, plural: nil,
                       verbForm: VerbForm(infinitive: "devoir", tense: "conditionnel présent", person: "2-е лицо, ед. число"),
                       grammar: [], chunks: [], examples: [], difficulty: "A2", naturalnessNotes: nil)
    }
}

@MainActor private final class EmptyKeyStore: APIKeyStore {
    func load() throws -> String? { nil }
    func save(_ key: String) throws { throw AppError.keychain }
    func delete() throws {}
}
