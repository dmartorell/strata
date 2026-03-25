import AVFoundation
import Accelerate
import Foundation
import Observation

// MARK: - TunerEngine

@Observable
@MainActor
final class TunerEngine {

    // MARK: - Public State

    var detectedPitch: Double = 0
    var closestString: GuitarString = .e2
    var deviationCents: Double = 0
    var isActive: Bool = false
    var lockedString: GuitarString? = nil
    var permissionDenied: Bool = false

    // MARK: - Private

    private let audioEngine = AVAudioEngine()
    private let playbackEngine: PlaybackEngine
    private var wasPlaying: Bool = false
    private var lastUpdateTime: TimeInterval = 0

    // MARK: - Init

    init(playbackEngine: PlaybackEngine) {
        self.playbackEngine = playbackEngine
    }

    // MARK: - Public API

    func start() {
        Task {
            let granted = await AVCaptureDevice.requestAccess(for: .audio)
            await MainActor.run {
                if granted {
                    self.startAudioEngine()
                } else {
                    self.permissionDenied = true
                }
            }
        }
    }

    func stop() {
        guard isActive else { return }
        audioEngine.inputNode.removeTap(onBus: 0)
        if audioEngine.isRunning {
            audioEngine.stop()
        }
        isActive = false
        detectedPitch = 0
        deviationCents = 0
        if wasPlaying {
            playbackEngine.play()
        }
        wasPlaying = false
    }

    // MARK: - Private

    private func startAudioEngine() {
        wasPlaying = playbackEngine.isPlaying
        if wasPlaying {
            playbackEngine.pause()
        }

        let inputNode = audioEngine.inputNode
        let inputFormat = inputNode.outputFormat(forBus: 0)

        let sampleRate = inputFormat.sampleRate
        let bufferSize: AVAudioFrameCount = 4096

        inputNode.installTap(onBus: 0, bufferSize: bufferSize, format: inputFormat) { [weak self] buffer, _ in
            self?.processAudioBuffer(buffer, sampleRate: sampleRate)
        }

        do {
            try audioEngine.start()
            isActive = true
        } catch {
            audioEngine.inputNode.removeTap(onBus: 0)
            wasPlaying = false
        }
    }

    private func processAudioBuffer(_ buffer: AVAudioPCMBuffer, sampleRate: Double) {
        let now = Date.timeIntervalSinceReferenceDate
        guard now - lastUpdateTime >= 0.1 else { return }

        guard let channelData = buffer.floatChannelData?[0] else { return }
        let frameCount = Int(buffer.frameLength)
        guard frameCount > 0 else { return }

        var samples = [Float](UnsafeBufferPointer(start: channelData, count: frameCount))

        // Apply Hanning window
        var window = [Float](repeating: 0, count: frameCount)
        vDSP_hann_window(&window, vDSP_Length(frameCount), Int32(vDSP_HANN_NORM))
        vDSP_vmul(samples, 1, window, 1, &samples, 1, vDSP_Length(frameCount))

        // Compute autocorrelation manually for lag range of interest
        // r[lag] = sum(samples[i] * samples[i+lag]) for i in 0..N-1-lag
        let r0 = samples.reduce(0) { $0 + $1 * $1 }
        guard r0 > 0 else { return }

        // Search range: lag indices covering E2 (82Hz) to E4 (330Hz) with margin
        let minLag = Int(sampleRate / 350.0)  // ~126 samples @ 44100
        let maxLag = Int(sampleRate / 75.0)   // ~588 samples @ 44100

        guard minLag < maxLag, maxLag < frameCount else { return }

        // Build correlation values for search range using vDSP inner product
        var peakValue: Float = -Float.infinity
        var peakIndex = minLag
        var correlationAtPeak: (prev: Float, next: Float) = (0, 0)

        for lag in minLag...maxLag {
            var dotProduct: Float = 0
            let count = frameCount - lag
            vDSP_dotpr(samples, 1, Array(samples[lag...]), 1, &dotProduct, vDSP_Length(count))
            if dotProduct > peakValue {
                peakValue = dotProduct
                peakIndex = lag
                let prevLag = lag - 1
                let nextLag = lag + 1
                var prev: Float = 0
                var next: Float = 0
                if prevLag >= minLag {
                    vDSP_dotpr(samples, 1, Array(samples[prevLag...]), 1, &prev, vDSP_Length(frameCount - prevLag))
                }
                if nextLag <= maxLag {
                    vDSP_dotpr(samples, 1, Array(samples[nextLag...]), 1, &next, vDSP_Length(frameCount - nextLag))
                }
                correlationAtPeak = (prev, next)
            }
        }

        // Confidence check: peak must exceed 20% of r0
        guard peakValue > 0.2 * r0 else { return }

        // Parabolic interpolation for sub-sample accuracy
        let lagF: Double
        let y1 = Double(correlationAtPeak.prev)
        let y2 = Double(peakValue)
        let y3 = Double(correlationAtPeak.next)
        let denom = 2.0 * (2.0 * y2 - y1 - y3)
        if denom != 0 {
            lagF = Double(peakIndex) + (y1 - y3) / denom
        } else {
            lagF = Double(peakIndex)
        }

        guard lagF > 0 else { return }
        let frequency = sampleRate / lagF

        lastUpdateTime = now

        let pitch = frequency
        let target: GuitarString
        if let locked = lockedString {
            target = locked
        } else {
            target = GuitarString.closestString(to: pitch)
        }
        let cents = GuitarString.deviationInCents(pitch: pitch, target: target.frequency)

        detectedPitch = pitch
        closestString = target
        deviationCents = cents
    }
}
