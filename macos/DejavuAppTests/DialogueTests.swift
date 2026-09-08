import SwiftData
import Speech
import XCTest
@testable import DejavuApp

@MainActor final class DialogueTests: XCTestCase {
    func testAppearancePersistsWithoutChangingIntegrations() throws {
        let h = try Harness()
        XCTAssertEqual(h.settings.accent, .lavender)
        XCTAssertTrue(h.settings.playfulDetails)
        try h.settings.updateAppearance(accent: .ocean, playfulDetails: false)
        let reload = try SettingsStore(context: h.container.mainContext)
        XCTAssertEqual(reload.accent, .ocean)
        XCTAssertFalse(reload.playfulDetails)
        XCTAssertFalse(reload.clipboardEnabled)
        XCTAssertFalse(reload.bridgeEnabled)
        XCTAssertFalse(reload.dialogueEnabled)
    }

    func testCollectionsScopeDialogueAndKeepItsOriginalThemeWhenSaving() async throws {
        let h = try Harness()
        let fashion = try h.vocabulary.save(PersistenceTests.analysis("une robe"), source: .manual, collection: .fashion)
        _ = try h.vocabulary.save(PersistenceTests.analysis("un billet"), source: .manual, collection: .travel)
        try h.settings.setDialogueCollection(.fashion)
        let reload = try SettingsStore(context: h.container.mainContext)
        XCTAssertEqual(reload.dialogueCollection, .fashion)
        h.model.start(); await settle(h.model)
        XCTAssertEqual(h.service.words, ["une robe"])
        XCTAssertEqual(h.service.contexts.last, VocabularyCollection.fashion.contexts.first)
        try h.settings.setDialogueCollection(.travel)
        h.model.answer = "Oui, merci."
        h.model.submit(); await settle(h.model)
        h.model.savePhrase()
        XCTAssertEqual(try h.vocabulary.find(Self.feedback.usefulPhrase)?.collection, .fashion)
        try h.vocabulary.setCollection(fashion, collection: nil)
        XCTAssertNil(fashion.collection)
        XCTAssertEqual(try h.vocabulary.dialogueVocabulary(collection: .travel), ["un billet"])
    }

    func testMascotCelebratesOnlyExplicitSavesAndCanBeDisabled() throws {
        let h = try Harness()
        XCTAssertNil(h.vocabulary.lastSavedAt)
        try h.vocabulary.recordEncounter(PersistenceTests.analysis("bonjour"), source: .manual)
        XCTAssertNil(h.vocabulary.lastSavedAt)
        try h.vocabulary.save(PersistenceTests.analysis("bonjour"), source: .manual)
        XCTAssertNotNil(h.vocabulary.lastSavedAt)
        try h.settings.setMascotEnabled(false)
        XCTAssertFalse(try SettingsStore(context: h.container.mainContext).mascotEnabled)
    }

