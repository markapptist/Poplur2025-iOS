import AVFoundation
import Foundation

@main
struct SplashPlaybackCheck {
    @MainActor static func main() async throws {
        func require(_ condition: Bool, _ message: String) {
            guard condition else { fatalError(message) }
            print("PASS: \(message)")
        }
        let missing = SplashPlayback(url: nil)
        require(missing.hasFinished, "missing video falls through safely")
        missing.stop()
        let playback = SplashPlayback(url: URL(fileURLWithPath: CommandLine.arguments[1]))
        // Reproduce delayed AVFoundation startup past the former dismissal timer.
        try await Task.sleep(for: .milliseconds(3400))
        require(!playback.hasFinished && playback.elapsed == 0, "startup delay cannot truncate the intro")
        playback.setActive(true)
        for _ in 0..<100 {
            if playback.elapsed > 0.35 { break }
            try await Task.sleep(for: .milliseconds(50))
        }
        require(playback.elapsed > 0.35 && !playback.hasFinished, "real bundled video begins playing")
        let interruptedAt = playback.elapsed
        playback.player.pause() // An audio-session interruption, without a scene change.
        for _ in 0..<60 {
            if playback.elapsed > interruptedAt + 0.15 { break }
            try await Task.sleep(for: .milliseconds(50))
        }
        require(playback.elapsed > interruptedAt + 0.15 && !playback.hasFinished, "a paused active decoder resumes instead of freezing or skipping the clip")
        playback.setActive(false)
        try await Task.sleep(for: .milliseconds(200))
        let pausedAt = playback.elapsed
        try await Task.sleep(for: .milliseconds(3400))
        require(!playback.hasFinished && abs(playback.elapsed - pausedAt) < 0.1, "background pause cannot dismiss or advance the intro")
        playback.setActive(true)
        for _ in 0..<120 {
            if playback.hasFinished { break }
            try await Task.sleep(for: .milliseconds(50))
        }
        require(playback.hasFinished && playback.progress == 1, "completion reaches 100 percent")
        let duration = playback.player.currentItem!.duration.seconds
        require(playback.player.currentTime().seconds >= duration - 0.1, "completion occurs only after the actual final frame")
        let endTime = playback.player.currentTime().seconds
        playback.setActive(false)
        playback.setActive(true)
        try await Task.sleep(for: .milliseconds(300))
        require(abs(playback.player.currentTime().seconds - endTime) < 0.1, "finished video holds its final frame without looping")
        playback.stop()
        require(playback.player.currentItem == nil, "dismissal releases the video")

        let stalled = SplashPlayback(url: URL(fileURLWithPath: CommandLine.arguments[1]), recoveryDelay: 0.2, stallLimit: 0.8)
        stalled.setActive(true)
        stalled.player.replaceCurrentItem(with: nil) // Decoder is lost; no end notification can arrive.
        for _ in 0..<40 {
            if stalled.hasFinished { break }
            try await Task.sleep(for: .milliseconds(50))
        }
        require(stalled.hasFinished, "unrecoverable decoder loss has a bounded exit")
        stalled.stop()
    }
}
