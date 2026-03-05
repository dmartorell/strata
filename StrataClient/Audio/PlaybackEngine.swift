import AVFAudio
import Foundation
import Observation

// MARK: - Stem

enum Stem: Int, CaseIterable {
    case vocals = 0
    case drums = 1
    case bass = 2
    case other = 3
}

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
    var pitchSemitones: Int = 0
    var loopStart: TimeInterval? = nil
    var loopEnd: TimeInterval? = nil

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
    private var stemVolumes: [Float] = [1.0, 1.0, 1.0, 1.0]
    private var stemMuted: [Bool] = [false, false, false, false]
    private(set) var soloedStem: Int? = nil
    private var isLooping: Bool = false
    private var playbackGeneration: Int = 0

    // MARK: - Public API

    func load(stemURLs: [URL]) throws {
        NotificationCenter.default.removeObserver(self)

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
        stemVolumes = [1.0, 1.0, 1.0, 1.0]
        stemMuted = [false, false, false, false]
        soloedStem = nil
        loopStart = nil
        loopEnd = nil
        isLooping = false

        setupNotifications()
    }

    func play() {
        guard !stemFiles.isEmpty, !isPlaying else { return }
        if !engine.isRunning { try? engine.start() }
        let sampleRate = stemFiles[0].processingFormat.sampleRate
        if isLooping {
            scheduleLoopAndPlay(from: seekOffset)
        } else {
            scheduleAndPlay(from: AVAudioFramePosition(seekOffset * sampleRate))
        }
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

        if let start = loopStart, let end = loopEnd {
            if clampedTime < start || clampedTime >= end {
                clearLoop()
            }
        }

        seekOffset = clampedTime
        currentTime = clampedTime
        players.forEach { $0.stop() }
        if isPlaying {
            stopTimer()
            if isLooping {
                scheduleLoopAndPlay(from: clampedTime)
            } else {
                let sampleRate = stemFiles[0].processingFormat.sampleRate
                scheduleAndPlay(from: AVAudioFramePosition(clampedTime * sampleRate))
            }
            startTimer()
        }
    }

    // MARK: - A/B Loop

    func setLoopStart(_ time: TimeInterval?) {
        loopStart = time
        updateLoopState()
    }

    func setLoopEnd(_ time: TimeInterval?) {
        loopEnd = time
        updateLoopState()
    }

    func clearLoop() {
        loopStart = nil
        loopEnd = nil
        isLooping = false
    }

    // MARK: - Pitch

    func setPitch(semitones: Int) {
        let clamped = max(-6, min(6, semitones))
        pitchSemitones = clamped
        timePitchNode.pitch = Float(clamped * 100)
    }

    // MARK: - Per-Stem Volume / Mute / Solo

    func setVolume(_ volume: Float, for stem: Int) {
        guard stem >= 0 && stem < 4 else { return }
        stemVolumes[stem] = max(0.0, min(1.0, volume))
        applyVolumes()
    }

    func getVolume(for stem: Int) -> Float {
        guard stem >= 0 && stem < 4 else { return 0 }
        return stemVolumes[stem]
    }

    func setMute(_ muted: Bool, for stem: Int) {
        guard stem >= 0 && stem < 4 else { return }
        stemMuted[stem] = muted
        applyVolumes()
    }

    func isMuted(_ stem: Int) -> Bool {
        guard stem >= 0 && stem < 4 else { return false }
        return stemMuted[stem]
    }

    func setSolo(_ stem: Int?) {
        soloedStem = stem
        applyVolumes()
    }

    // MARK: - Private

    private func updateLoopState() {
        guard let start = loopStart, let end = loopEnd, end > start else {
            isLooping = false
            return
        }
        isLooping = true
        if isPlaying {
            let clampedTime = max(start, min(currentTime, end))
            seekOffset = clampedTime
            players.forEach { $0.stop() }
            scheduleLoopAndPlay(from: clampedTime)
        }
    }

    private func scheduleLoopAndPlay(from time: TimeInterval) {
        guard let start = loopStart, let end = loopEnd else { return }
        let sampleRate = stemFiles[0].processingFormat.sampleRate
        let startFrame = AVAudioFramePosition(time * sampleRate)
        let endFrame = AVAudioFramePosition(end * sampleRate)

        for i in 0..<players.count {
            let file = stemFiles[i]
            let frameCount = AVAudioFrameCount(min(endFrame, file.length) - startFrame)
            guard frameCount > 0 else { continue }
            players[i].scheduleSegment(file,
                startingFrame: startFrame,
                frameCount: frameCount,
                at: nil,
                completionCallbackType: .dataPlayedBack) { [weak self] _ in
                Task { @MainActor in
                    guard let self, self.isLooping else { return }
                    self.scheduleLoopSegment(stem: i)
                }
            }
        }

        let delayTicks = secondsToHostTicks(0.1)
        let startTime = AVAudioTime(hostTime: mach_absolute_time() + delayTicks)
        players.forEach { $0.play(at: startTime) }

        _ = start
    }

    private func scheduleLoopSegment(stem: Int) {
        guard let start = loopStart, let end = loopEnd, isLooping else { return }
        let sampleRate = stemFiles[stem].processingFormat.sampleRate
        let startFrame = AVAudioFramePosition(start * sampleRate)
        let frameCount = AVAudioFrameCount((end - start) * sampleRate)
        guard frameCount > 0 else { return }

        seekOffset = start
        currentTime = start

        players[stem].scheduleSegment(stemFiles[stem],
            startingFrame: startFrame,
            frameCount: frameCount,
            at: nil,
            completionCallbackType: .dataPlayedBack) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.isLooping else { return }
                self.scheduleLoopSegment(stem: stem)
            }
        }
    }

    private func applyVolumes() {
        for i in 0..<min(4, stemMixers.count) {
            let volume: Float
            if let soloed = soloedStem {
                volume = (i == soloed && !stemMuted[i]) ? stemVolumes[i] : 0.0
            } else {
                volume = stemMuted[i] ? 0.0 : stemVolumes[i]
            }
            stemMixers[i].outputVolume = volume
        }
    }

    private func scheduleAndPlay(from framePosition: AVAudioFramePosition) {
        playbackGeneration += 1
        let generation = playbackGeneration

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
                    guard let self, self.playbackGeneration == generation else { return }
                    self.handlePlaybackCompletion()
                }
            }
        }

        let delayTicks = secondsToHostTicks(0.1)
        let startTime = AVAudioTime(hostTime: mach_absolute_time() + delayTicks)
        players.forEach { $0.play(at: startTime) }
    }

    private func secondsToHostTicks(_ seconds: Double) -> UInt64 {
        var info = mach_timebase_info_data_t()
        mach_timebase_info(&info)
        let nanos = UInt64(seconds * Double(NSEC_PER_SEC))
        return nanos * UInt64(info.denom) / UInt64(info.numer)
    }

    private func handlePlaybackCompletion() {
        guard isPlaying, !isLooping else { return }
        isPlaying = false
        stopTimer()
        seekOffset = duration
        currentTime = duration
    }

    private func setupNotifications() {
        NotificationCenter.default.removeObserver(self)
        NotificationCenter.default.addObserver(
            forName: .AVAudioEngineConfigurationChange,
            object: engine,
            queue: .main) { [weak self] _ in
            Task { @MainActor in
                self?.handleConfigurationChange()
            }
        }
    }

    private func handleConfigurationChange() {
        let wasPlaying = isPlaying
        let savedTime = currentTime

        players.forEach { $0.stop() }
        isPlaying = false
        stopTimer()

        do {
            try engine.start()
        } catch {
            return
        }

        seekOffset = savedTime
        currentTime = savedTime

        if wasPlaying {
            if isLooping {
                scheduleLoopAndPlay(from: savedTime)
            } else {
                let sampleRate = stemFiles[0].processingFormat.sampleRate
                scheduleAndPlay(from: AVAudioFramePosition(savedTime * sampleRate))
            }
            isPlaying = true
            startTimer()
        }
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
              let playerTime = players[0].playerTime(forNodeTime: nodeTime),
              playerTime.sampleTime >= 0 else { return }
        currentTime = seekOffset + Double(playerTime.sampleTime) / playerTime.sampleRate
    }
}
