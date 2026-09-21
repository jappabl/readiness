import AVFoundation
import Foundation
import Speech

/// The microphone inside the logging screen.
///
/// Siri already logs a set from across the room; this is for when the phone is in your
/// hand between sets and typing three fields with chalk on your fingers is the worst
/// part of the app. It only ever hands back a transcript: `SpokenSetResolver` decides
/// what that means, so speaking and saying it to Siri cannot disagree.
///
/// Recognition is forced on-device where the phone supports it. What somebody grunts
/// between sets is not worth sending to Apple's servers, and on-device has no minute
/// limit, which a set-by-set logger would otherwise hit inside one session.
@Observable
@MainActor
final class Dictation {

    enum Status: Equatable {
        case idle
        case listening
        /// Permission was refused, or the phone cannot do this. Both are dead ends the
        /// user has to resolve in Settings, so they read the same on screen.
        case unavailable(String)
    }

    private(set) var status: Status = .idle
    /// Updates as the words arrive, so the user can see they are being heard.
    private(set) var transcript = ""

    var isListening: Bool { status == .listening }

    private let recogniser = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
    private let engine = AVAudioEngine()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?

    /// Everything that can refuse is asked for before a single buffer is captured, so a
    /// tap either starts listening or says why it cannot.
    func start() async {
        guard !isListening else { return }
        transcript = ""

        guard let recogniser, recogniser.isAvailable else {
            status = .unavailable("Speech recognition isn’t available on this phone.")
            return
        }
        guard await authorised() else {
            status = .unavailable("Jett needs the microphone and speech recognition. Turn them on in Settings.")
            return
        }

        do {
            try beginCapturing(with: recogniser)
            status = .listening
        } catch {
            teardown()
            status = .unavailable("The microphone couldn’t start.")
        }
    }

    /// Stops listening and hands back the final transcript. Empty when nothing was said.
    @discardableResult
    func stop() -> String {
        guard isListening else { return transcript }
        teardown()
        status = .idle
        return transcript
    }

    /// Clears a refusal so the button reads as tappable again after a trip to Settings.
    func reset() {
        if case .unavailable = status { status = .idle }
    }

    // MARK: - The machinery

    private func authorised() async -> Bool {
        let speech = await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { continuation.resume(returning: $0) }
        }
        guard speech == .authorized else { return false }
        return await AVAudioApplication.requestRecordPermission()
    }

    private func beginCapturing(with recogniser: SFSpeechRecognizer) throws {
        let session = AVAudioSession.sharedInstance()
        // .record rather than .playAndRecord: nothing here plays, and asking for
        // playback would duck whatever the user is listening to while they lift.
        try session.setCategory(.record, mode: .measurement, options: .duckOthers)
        try session.setActive(true, options: .notifyOthersOnDeactivation)

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        request.requiresOnDeviceRecognition = recogniser.supportsOnDeviceRecognition
        self.request = request

        let input = engine.inputNode
        input.installTap(onBus: 0, bufferSize: 1024, format: input.outputFormat(forBus: 0)) {
            [request] buffer, _ in
            request.append(buffer)
        }
        engine.prepare()
        try engine.start()

        task = recogniser.recognitionTask(with: request) { [weak self] result, error in
            guard let self else { return }
            Task { @MainActor in
                if let result {
                    self.transcript = result.bestTranscription.formattedString
                }
                // A recogniser that gives up mid-set keeps whatever it heard: the user
                // is about to see it and decide, so a partial line beats an empty one.
                if error != nil || result?.isFinal == true, self.isListening {
                    self.teardown()
                    self.status = .idle
                }
            }
        }
    }

    private func teardown() {
        engine.inputNode.removeTap(onBus: 0)
        if engine.isRunning { engine.stop() }
        request?.endAudio()
        task?.cancel()
        request = nil
        task = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }
}
