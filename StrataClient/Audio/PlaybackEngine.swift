import AVFAudio
import Foundation
import Observation

// MARK: - PlaybackEngine
// Nota: deinit no es compatible con @MainActor en Swift 5.9.
// Llama stop() explicitamente antes de soltar la referencia para liberar el engine.

@Observable
@MainActor
final class PlaybackEngine {

    // MARK: - Public State

    var currentTime: TimeInterval = 0
    var duration: TimeInterval = 0
    var isPlaying: Bool = false
    var pitchSemitones: Int = 0         // Plan 02 implementa el setter
    var loopStart: TimeInterval? = nil  // Plan 03 implementa la logica
    var loopEnd: TimeInterval? = nil    // Plan 03 implementa la logica

    // MARK: - Private Audio Graph

    private let engine = AVAudioEngine()
    private var players: [AVAudioPlayerNode] = []
    private var stemMixers: [AVAudioMixerNode] = []
    private let preMixNode = AVAudioMixerNode()
    private let timePitchNode = AVAudioUnitTimePitch()
    private var stemFiles: [AVAudioFile] = []

    // MARK: - Private State

    private var seekOffset: TimeInterval = 0
    private var updateTimer: Timer?

    // MARK: - Public API

    func load(stemURLs: [URL]) throws {
        if engine.isRunning {
            stop()
        }

        players = (0..<stemURLs.count).map { _ in AVAudioPlayerNode() }
        stemMixers = (0..<stemURLs.count).map { _ in AVAudioMixerNode() }
        stemFiles = try stemURLs.map { try AVAudioFile(forReading: $0) }

        duration = stemFiles.map {
            Double($0.length) / $0.processingFormat.sampleRate
        }.max() ?? 0

        guard let format = stemFiles.first?.processingFormat else { return }

        for player in players { engine.attach(player) }
        for mixer in stemMixers { engine.attach(mixer) }
        engine.attach(preMixNode)
        engine.attach(timePitchNode)

        for i in 0..<players.count {
            engine.connect(players[i], to: stemMixers[i], format: format)
            engine.connect(stemMixers[i], to: preMixNode, format: format)
        }
        engine.connect(preMixNode, to: timePitchNode, format: format)
        engine.connect(timePitchNode, to: engine.mainMixerNode, format: format)

        try engine.start()

        seekOffset = 0
        currentTime = 0
        isPlaying = false
        pitchSemitones = 0
    }

    func play() {
        guard !stemFiles.isEmpty, !isPlaying else { return }
        if !engine.isRunning { try? engine.start() }
        let sampleRate = stemFiles[0].processingFormat.sampleRate
        scheduleAndPlay(from: AVAudioFramePosition(seekOffset * sampleRate))
        isPlaying = true
        startTimer()
    }

    func pause() {
        guard isPlaying else { return }
        updateCurrentTime()
        seekOffset = currentTime
        players.forEach { $0.stop() }
        isPlaying = false
        stopTimer()
    }

    func stop() {
        players.forEach { $0.stop() }
        isPlaying = false
        stopTimer()
        seekOffset = 0
        currentTime = 0
        if engine.isRunning {
            engine.stop()
        }
    }

    func seek(to time: TimeInterval) {
        let clampedTime = max(0, min(time, duration))
        seekOffset = clampedTime
        currentTime = clampedTime
        players.forEach { $0.stop() }
        if isPlaying {
            let sampleRate = stemFiles[0].processingFormat.sampleRate
            scheduleAndPlay(from: AVAudioFramePosition(clampedTime * sampleRate))
        }
    }

    // MARK: - Private

    private func scheduleAndPlay(from framePosition: AVAudioFramePosition) {
        players.forEach { $0.stop() }

        for i in 0..<players.count {
            let file = stemFiles[i]
            let frameCount = AVAudioFrameCount(file.length - framePosition)
            guard frameCount > 0 else { return }
            players[i].scheduleSegment(
                file,
                startingFrame: framePosition,
                frameCount: frameCount,
                at: nil,
                completionCallbackType: .dataPlayedBack
            ) { [weak self] _ in
                Task { @MainActor in
                    self?.handlePlaybackCompletion()
                }
            }
        }

        guard let lastRender = engine.outputNode.lastRenderTime else { return }
        let sampleRate = engine.outputNode.outputFormat(forBus: 0).sampleRate
        let delayFrames = AVAudioFramePosition(0.1 * sampleRate)
        let startTime = AVAudioTime(
            sampleTime: lastRender.sampleTime + delayFrames,
            atRate: sampleRate
        )
        players.forEach { $0.play(at: startTime) }
    }

    private func handlePlaybackCompletion() {
        guard isPlaying else { return }
        isPlaying = false
        stopTimer()
        seekOffset = duration
        currentTime = duration
    }

    private func startTimer() {
        stopTimer()
        updateTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.updateCurrentTime()
            }
        }
    }

    private func stopTimer() {
        updateTimer?.invalidate()
        updateTimer = nil
    }

    private func updateCurrentTime() {
        guard isPlaying,
              let nodeTime = players[0].lastRenderTime,
              nodeTime.isSampleTimeValid,
              let playerTime = players[0].playerTime(forNodeTime: nodeTime) else { return }
        currentTime = seekOffset + Double(playerTime.sampleTime) / playerTime.sampleRate
    }
}
