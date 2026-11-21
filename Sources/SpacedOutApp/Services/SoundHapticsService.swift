import AppKit
import AVFoundation
import Foundation
import SpacedOutCore

@MainActor
final class SoundHapticsService {
    private var engine: AVAudioEngine?
    private var playerNode: AVAudioPlayerNode?
    private let sampleRate: Double = 44_100

    func playChime(_ preset: SoundPreset, enabled: Bool) {
        guard enabled, preset != .silent else { return }
        guard let buffer = synthesizeBuffer(for: preset) else { return }

        do {
            let (engine, player) = try ensureEngine(format: buffer.format)
            if !engine.isRunning {
                try engine.start()
            }
            player.stop()
            player.scheduleBuffer(buffer, at: nil, options: .interrupts)
            player.play()
        } catch {
            // no audio device / muted headless mac
        }
    }

    func performHaptic(_ pattern: NSHapticFeedbackManager.FeedbackPattern = .alignment, enabled: Bool) {
        guard enabled else { return }
        NSHapticFeedbackManager.defaultPerformer.perform(pattern, performanceTime: .now)
    }

    private func ensureEngine(format: AVAudioFormat) throws -> (AVAudioEngine, AVAudioPlayerNode) {
        if let engine, let playerNode {
            return (engine, playerNode)
        }
        let newEngine = AVAudioEngine()
        let newPlayer = AVAudioPlayerNode()
        newEngine.attach(newPlayer)
        newEngine.connect(newPlayer, to: newEngine.mainMixerNode, format: format)
        newEngine.prepare()
        self.engine = newEngine
        self.playerNode = newPlayer
        return (newEngine, newPlayer)
    }

    private func synthesizeBuffer(for preset: SoundPreset) -> AVAudioPCMBuffer? {
        struct ToneNote {
            let frequency: Double
            let startTime: Double
            let duration: Double
            let gain: Double
            let harmonic2: Double
            let harmonic3: Double
        }

        let notes: [ToneNote]
        let totalDuration: Double

        switch preset {
        case .glassChime:
            notes = [
                ToneNote(frequency: 1046.50, startTime: 0.00, duration: 0.85, gain: 0.22, harmonic2: 0.14, harmonic3: 0.04),
                ToneNote(frequency: 1318.51, startTime: 0.12, duration: 0.90, gain: 0.20, harmonic2: 0.12, harmonic3: 0.04),
                ToneNote(frequency: 1567.98, startTime: 0.24, duration: 1.10, gain: 0.18, harmonic2: 0.10, harmonic3: 0.03)
            ]
            totalDuration = 1.45
        case .warmMarimba:
            notes = [
                ToneNote(frequency: 349.23, startTime: 0.00, duration: 0.42, gain: 0.28, harmonic2: 0.18, harmonic3: 0.02),
                ToneNote(frequency: 440.00, startTime: 0.14, duration: 0.48, gain: 0.25, harmonic2: 0.15, harmonic3: 0.02),
                ToneNote(frequency: 523.25, startTime: 0.28, duration: 0.70, gain: 0.24, harmonic2: 0.12, harmonic3: 0.02)
            ]
            totalDuration = 1.05
        case .softBell:
            notes = [
                ToneNote(frequency: 587.33, startTime: 0.00, duration: 1.30, gain: 0.24, harmonic2: 0.22, harmonic3: 0.08),
                ToneNote(frequency: 880.00, startTime: 0.03, duration: 1.15, gain: 0.12, harmonic2: 0.10, harmonic3: 0.03)
            ]
            totalDuration = 1.40
        case .crystalPulse:
            notes = [
                ToneNote(frequency: 880.00, startTime: 0.00, duration: 0.45, gain: 0.20, harmonic2: 0.12, harmonic3: 0.05),
                ToneNote(frequency: 1318.51, startTime: 0.18, duration: 0.70, gain: 0.22, harmonic2: 0.14, harmonic3: 0.04),
                ToneNote(frequency: 1318.51, startTime: 0.45, duration: 0.85, gain: 0.16, harmonic2: 0.10, harmonic3: 0.03)
            ]
            totalDuration = 1.35
        case .silent:
            return nil
        }

        guard let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1) else {
            return nil
        }
        let frameCount = AVAudioFrameCount(totalDuration * sampleRate)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else {
            return nil
        }
        buffer.frameLength = frameCount
        guard let channelData = buffer.floatChannelData?[0] else {
            return nil
        }

        for i in 0..<Int(frameCount) {
            channelData[i] = 0
        }

        let attackTime = 0.009
        for note in notes {
            let startFrame = max(0, Int(note.startTime * sampleRate))
            let noteFrames = Int(note.duration * sampleRate)
            let endFrame = min(Int(frameCount), startFrame + noteFrames)

            for frame in startFrame..<endFrame {
                let t = Double(frame - startFrame) / sampleRate
                let attack = t < attackTime ? 0.5 * (1.0 - cos(.pi * t / attackTime)) : 1.0
                let decay = exp(-4.8 * (t / note.duration))
                let env = attack * decay

                let phase = 2.0 * .pi * note.frequency * t
                let wave = sin(phase)
                    + note.harmonic2 * sin(2.0 * phase)
                    + note.harmonic3 * sin(3.0 * phase)

                channelData[frame] += Float(wave * env * note.gain)
            }
        }

        for i in 0..<Int(frameCount) {
            channelData[i] = tanh(channelData[i])
        }

        return buffer
    }
}