    func testOptInDefaultsAndPersistentPause() throws {
        let h = try Harness()
        XCTAssertFalse(h.settings.dialogueEnabled)
        XCTAssertEqual(h.settings.dialogueMinutes, 45)
        XCTAssertThrowsError(try h.settings.updateDialogue(enabled: true, minutes: 0, reuseVocabulary: false))
        try h.settings.updateDialogue(enabled: true, minutes: 30, reuseVocabulary: false)
        let until = Date.now.addingTimeInterval(3600)
        try h.settings.pauseDialogue(until: until)
        let reload = try SettingsStore(context: h.container.mainContext)
        XCTAssertTrue(reload.dialogueEnabled); XCTAssertEqual(reload.dialogueMinutes, 30)
        XCTAssertFalse(reload.dialogueReuseVocabulary); XCTAssertEqual(reload.dialoguePausedUntil, until)
    }
    func testSchedulingRequiresQuietActiveUnlockedSessionAndHonorsPause() {
        let now = Date(timeIntervalSince1970: 100000), due = Date(timeIntervalSince1970: 99999)
        func trigger(enabled: Bool = true, open: Bool = false, safe: Bool = true, idle: Double = 10, pause: Date? = nil) -> Bool {
            DialogueTiming.shouldTrigger(now: now, due: due, pausedUntil: pause, enabled: enabled, isOpen: open, safe: safe, idleSeconds: idle)
        }
        XCTAssertTrue(trigger()); XCTAssertFalse(trigger(enabled: false)); XCTAssertFalse(trigger(open: true))
        XCTAssertFalse(trigger(safe: false)); XCTAssertFalse(trigger(idle: 0)); XCTAssertFalse(trigger(idle: 121))
        XCTAssertFalse(trigger(pause: now.addingTimeInterval(1)))
        XCTAssertTrue(trigger(pause: now))
        XCTAssertEqual(DialogueTiming.next(now: now, minutes: 45, jitter: 0.2).timeIntervalSince(now), 3240, accuracy: 0.01)
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        XCTAssertEqual(DialogueTiming.tomorrow(now: now, calendar: calendar), Date(timeIntervalSince1970: 172800))
    }
    func testOneScenarioAtATimeRotationAndMemoryBounds() async throws {
        let h = try Harness()
        for _ in 0..<22 { h.model.start(); h.model.start(); await settle(h.model); h.model.close() }
        XCTAssertEqual(h.service.contexts.count, 22)
        XCTAssertEqual(h.service.contexts.prefix(15), ArraySlice(DialogueModel.contexts))
        XCTAssertEqual(h.model.recentQuestions.count, 20)
        XCTAssertEqual(h.service.stretches.filter { $0 }.count, 4)
        h.model.clearMemory(); XCTAssertTrue(h.model.recentQuestions.isEmpty)
    }
    func testFeedbackAndExplicitSaveWithoutHistory() async throws {
        let h = try Harness()
        try h.settings.update(provider: .openAI, model: "example-model", saveHistory: false)
        h.model.start(); await settle(h.model)
        XCTAssertTrue(h.service.answers.isEmpty)
        h.model.answer = "Je reste chez moi."; h.model.submit(); await settle(h.model)
        XCTAssertNotNil(h.model.feedback)
        XCTAssertEqual(try h.container.mainContext.fetchCount(FetchDescriptor<VocabularyEntry>()), 0)
        h.model.savePhrase(); h.model.savePhrase()
        let rows = try h.container.mainContext.fetch(FetchDescriptor<VocabularyEntry>())
        XCTAssertEqual(rows.count, 1); XCTAssertTrue(rows[0].savedByUser)
        XCTAssertEqual(rows[0].source, .conversationGhost); XCTAssertEqual(rows[0].seenCount, 1)
        XCTAssertEqual(try h.container.mainContext.fetchCount(FetchDescriptor<AnalysisHistoryEntry>()), 0)
        h.model.close(); XCTAssertEqual(h.model.answer, ""); XCTAssertNil(h.model.feedback)
    }
    func testCloseDiscardsLateGenerationAndDoesNotAdvanceRotation() async throws {
        let h = try Harness(); h.service.hold = true
        h.model.start()
        for _ in 0..<100 where h.service.waiter == nil { await Task.yield() }
        XCTAssertNotNil(h.service.waiter)
        h.model.close(); h.service.finish()
        for _ in 0..<20 { await Task.yield() }
        XCTAssertNil(h.model.scenario); XCTAssertFalse(h.model.isOpen)
        XCTAssertEqual(h.model.contextIndex, 0)
    }
    func testNoUnrelatedVocabularyOrNotesAndOptOut() async throws {
        let h = try Harness()
        try h.vocabulary.recordEncounter(PersistenceTests.analysis("bonjour"), source: .manual)
        let saved = try h.vocabulary.save(PersistenceTests.analysis("en route"), source: .manual)
        try h.vocabulary.update(saved, saved: true, notes: "example private note")
        h.model.start(); await settle(h.model)
        XCTAssertEqual(h.service.words, ["en route"])
        h.model.close()
        try h.settings.updateDialogue(enabled: false, minutes: 45, reuseVocabulary: false)
        h.model.start(); await settle(h.model); XCTAssertTrue(h.service.words.isEmpty)
    }
    func testDuplicateAndInvalidResponsesAreRejected() async throws {
        let h = try Harness(); h.service.repeatQuestion = true
        h.model.start(); await settle(h.model); h.model.close()
        h.model.start(); await settle(h.model)
        XCTAssertNotNil(h.model.errorMessage); XCTAssertNil(h.model.scenario)
        XCTAssertThrowsError(try DialogueScenario(situation: "", question: "bonjour").validated())
        XCTAssertThrowsError(try DialogueScenario(situation: "Приветствие", question: String(repeating: "a", count: 401)).validated())
    }
    func testServiceUsesStrictSchemaEphemeralRequestsAndBoundedContext() async throws {
        let h = try Harness()
        let transport = DialogueTransport(payload: try JSONEncoder().encode(DialogueScenario(situation: "Встреча", question: "Ça va ?")))
        let service = DialogueService(settings: h.settings, keychain: DialogueKey(), transport: transport)
        _ = try await service.scenario(context: "друг", recent: Array(repeating: "Ça va ?", count: 30), vocabulary: Array(repeating: "en route", count: 10), stretch: false)
        let captured = await transport.request
        let request = try XCTUnwrap(captured)
        XCTAssertEqual(request.url?.absoluteString, "https://api.openai.com/v1/responses")
        let body = try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap(request.httpBody)) as? [String: Any])
        XCTAssertEqual(body["store"] as? Bool, false)
        let input = try XCTUnwrap(body["input"] as? String)
        let payload = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(input.utf8)) as? [String: Any])
        XCTAssertEqual((payload["recentQuestions"] as? [String])?.count, 20)
        XCTAssertEqual((payload["optionalVocabulary"] as? [String])?.count, 5)
        let format = try XCTUnwrap((body["text"] as? [String: Any])?["format"] as? [String: Any])
        XCTAssertEqual(format["strict"] as? Bool, true)
        XCTAssertEqual(format["name"] as? String, "dialogue_scenario")
        XCTAssertEqual((format["schema"] as? [String: Any])?["additionalProperties"] as? Bool, false)
    }
    func testFeedbackSchemaAndInputValidation() async throws {
        let h = try Harness()
        let transport = DialogueTransport(payload: try JSONEncoder().encode(Self.feedback))
        let service = DialogueService(settings: h.settings, keychain: DialogueKey(), transport: transport)
        let scenario = DialogueScenario(situation: "Планы", question: "Tu fais quoi ?")
        do { _ = try await service.feedback(scenario: scenario, answer: " "); XCTFail("Empty answer accepted") } catch { XCTAssertEqual(error as? AppError, .invalidInput) }
        let value = try await service.feedback(scenario: scenario, answer: "Je reste ici.")
        XCTAssertTrue(value.isNatural); XCTAssertNil(value.correctedVersion)
        let captured = await transport.request
        let body = try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap(captured?.httpBody)) as? [String: Any])
        let input = try XCTUnwrap(body["input"] as? String)
        XCTAssertTrue(input.contains("Je reste ici.")); XCTAssertFalse(input.contains("optionalVocabulary"))
    }
    func testSpeechPermissionReplyCanArriveOnBackgroundQueue() async {
        let status = await DialogueVoice.requestSpeechAuthorization { reply in
            DispatchQueue.global().async { reply(.authorized) }
        }
        XCTAssertEqual(status, .authorized)
    }
    func testFrenchPhraseCannotContainEmbeddedRussianTranslation() throws {
        let bad = DialogueFeedback(understood: true, isNatural: true, correctedVersion: nil, moreNaturalVersion: nil,
            mainIssue: nil, usefulPhrase: "Je viens. — Я приду.", usefulTranslation: "Я приду.", encouragement: "Понятно.")
        XCTAssertThrowsError(try bad.validated())
        XCTAssertNoThrow(try Self.feedback.validated())
    }
    func testWelcomeCompletionDoesNotEnableOptionalFeatures() throws {
        let h = try Harness()
        XCTAssertFalse(h.settings.welcomeCompleted)
        try h.settings.completeWelcome()
        let reload = try SettingsStore(context: h.container.mainContext)
        XCTAssertTrue(reload.welcomeCompleted)
        XCTAssertFalse(reload.dialogueEnabled)
        XCTAssertFalse(reload.clipboardEnabled)
        XCTAssertFalse(reload.bridgeEnabled)
    }
    func testVoiceStartsInactiveAndClearDoesNotRequestPermissions() {
        let voice = DialogueVoice()
        XCTAssertFalse(voice.recording); XCTAssertFalse(voice.requesting)
        voice.transcript = "Bonjour"; voice.clear()
        XCTAssertEqual(voice.transcript, ""); XCTAssertFalse(voice.recording)
    }
    private func settle(_ model: DialogueModel) async {
        for _ in 0..<500 where model.isLoading { await Task.yield() }
        XCTAssertFalse(model.isLoading)
    }
    static var feedback: DialogueFeedback {
        DialogueFeedback(understood: true, isNatural: true, correctedVersion: nil, moreNaturalVersion: nil,
            mainIssue: nil, usefulPhrase: "rester chez soi", usefulTranslation: "остаться дома", encouragement: "Ответ понятен.")
    }
}

