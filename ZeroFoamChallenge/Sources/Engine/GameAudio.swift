import AVFoundation
import CoreGraphics
import Foundation

/// Tiny software synth: every sound effect is generated as raw PCM at start-up
/// and played straight out of memory, so the app ships with no audio assets.
final class GameAudio {
    private let engine = AVAudioEngine()
    private let pourNode = AVAudioPlayerNode()
    private let fizzNode = AVAudioPlayerNode()
    private let oneShotNode = AVAudioPlayerNode()

    private var pourBuffer: AVAudioPCMBuffer?
    private var fizzBuffer: AVAudioPCMBuffer?
    private var successBuffer: AVAudioPCMBuffer?
    private var failBuffer: AVAudioPCMBuffer?

    private let sampleRate: Double = 22050
    private var ready = false
    private var pouring = false
    var muted = false

    func start() {
        guard !ready else { return }
        #if canImport(UIKit)
        // Ambient: never interrupt the player's music, never take the phone
        // out of silent mode.
        try? AVAudioSession.sharedInstance().setCategory(.ambient, mode: .default)
        try? AVAudioSession.sharedInstance().setActive(true)
        #endif

        guard let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1) else { return }
        for node in [pourNode, fizzNode, oneShotNode] {
            engine.attach(node)
            engine.connect(node, to: engine.mainMixerNode, format: format)
        }
        pourBuffer = buffer(from: pourSamples(), format: format)
        fizzBuffer = buffer(from: fizzSamples(), format: format)
        successBuffer = buffer(from: successSamples(), format: format)
        failBuffer = buffer(from: failSamples(), format: format)

        do {
            try engine.start()
            ready = true
        } catch {
            // Audio is a nicety, never a crash.
            ready = false
        }
    }

    func setPouring(_ on: Bool, intensity: CGFloat = 1) {
        guard ready, !muted else { return }
        if on, !pouring {
            pouring = true
            pourNode.volume = Float(0.25 + 0.5 * min(max(intensity, 0), 1))
            fizzNode.volume = 0.18
            if let b = pourBuffer { pourNode.scheduleBuffer(b, at: nil, options: .loops) }
            if let b = fizzBuffer { fizzNode.scheduleBuffer(b, at: nil, options: .loops) }
            pourNode.play()
            fizzNode.play()
        } else if !on, pouring {
            pouring = false
            pourNode.stop()
            fizzNode.stop()
        } else if on {
            pourNode.volume = Float(0.25 + 0.5 * min(max(intensity, 0), 1))
        }
    }

    func playSuccess() { playOneShot(successBuffer, volume: 0.8) }
    func playFail() { playOneShot(failBuffer, volume: 0.8) }

    private func playOneShot(_ buffer: AVAudioPCMBuffer?, volume: Float) {
        guard ready, !muted, let buffer else { return }
        oneShotNode.stop()
        oneShotNode.volume = volume
        oneShotNode.scheduleBuffer(buffer, at: nil, options: .interrupts)
        oneShotNode.play()
    }

    func stopAll() {
        pouring = false
        guard ready else { return }
        pourNode.stop()
        fizzNode.stop()
    }

    func shutdown() {
        stopAll()
        if ready { engine.stop() }
        ready = false
    }

    // MARK: Synthesis

    private func buffer(from samples: [Float], format: AVAudioFormat) -> AVAudioPCMBuffer? {
        guard let buf = AVAudioPCMBuffer(pcmFormat: format,
                                         frameCapacity: AVAudioFrameCount(samples.count)),
              let channel = buf.floatChannelData?[0] else { return nil }
        for i in samples.indices { channel[i] = samples[i] }
        buf.frameLength = AVAudioFrameCount(samples.count)
        return buf
    }

    /// Band-limited noise with a slow amplitude wobble: reads as splashing
    /// liquid when looped.
    private func pourSamples() -> [Float] {
        let n = Int(sampleRate * 1.0)
        var out = [Float](repeating: 0, count: n)
        var generator = SeededGenerator(seed: 1234)
        var lp: Float = 0, hp: Float = 0, prev: Float = 0
        for i in 0..<n {
            let white = Float.random(in: -1...1, using: &generator)
            lp += (white - lp) * 0.35              // low pass -> body
            hp = 0.85 * (hp + lp - prev)           // high pass -> hiss
            prev = lp
            let t = Float(i) / Float(sampleRate)
            let wobble = 0.75 + 0.25 * sin(2 * .pi * 3.1 * t)
            out[i] = (lp * 0.7 + hp * 0.5) * wobble * 0.6
        }
        crossfadeLoop(&out, fade: 400)
        return out
    }

    /// Sparse clicks: the crackle of a fresh head of foam.
    private func fizzSamples() -> [Float] {
        let n = Int(sampleRate * 1.5)
        var out = [Float](repeating: 0, count: n)
        var generator = SeededGenerator(seed: 99)
        for i in 0..<n {
            guard Float.random(in: 0...1, using: &generator) < 0.004 else { continue }
            let len = 40 + Int.random(in: 0..<90, using: &generator)
            let f = Float.random(in: 1800...6000, using: &generator)
            let amp = Float.random(in: 0.15...0.5, using: &generator)
            for k in 0..<len where i + k < n {
                let env = exp(-Float(k) / (Float(len) * 0.28))
                out[i + k] += sin(2 * .pi * f * Float(k) / Float(sampleRate)) * env * amp
            }
        }
        crossfadeLoop(&out, fade: 600)
        return out
    }

    /// Bright major arpeggio.
    private func successSamples() -> [Float] {
        melody([523.25, 659.25, 783.99, 1046.5], noteLength: 0.16, amp: 0.55)
    }

    /// Descending detuned buzz.
    private func failSamples() -> [Float] {
        melody([220, 174.6, 130.8], noteLength: 0.22, amp: 0.6, square: true)
    }

    private func melody(_ freqs: [Float], noteLength: Float, amp: Float,
                        square: Bool = false) -> [Float] {
        let total = Int(Float(sampleRate) * (noteLength * Float(freqs.count) + 0.35))
        var out = [Float](repeating: 0, count: total)
        for (index, freq) in freqs.enumerated() {
            let start = Int(Float(index) * noteLength * Float(sampleRate))
            let len = Int(noteLength * 2 * Float(sampleRate))
            for k in 0..<len where start + k < total {
                let t = Float(k) / Float(sampleRate)
                let env = exp(-t * (square ? 6 : 4.5))
                var s = sin(2 * .pi * freq * t)
                if square { s = (s < 0 ? -0.6 : 0.6) + 0.4 * sin(4 * .pi * freq * t) }
                out[start + k] += s * env * amp
            }
        }
        return out
    }

    private func crossfadeLoop(_ buf: inout [Float], fade: Int) {
        let n = buf.count
        guard fade * 2 < n else { return }
        for i in 0..<fade {
            let t = Float(i) / Float(fade)
            buf[i] = buf[i] * t + buf[n - fade + i] * (1 - t)
        }
    }
}

/// Deterministic PRNG so the synthesized noise is identical on every launch.
struct SeededGenerator: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) { state = seed &* 6364136223846793005 &+ 1442695040888963407 }

    mutating func next() -> UInt64 {
        state ^= state << 13
        state ^= state >> 7
        state ^= state << 17
        return state
    }
}
