import Foundation
import Observation
@preconcurrency import Speech
@preconcurrency import AVFoundation

// Apple expects append to be called from the audio render callback, not the main actor.
private final class SpeechBufferSink: @unchecked Sendable {
    let request: SFSpeechAudioBufferRecognitionRequest
    init(_ request: SFSpeechAudioBufferRecognitionRequest) { self.request = request }
}

@MainActor @Observable final class DialogueVoice {
    private let engine = AVAudioEngine()
    private var recognition: SFSpeechRecognitionTask?
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var timeout: Task<Void, Never>?
    private var generation = UUID()
    private var hasTap = false
    private(set) var recording = false
    private(set) var requesting = false
    var transcript = ""
    var errorMessage: String?

    var permissionDescription: String {
        if requesting { return "Ожидаем ответ на запрос разрешений macOS…" }
        let microphone = AVCaptureDevice.authorizationStatus(for: .audio)
        let speech = SFSpeechRecognizer.authorizationStatus()
        if microphone == .denied || microphone == .restricted { return "Доступ к микрофону закрыт. Можно написать ответ или изменить разрешение в macOS." }
        if speech == .denied || speech == .restricted { return "Распознавание речи запрещено в macOS. Письменный ответ доступен." }
        if microphone == .authorized && speech == .authorized { return "Разрешения выданы. Локальное распознавание fr-FR проверяется при начале записи." }
        return "Разрешения будут запрошены только после нажатия «Ответить голосом»."
    }

    // Speech delivers permission on an arbitrary queue. Keep the bridge nonisolated;
    // only the resumed start() task may touch UI/engine state on MainActor.
    nonisolated static func requestSpeechAuthorization(
        using requester: @Sendable (@escaping @Sendable (SFSpeechRecognizerAuthorizationStatus) -> Void) -> Void = {
            SFSpeechRecognizer.requestAuthorization($0)
        }
    ) async -> SFSpeechRecognizerAuthorizationStatus {
        await withCheckedContinuation { continuation in
            requester { @Sendable status in continuation.resume(returning: status) }
        }
    }

    // Called only from the explicit voice button. A close while permission is pending invalidates the start.
    func start() async {
        guard !recording, !requesting else { return }
        stop(); let token = generation
        requesting = true; errorMessage = nil; transcript = ""
        let speechStatus = await Self.requestSpeechAuthorization()
        guard generation == token else { return }
        guard speechStatus == .authorized else {
            requesting = false; errorMessage = "Разрешите распознавание речи в настройках конфиденциальности macOS или напишите ответ."; return
        }
        let microphone = await AVCaptureDevice.requestAccess(for: .audio)
        guard generation == token else { return }
        requesting = false
        guard microphone else { errorMessage = "Нет доступа к микрофону. Разрешите его в настройках macOS или напишите ответ."; return }
        guard let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "fr-FR")), recognizer.isAvailable,
              recognizer.supportsOnDeviceRecognition else {
            errorMessage = "Локальное распознавание французского недоступно. Проверьте загрузку французского языка для диктовки в macOS или напишите ответ."; return
        }
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.requiresOnDeviceRecognition = true
        request.shouldReportPartialResults = true
        self.request = request
        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else {
            errorMessage = "Микрофон недоступен. Проверьте устройство ввода."; self.request = nil; return
        }
        let sink = SpeechBufferSink(request)
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { @Sendable buffer, _ in sink.request.append(buffer) }
        hasTap = true
        recognition = recognizer.recognitionTask(with: request) { @Sendable [weak self] result, error in
            let text = result?.bestTranscription.formattedString
            let final = result?.isFinal == true
            let failed = error != nil
            Task { @MainActor [weak self] in
                guard let self, generation == token else { return }
                if let text { transcript = String(text.prefix(2000)) }
                if final || failed {
                    stop()
                    if failed && transcript.isEmpty { errorMessage = "Не удалось распознать речь. Попробуйте ещё раз или напишите ответ." }
                }
            }
        }
        do { engine.prepare(); try engine.start(); recording = true }
        catch { stop(); errorMessage = "Не удалось включить микрофон. Проверьте устройство ввода."; return }
        timeout = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(60)) } catch { return }
            self?.stop()
        }
    }
    func stop() {
        generation = UUID(); requesting = false; recording = false
        timeout?.cancel(); timeout = nil
        engine.stop()
        if hasTap { engine.inputNode.removeTap(onBus: 0); hasTap = false }
        request?.endAudio(); recognition?.cancel(); recognition = nil; request = nil
    }
    func clear() { stop(); transcript = ""; errorMessage = nil }
}