@MainActor private final class Harness {
    let container: ModelContainer
    let settings: SettingsStore
    let vocabulary: VocabularyStore
    let service = FakeDialogue()
    let model: DialogueModel
    init() throws {
        container = try PersistenceController.makeContainer(inMemory: true)
        settings = try SettingsStore(context: container.mainContext)
        vocabulary = VocabularyStore(context: container.mainContext)
        model = DialogueModel(service: service, vocabulary: vocabulary, settings: settings)
    }
}
@MainActor private final class FakeDialogue: DialogueServing {
    var contexts: [String] = [], stretches: [Bool] = [], words: [String] = [], answers: [String] = []
    var repeatQuestion = false, hold = false
    var waiter: CheckedContinuation<DialogueScenario, Never>?
    func scenario(context: String, recent: [String], vocabulary: [String], stretch: Bool) async throws -> DialogueScenario {
        contexts.append(context); stretches.append(stretch); words = vocabulary
        if hold { return await withCheckedContinuation { waiter = $0 } }
        return DialogueScenario(situation: "С другом", question: repeatQuestion ? "Ça va ?" : "Tu viens à \(contexts.count) heures ?")
    }
    func feedback(scenario: DialogueScenario, answer: String) async throws -> DialogueFeedback {
        answers.append(answer); return DialogueTests.feedback
    }
    func finish() { waiter?.resume(returning: DialogueScenario(situation: "Встреча", question: "Ça va ?")); waiter = nil }
}
@MainActor private final class DialogueKey: APIKeyStore {
    func load() throws -> String? { "placeholder" }
    func save(_ key: String) throws {}
    func delete() throws {}
}
private actor DialogueTransport: HTTPTransport {
    var request: URLRequest?
    let payload: Data
    init(payload: Data) { self.payload = payload }
    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        self.request = request
        let data = try JSONSerialization.data(withJSONObject: ["status": "completed", "output": [["type": "message", "content": [["type": "output_text", "text": String(decoding: payload, as: UTF8.self)]]]]])
        return (data, HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
    }
}
