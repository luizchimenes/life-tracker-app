#if os(iOS)
import AVFoundation
import Foundation
import Observation
import Speech

/// Records one spoken phrase and transcribes it in Brazilian Portuguese.
///
/// Recognition runs on device. If the device cannot recognize pt-BR locally,
/// it reports `.onDeviceUnavailable` and uses Apple's servers only after the
/// user explicitly allows it for this session. Audio is never written to disk
/// and transcripts are not kept after the flow ends.
@MainActor
@Observable
final class VoiceTransactionService {
    enum State: Equatable {
        case idle
        case requestingPermission
        case listening
        case finished
        case failed(Failure)
    }

    enum Failure: Equatable {
        case speechDenied
        case microphoneDenied
        case restricted
        case recognizerUnavailable
        case onDeviceUnavailable
        case dictationDisabled
        case nothingHeard
        case audio(String)
        case recognition(String)
    }

    static let locale = Locale(identifier: "pt-BR")

    private(set) var state = State.idle
    private(set) var transcript = ""
    /// The user agreed to send this session's audio to Apple for recognition.
    private(set) var allowsServerRecognition = false

    private let recognizer = SFSpeechRecognizer(locale: VoiceTransactionService.locale)
    private let capture = AudioCapture()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private var silenceTimer: Task<Void, Never>?
    private var interruptionObserver: NSObjectProtocol?

    func allowServerRecognition() {
        allowsServerRecognition = true
    }

    func start() async {
        guard state != .listening, state != .requestingPermission else { return }
        transcript = ""
        state = .requestingPermission

        if let failure = await requestPermissions() {
            state = .failed(failure)
            return
        }
        guard let recognizer, recognizer.isAvailable else {
            state = .failed(.recognizerUnavailable)
            return
        }
        guard recognizer.supportsOnDeviceRecognition || allowsServerRecognition else {
            state = .failed(.onDeviceUnavailable)
            return
        }

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        request.requiresOnDeviceRecognition = recognizer.supportsOnDeviceRecognition
        request.addsPunctuation = true
        request.taskHint = .dictation
        self.request = request

        do {
            // Audio session and engine work happens off the main thread.
            try await capture.start(feeding: request)
        } catch {
            teardown()
            state = .failed(.audio(error.localizedDescription))
            return
        }

        state = .listening
        task = recognizer.recognitionTask(with: request, resultHandler: Self.resultHandler(for: self))
        observeInterruptions()
    }

    /// Stops listening and keeps what was recognized.
    func stop() {
        guard state == .listening else { return }
        request?.endAudio()
        finish()
    }

    /// Stops listening and discards the transcript.
    func cancel() {
        task?.cancel()
        teardown()
        transcript = ""
        state = .idle
    }

    // MARK: Permissions

    private func requestPermissions() async -> Failure? {
        switch await Self.speechAuthorization() {
        case .authorized: break
        case .denied: return .speechDenied
        case .restricted: return .restricted
        case .notDetermined: return .speechDenied
        @unknown default: return .speechDenied
        }
        guard await AVAudioApplication.requestRecordPermission() else {
            return .microphoneDenied
        }
        return nil
    }

    /// The callback arrives on a background queue, so it is built off the main actor.
    private nonisolated static func speechAuthorization() async -> SFSpeechRecognizerAuthorizationStatus {
        await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { continuation.resume(returning: $0) }
        }
    }

    // MARK: Recognition

    private nonisolated static func resultHandler(
        for service: VoiceTransactionService
    ) -> (SFSpeechRecognitionResult?, Error?) -> Void {
        { [weak service] result, error in
            let text = result?.bestTranscription.formattedString
            let isFinal = result?.isFinal ?? false
            let failure = error.map { classify($0 as NSError) }
            Task { @MainActor [service] in
                service?.handle(text: text, isFinal: isFinal, failure: failure)
            }
        }
    }

    /// Turns recognizer errors into something the user can act on instead of
    /// a silent "nothing was heard".
    private nonisolated static func classify(_ error: NSError) -> Failure {
        let description = error.localizedDescription
        if (error.domain == "kLSRErrorDomain" && error.code == 201)
            || description.localizedCaseInsensitiveContains("dictation") {
            return .dictationDisabled
        }
        if error.domain == "kAFAssistantErrorDomain" && error.code == 1110 {
            return .nothingHeard
        }
        return .recognition("\(description) (\(error.domain) \(error.code))")
    }

    private func handle(text: String?, isFinal: Bool, failure: Failure?) {
        guard state == .listening else { return }
        if let text, !text.isEmpty {
            transcript = text
            scheduleSilenceStop()
        }
        if let failure, transcript.isEmpty {
            teardown()
            state = .failed(failure)
        } else if isFinal || failure != nil {
            finish()
        }
    }

    /// Ends the phrase after a short pause so the user need not tap Stop.
    private func scheduleSilenceStop() {
        silenceTimer?.cancel()
        silenceTimer = Task { [weak self] in
            try? await Task.sleep(for: .seconds(1.8))
            guard !Task.isCancelled else { return }
            self?.stop()
        }
    }

    private func finish() {
        teardown()
        let text = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        state = text.isEmpty ? .failed(.nothingHeard) : .finished
    }

    private func observeInterruptions() {
        interruptionObserver = NotificationCenter.default.addObserver(
            forName: AVAudioSession.interruptionNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            let service = self
            Task { @MainActor in service?.stop() }
        }
    }

    private func teardown() {
        silenceTimer?.cancel()
        silenceTimer = nil
        request?.endAudio()
        request = nil
        task?.finish()
        task = nil
        capture.stop()
        if let interruptionObserver {
            NotificationCenter.default.removeObserver(interruptionObserver)
        }
        interruptionObserver = nil
    }
}

/// Owns the microphone. Every audio-session and engine call runs on one serial
/// background queue: off the main thread (no UI stalls) and in order, so a
/// stop always completes before the next start.
private nonisolated final class AudioCapture: @unchecked Sendable {
    private let engine = AVAudioEngine()
    private let queue = DispatchQueue(label: "LifeTracker.VoiceAudioCapture", qos: .userInitiated)

    struct NoInputError: LocalizedError {
        var errorDescription: String? { "No microphone input is available." }
    }

    /// The request is only appended to from the tap, which Speech supports
    /// from any thread.
    private struct RequestBox: @unchecked Sendable {
        let request: SFSpeechAudioBufferRecognitionRequest
    }

    func start(feeding request: SFSpeechAudioBufferRecognitionRequest) async throws {
        let box = RequestBox(request: request)
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            queue.async { [engine] in
                do {
                    let session = AVAudioSession.sharedInstance()
                    try session.setCategory(.record, mode: .measurement, options: .duckOthers)
                    try session.setActive(true, options: .notifyOthersOnDeactivation)

                    let input = engine.inputNode
                    let format = input.outputFormat(forBus: 0)
                    guard format.sampleRate > 0, format.channelCount > 0 else {
                        throw NoInputError()
                    }
                    // iOS 27 replaces the non-throwing installTap; its
                    // error-reporting form is exposed to Swift under this name.
                    try input.__installTap(onBus: 0, bufferSize: 4_096, format: format, error: ()) { buffer, _ in
                        box.request.append(buffer)
                    }
                    engine.prepare()
                    try engine.start()
                    continuation.resume()
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    func stop() {
        queue.async { [engine] in
            if engine.isRunning {
                engine.stop()
            }
            engine.inputNode.removeTap(onBus: 0)
            try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        }
    }
}
#endif
