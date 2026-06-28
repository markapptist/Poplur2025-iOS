import Foundation
import AVFoundation

/// Speaks camera-AI events: recognized user name + radius, and ML vision labels.
@MainActor
final class CameraAIAnnouncer: NSObject, AVSpeechSynthesizerDelegate {
    static let shared = CameraAIAnnouncer()

    private let synth = AVSpeechSynthesizer()
    private var lastSpokenUsername: String?
    private var lastMLSignature: String?
    private var lastMLTime: Date = .distantPast
    private let mlCooldown: TimeInterval = 2.2

    override init() {
        super.init()
        synth.delegate = self
    }

    /// Speak the recognized user's name, radius, and post count.
    /// Deduplicates — won't repeat the same username until clearLastUser() is called.
    func announceRecognizedUser(_ user: RecognizedUser) {
        guard user.profile.username != lastSpokenUsername else { return }
        lastSpokenUsername = user.profile.username
        let posts = user.postCount == 1 ? "1 post" : "\(user.postCount) posts"
        speak("\(user.nameForSpeech). Username \(user.profile.username). Current radius \(user.formattedRadius). \(posts).")
    }

    func clearLastUser() {
        lastSpokenUsername = nil
    }

    func resetSession() {
        lastSpokenUsername = nil
        lastMLSignature = nil
        lastMLTime = .distantPast
        synth.stopSpeaking(at: .immediate)
    }

    /// Speak the strongest live ML vision labels as one concise observation.
    func announceMLObjects(_ objects: [DetectedObject]) {
        let labels = objects
            .filter { $0.confidence >= 0.18 }
            .sorted { $0.confidence > $1.confidence }
            .map { cleanLabel($0.identifier) }
            .reduce(into: [String]()) { partial, label in
                guard !label.isEmpty,
                      !partial.contains(where: { $0.caseInsensitiveCompare(label) == .orderedSame })
                else { return }
                partial.append(label)
            }
            .prefix(2)

        announceMLLabels(Array(labels))
    }

    /// Speak an ML vision detection label. Rate-limited and deduplicated.
    func announceMLLabel(_ label: String) {
        announceMLLabels([cleanLabel(label)])
    }

    private func announceMLLabels(_ labels: [String]) {
        let labels = labels.filter { !$0.isEmpty }
        guard !labels.isEmpty else { return }

        let now = Date()
        guard now.timeIntervalSince(lastMLTime) > mlCooldown else { return }
        let signature = labels.map { $0.lowercased() }.joined(separator: "|")
        guard signature != lastMLSignature else { return }
        lastMLSignature = signature
        lastMLTime = now

        let phrase: String
        if labels.count == 1 {
            phrase = "I see \(labels[0])."
        } else {
            phrase = "I see \(labels.dropLast().joined(separator: ", ")) and \(labels.last!)."
        }
        speak(phrase)
    }

    private func cleanLabel(_ label: String) -> String {
        label
            .replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: "-", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func speak(_ text: String) {
        synth.stopSpeaking(at: .word)
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = AVSpeechSynthesisVoice(language: "en-US")
        utterance.rate = 0.52
        utterance.pitchMultiplier = 1.05
        utterance.volume = 0.9
        synth.speak(utterance)
    }
}
