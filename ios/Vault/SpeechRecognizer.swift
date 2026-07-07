import Foundation
import Speech
import AVFoundation

/// 실시간 음성 → 텍스트. 시작/종료 시 오디오 세션을 깔끔히 설정·해제.
@MainActor
final class SpeechRecognizer: ObservableObject {
    @Published var transcript = ""
    @Published var isRecording = false
    @Published var denied = false

    private let recognizer = SFSpeechRecognizer(locale: Locale.current) ?? SFSpeechRecognizer()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private let engine = AVAudioEngine()

    func toggle() { isRecording ? stop() : start() }

    func start() {
        guard !isRecording else { return }
        transcript = ""; denied = false
        Task {
            guard await authorize() else { denied = true; return }
            do {
                try beginSession()
                isRecording = true
            } catch {
                cleanup()
                isRecording = false
            }
        }
    }

    /// 녹음 종료 — 엔진·탭·세션을 명확히 정리해 잔여 소리/버퍼가 없도록.
    func stop() {
        guard isRecording else { return }
        request?.endAudio()
        cleanup()
        isRecording = false
    }

    private func cleanup() {
        if engine.isRunning { engine.stop() }
        engine.inputNode.removeTap(onBus: 0)
        task?.cancel(); task = nil
        request = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    private func authorize() async -> Bool {
        let sp = await withCheckedContinuation { c in
            SFSpeechRecognizer.requestAuthorization { c.resume(returning: $0) }
        }
        guard sp == .authorized else { return false }
        return await AVAudioApplication.requestRecordPermission()
    }

    private func beginSession() throws {
        cleanup()
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.record, mode: .measurement, options: .duckOthers)
        try session.setActive(true, options: .notifyOthersOnDeactivation)

        let req = SFSpeechAudioBufferRecognitionRequest()
        req.shouldReportPartialResults = true
        request = req

        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in
            req.append(buffer)
        }
        engine.prepare()
        try engine.start()

        task = recognizer?.recognitionTask(with: req) { [weak self] result, error in
            guard let self else { return }
            if let result {
                let text = result.bestTranscription.formattedString
                Task { @MainActor in self.transcript = text }
            }
            if error != nil || (result?.isFinal ?? false) {
                Task { @MainActor in if self.isRecording { self.stop() } }
            }
        }
    }
}
