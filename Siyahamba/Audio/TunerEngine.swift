import AVFoundation
import Accelerate
import Foundation
import Observation

@Observable
@MainActor
final class TunerEngine {

    var detectedPitch: Double = 0
    var closestString: GuitarString = .e2
    var deviationCents: Double = 0
    var isActive: Bool = false
    var lockedString: GuitarString? = nil
    var permissionDenied: Bool = false

    private var audioEngine = AVAudioEngine()
    private let playbackEngine: PlaybackEngine
    private var wasPlaying: Bool = false

    private var smoothedPitch: Double = 0
    private let smoothingFactor: Double = 0.3
    private var pitchHistory: [Double] = []
    private let historySize = 5
    private let noiseFloor: Float = 0.01

    init(playbackEngine: PlaybackEngine) {
        self.playbackEngine = playbackEngine
    }

    func start() {
        smoothedPitch = 0
        pitchHistory = []
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
        stop(resumePlayback: true)
    }

    func stopWithoutResume() {
        stop(resumePlayback: false)
    }

    private func stop(resumePlayback: Bool) {
        guard isActive else { return }
        audioEngine.inputNode.removeTap(onBus: 0)
        if audioEngine.isRunning {
            audioEngine.stop()
        }
        audioEngine = AVAudioEngine()
        isActive = false
        detectedPitch = 0
        deviationCents = 0
        smoothedPitch = 0
        pitchHistory = []
        if resumePlayback && wasPlaying {
            playbackEngine.play()
        }
        wasPlaying = false
    }

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
        guard let channelData = buffer.floatChannelData?[0] else { return }
        let frameCount = Int(buffer.frameLength)
        guard frameCount > 0 else { return }

        let samples = Array(UnsafeBufferPointer(start: channelData, count: frameCount))

        var rms: Float = 0
        vDSP_rmsqv(samples, 1, &rms, vDSP_Length(frameCount))
        guard rms > noiseFloor else { return }

        let minLag = Int(sampleRate / 350.0)
        let maxLag = min(Int(sampleRate / 75.0), frameCount / 2)
        guard minLag < maxLag else { return }

        let frequency = yinPitchDetect(samples: samples, sampleRate: sampleRate, minLag: minLag, maxLag: maxLag)
        guard frequency > 0 else { return }

        pitchHistory.append(frequency)
        if pitchHistory.count > historySize {
            pitchHistory.removeFirst()
        }

        let medianPitch = medianFilter(pitchHistory)

        if smoothedPitch == 0 {
            smoothedPitch = medianPitch
        } else {
            smoothedPitch = smoothedPitch * (1.0 - smoothingFactor) + medianPitch * smoothingFactor
        }

        let target: GuitarString
        if let locked = lockedString {
            target = locked
        } else {
            target = GuitarString.closestString(to: smoothedPitch)
        }
        let cents = GuitarString.deviationInCents(pitch: smoothedPitch, target: target.frequency)

        detectedPitch = smoothedPitch
        closestString = target
        deviationCents = cents
    }

    private func yinPitchDetect(samples: [Float], sampleRate: Double, minLag: Int, maxLag: Int) -> Double {
        let n = samples.count

        var diff = [Float](repeating: 0, count: maxLag + 1)
        for tau in 1...maxLag {
            var sum: Float = 0
            let count = n - tau
            for i in 0..<count {
                let d = samples[i] - samples[i + tau]
                sum += d * d
            }
            diff[tau] = sum
        }

        var cmnd = [Float](repeating: 1.0, count: maxLag + 1)
        var runningSum: Float = 0
        for tau in 1...maxLag {
            runningSum += diff[tau]
            if runningSum > 0 {
                cmnd[tau] = diff[tau] * Float(tau) / runningSum
            }
        }

        let threshold: Float = 0.15
        var bestTau = -1

        for tau in minLag...maxLag {
            if cmnd[tau] < threshold {
                while tau + 1 <= maxLag && cmnd[tau + 1] < cmnd[tau] {
                    bestTau = tau + 1
                    break
                }
                if bestTau < 0 { bestTau = tau }
                break
            }
        }

        if bestTau < 0 {
            var minVal: Float = Float.infinity
            for tau in minLag...maxLag {
                if cmnd[tau] < minVal {
                    minVal = cmnd[tau]
                    bestTau = tau
                }
            }
            guard minVal < 0.4 else { return 0 }
        }

        guard bestTau > 0, bestTau < maxLag else { return 0 }

        let y1 = Double(cmnd[bestTau - 1])
        let y2 = Double(cmnd[bestTau])
        let y3 = Double(cmnd[bestTau + 1])
        let denom = 2.0 * y2 - y1 - y3
        let adjustedTau: Double
        if denom != 0 {
            adjustedTau = Double(bestTau) + (y1 - y3) / (2.0 * denom)
        } else {
            adjustedTau = Double(bestTau)
        }

        guard adjustedTau > 0 else { return 0 }
        return sampleRate / adjustedTau
    }

    private func medianFilter(_ values: [Double]) -> Double {
        let sorted = values.sorted()
        let mid = sorted.count / 2
        if sorted.count % 2 == 0 && sorted.count >= 2 {
            return (sorted[mid - 1] + sorted[mid]) / 2.0
        }
        return sorted[mid]
    }
}
