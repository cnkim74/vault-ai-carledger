import Foundation
import AVFoundation

/// 답변 음성 읽어주기 (TTS). 기기 언어에 맞는 음성으로 재생.
@MainActor
final class Speaker: NSObject, ObservableObject, AVSpeechSynthesizerDelegate {
    @Published var speakingID: UUID?
    private let synth = AVSpeechSynthesizer()

    override init() {
        super.init()
        synth.delegate = self
    }

    /// 같은 메시지면 정지, 아니면 재생.
    func toggle(_ id: UUID, text: String) {
        if speakingID == id { stop(); return }
        stop()
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .spokenAudio, options: .duckOthers)
        try? AVAudioSession.sharedInstance().setActive(true)
        let u = AVSpeechUtterance(string: text)
        u.voice = AVSpeechSynthesisVoice(language: Self.voiceLang)
        u.rate = AVSpeechUtteranceDefaultSpeechRate
        speakingID = id
        synth.speak(u)
    }

    func stop() {
        if synth.isSpeaking { synth.stopSpeaking(at: .immediate) }
        speakingID = nil
    }

    private static var voiceLang: String {
        switch AppLocale.languageCode.prefix(2) {
        case "en": return "en-US"
        case "ja": return "ja-JP"
        case "zh": return "zh-CN"
        default: return "ko-KR"
        }
    }

    nonisolated func speechSynthesizer(_ s: AVSpeechSynthesizer, didFinish u: AVSpeechUtterance) {
        Task { @MainActor in speakingID = nil }
    }
    nonisolated func speechSynthesizer(_ s: AVSpeechSynthesizer, didCancel u: AVSpeechUtterance) {
        Task { @MainActor in speakingID = nil }
    }
}
