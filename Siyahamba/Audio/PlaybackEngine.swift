import AVFAudio
import Foundation
import Observation

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
    var vocalsEnabled: Bool = true

    // MARK: - Private Audio Graph

    @ObservationIgnored private let engine = AVAudioEngine()
    @ObservationIgnored private var originalPlayer = AVAudioPlayerNode()
    @ObservationIgnored private var instrumentalPlayer = AVAudioPlayerNode()
    @ObservationIgnored private var originalMixer = AVAudioMixerNode()
    @ObservationIgnored private var instrumentalMixer = AVAudioMixerNode()
    @ObservationIgnored private let preMixNode = AVAudioMixerNode()
    @ObservationIgnored private let timePitchNode = AVAudioUnitTimePitch()
    @ObservationIgnored private var originalFile: AVAudioFile?
    @ObservationIgnored private var instrumentalFile: AVAudioFile?

    // MARK: - Tick callback (set by PlayerView to wire PlayerViewModel.tick())
    @ObservationIgnored var onTick: (() -> Void)?

    // MARK: - Private State

    @ObservationIgnored private var seekOffset: TimeInterval = 0
    @ObservationIgnored private var updateTimer: Timer?
    @ObservationIgnored private var isLooping: Bool = false
    @ObservationIgnored private var playbackGeneration: Int = 0

    // MARK: - Computed helpers

    private var players: [AVAudioPlayerNode] { [originalPlayer, instrumentalPlayer] }
    private var files: [AVAudioFile] {
        [originalFile, instrumentalFile].compactMap { $0 }
    }

    // MARK: - Public API

    func load(originalURL: URL, instrumentalURL: URL) throws {
        NotificationCenter.default.removeObserver(self)

        if engine.isRunning {
            stop()
        }

        originalPlayer = AVAudioPlayerNode()
        instrumentalPlayer = AVAudioPlayerNode()
        originalMixer = AVAudioMixerNode()
        instrumentalMixer = AVAudioMixerNode()

        originalFile = try AVAudioFile(forReading: originalURL)
        instrumentalFile = try AVAudioFile(forReading: instrumentalURL)

        duration = files.map {
            Double($0.length) / $0.processingFormat.sampleRate
        }.max() ?? 0

        guard let format = originalFile?.processingFormat else { return }

        engine.attach(originalPlayer)
        engine.attach(instrumentalPlayer)
        engine.attach(originalMixer)
        engine.attach(instrumentalMixer)
        engine.attach(preMixNode)
        engine.attach(timePitchNode)

        engine.connect(originalPlayer, to: originalMixer, format: format)
        engine.connect(instrumentalPlayer, to: instrumentalMixer, format: format)
        engine.connect(originalMixer, to: preMixNode, format: format)
        engine.connect(instrumentalMixer, to: preMixNode, format: format)
        engine.connect(preMixNode, to: timePitchNode, format: format)
        engine.connect(timePitchNode, to: engine.mainMixerNode, format: format)

        try engine.start()

        seekOffset = 0
        currentTime = 0
        isPlaying = false
        pitchSemitones = 0
        vocalsEnabled = true
        loopStart = nil
        loopEnd = nil
        isLooping = false

        applyTrackVolumes()
        setupNotifications()
    }

    func play() {
        guard !files.isEmpty, !isPlaying else { return }
        if !engine.isRunning { try? engine.start() }
        players.forEach { $0.stop() }
        let sampleRate = files[0].processingFormat.sampleRate
        if isLooping, let start = loopStart, let end = loopEnd {
            if seekOffset < start || seekOffset >= end {
                seekOffset = start
                currentTime = start
            }
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

    func fadeOutAndStop(duration: TimeInterval = 0.4) async {
        guard isPlaying else {
            stop()
            return
        }
        let steps = 20
        let interval = duration / Double(steps)
        let originalVolume = engine.mainMixerNode.outputVolume
        for i in 1...steps {
            let fraction = 1.0 - (Float(i) / Float(steps))
            engine.mainMixerNode.outputVolume = originalVolume * fraction
            try? await Task.sleep(for: .milliseconds(Int(interval * 1000)))
        }
        stop()
        engine.mainMixerNode.outputVolume = originalVolume
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
                let sampleRate = files[0].processingFormat.sampleRate
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

    func setLoop(start: TimeInterval, end: TimeInterval) {
        loopStart = start
        loopEnd = end
        updateLoopState()
    }

    func clearLoop() {
        let wasLooping = isLooping
        loopStart = nil
        loopEnd = nil
        isLooping = false
        if wasLooping, isPlaying {
            updateCurrentTime()
            let time = currentTime
            seekOffset = time
            players.forEach { $0.stop() }
            let sampleRate = files[0].processingFormat.sampleRate
            scheduleAndPlay(from: AVAudioFramePosition(time * sampleRate))
        }
    }

    // MARK: - Pitch

    func setPitch(semitones: Int) {
        let clamped = max(-6, min(6, semitones))
        pitchSemitones = clamped
        timePitchNode.pitch = Float(clamped * 100)
    }

    // MARK: - Vocal Toggle

    func setVocals(enabled: Bool) {
        vocalsEnabled = enabled
        applyTrackVolumes()
    }

    // MARK: - Private

    private func applyTrackVolumes() {
        originalMixer.outputVolume = vocalsEnabled ? 1.0 : 0.0
        instrumentalMixer.outputVolume = vocalsEnabled ? 0.0 : 1.0
    }

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
        } else {
            seekOffset = start
            currentTime = start
        }
    }

    private func scheduleLoopAndPlay(from time: TimeInterval) {
        guard let start = loopStart, let end = loopEnd else { return }
        let clampedTime = max(start, min(time, end - 0.001))
        let sampleRate = files[0].processingFormat.sampleRate
        let startFrame = AVAudioFramePosition(clampedTime * sampleRate)
        let endFrame = AVAudioFramePosition(end * sampleRate)

        let allPlayers = players
        let allFiles = files
        for i in 0..<allPlayers.count {
            let file = allFiles[i]
            let frameCount = AVAudioFrameCount(min(endFrame, file.length) - startFrame)
            guard frameCount > 0 else { continue }
            allPlayers[i].scheduleSegment(file,
                startingFrame: startFrame,
                frameCount: frameCount,
                at: nil,
                completionCallbackType: .dataPlayedBack) { [weak self] _ in
                Task { @MainActor in
                    guard let self, self.isLooping else { return }
                    self.scheduleLoopSegment(index: i)
                }
            }
        }

        let delayTicks = secondsToHostTicks(0.1)
        let startTime = AVAudioTime(hostTime: mach_absolute_time() + delayTicks)
        allPlayers.forEach { $0.play(at: startTime) }

        _ = start
    }

    private func scheduleLoopSegment(index: Int) {
        guard let start = loopStart, let end = loopEnd, isLooping else { return }
        let allPlayers = players
        let allFiles = files
        guard index < allFiles.count else { return }
        let file = allFiles[index]
        let sampleRate = file.processingFormat.sampleRate
        let startFrame = AVAudioFramePosition(start * sampleRate)
        let frameCount = AVAudioFrameCount((end - start) * sampleRate)
        guard frameCount > 0 else { return }

        seekOffset = start
        currentTime = start

        allPlayers[index].scheduleSegment(file,
            startingFrame: startFrame,
            frameCount: frameCount,
            at: nil,
            completionCallbackType: .dataPlayedBack) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.isLooping else { return }
                self.scheduleLoopSegment(index: index)
            }
        }
    }

    private func scheduleAndPlay(from framePosition: AVAudioFramePosition) {
        playbackGeneration += 1
        let generation = playbackGeneration

        let allPlayers = players
        let allFiles = files
        allPlayers.forEach { $0.stop() }

        for i in 0..<allPlayers.count {
            let file = allFiles[i]
            let frameCount = AVAudioFrameCount(file.length - framePosition)
            guard frameCount > 0 else { return }
            allPlayers[i].scheduleSegment(
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
        allPlayers.forEach { $0.play(at: startTime) }
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
                let sampleRate = files[0].processingFormat.sampleRate
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
              let nodeTime = originalPlayer.lastRenderTime,
              nodeTime.isSampleTimeValid,
              let playerTime = originalPlayer.playerTime(forNodeTime: nodeTime),
              playerTime.sampleTime >= 0 else { return }
        let raw = seekOffset + Double(playerTime.sampleTime) / playerTime.sampleRate
        if isLooping, let start = loopStart, let end = loopEnd, end > start {
            let loopLen = end - start
            currentTime = start + (raw - start).truncatingRemainder(dividingBy: loopLen)
        } else {
            currentTime = raw
        }
        onTick?()
    }
}
