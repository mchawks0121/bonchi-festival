//
//  SoundManager.swift
//  bonchi-festival
//
//  Procedurally synthesised sound effects using AVAudioEngine.
//  No audio asset files are required — all waveforms are generated at runtime.
//

import AVFoundation

// MARK: - SoundManager

/// Generates and plays synthesised sound effects for game events.
/// All sounds are created from PCM sine-wave buffers so no bundled audio
/// files are needed, staying consistent with the project's asset-free approach.
final class SoundManager {

    static let shared = SoundManager()

    // MARK: - Private

    private let engine      = AVAudioEngine()
    private let mixerNode   = AVAudioMixerNode()
    private let sampleRate: Double = 44_100

    /// Pool of player nodes so concurrent sounds can overlap without cutting
    /// each other off (e.g. lock-on ping fires while a capture arpeggio plays).
    private let playerNodes: [AVAudioPlayerNode]
    private var roundRobinIndex = 0

    private lazy var monoFormat: AVAudioFormat = {
        AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1)!
    }()

    // MARK: - Init

    private init() {
        // Build a pool of six player nodes
        playerNodes = (0..<6).map { _ in AVAudioPlayerNode() }

        engine.attach(mixerNode)
        engine.connect(mixerNode, to: engine.outputNode, format: nil)

        for node in playerNodes {
            engine.attach(node)
            engine.connect(node, to: mixerNode, format: monoFormat)
        }

        configureAudioSession()
        startEngine()
    }

    // MARK: - Public API

    /// Short whoosh when the net is thrown.
    func playThrow() {
        play(makeSweep(startFreq: 550, endFreq: 200, duration: 0.14, amplitude: 0.40))
    }

    /// Ascending arpeggio on bug capture.  Higher-value bugs trigger more notes.
    func playCapture(points: Int) {
        let notes: [Double]
        switch points {
        case 5:  notes = [523.25, 659.25, 783.99, 1046.5]   // C5 E5 G5 C6
        case 3:  notes = [659.25, 783.99, 987.77]            // E5 G5 B5
        default: notes = [880.0, 1108.73]                    // A5 C#6
        }
        playSequence(notes, noteDuration: 0.16, noteGap: 0.065, amplitude: 0.42)
    }

    /// Descending thud when the net misses.
    func playMiss() {
        play(makeSweep(startFreq: 280, endFreq: 120, duration: 0.22, amplitude: 0.32))
    }

    /// Brief beep when a bug enters the crosshair lock-on ring.
    func playLockOn() {
        play(makeTone(frequency: 1200, duration: 0.055, amplitude: 0.28,
                      fadeIn: 0.005, fadeOut: 0.025))
    }

    /// Ascending fanfare when the game starts.
    func playGameStart() {
        let notes: [Double] = [523.25, 659.25, 783.99, 1046.5]  // C5 E5 G5 C6
        playSequence(notes, noteDuration: 0.20, noteGap: 0.095, amplitude: 0.38)
    }

    /// Descending melody when the 90-second round ends.
    func playGameEnd() {
        let notes: [Double] = [783.99, 659.25, 523.25, 392.0]   // G5 E5 C5 G4
        playSequence(notes, noteDuration: 0.26, noteGap: 0.11, amplitude: 0.36)
    }

    // MARK: - Private: scheduling

    private func play(_ buffer: AVAudioPCMBuffer?) {
        guard let buffer else { return }
        let node = nextPlayer()
        node.stop()
        node.scheduleBuffer(buffer)
        if !node.isPlaying { node.play() }
    }

    /// Plays a sequence of pure tones, spaced `noteGap` seconds apart.
    /// Uses `asyncAfter` to avoid blocking the global thread pool.
    private func playSequence(_ freqs: [Double],
                              noteDuration: Double,
                              noteGap: Double,
                              amplitude: Float) {
        for (index, freq) in freqs.enumerated() {
            let delay = noteGap * Double(index)
            DispatchQueue.global(qos: .userInteractive).asyncAfter(deadline: .now() + delay) { [weak self] in
                guard let self else { return }
                self.play(self.makeTone(frequency: freq,
                                       duration: noteDuration,
                                       amplitude: amplitude,
                                       fadeIn: 0.01,
                                       fadeOut: 0.08))
            }
        }
    }

    private func nextPlayer() -> AVAudioPlayerNode {
        let node = playerNodes[roundRobinIndex]
        roundRobinIndex = (roundRobinIndex + 1) % playerNodes.count
        return node
    }

    // MARK: - Private: buffer generation

    /// Pure sine-wave tone with linear attack/decay envelope.
    private func makeTone(frequency: Double,
                          duration: Double,
                          amplitude: Float,
                          fadeIn: Double,
                          fadeOut: Double) -> AVAudioPCMBuffer? {
        let frameCount = AVAudioFrameCount(sampleRate * duration)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: monoFormat,
                                            frameCapacity: frameCount) else { return nil }
        buffer.frameLength = frameCount

        let samples = buffer.floatChannelData![0]
        for i in 0..<Int(frameCount) {
            let t   = Double(i) / sampleRate
            let env = envelope(t: t, duration: duration, fadeIn: fadeIn, fadeOut: fadeOut)
            samples[i] = amplitude * env * Float(sin(2 * .pi * frequency * t))
        }
        return buffer
    }

    /// Frequency-sweep (glide) sine tone — useful for whoosh and thud effects.
    private func makeSweep(startFreq: Double,
                           endFreq: Double,
                           duration: Double,
                           amplitude: Float) -> AVAudioPCMBuffer? {
        let frameCount = AVAudioFrameCount(sampleRate * duration)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: monoFormat,
                                            frameCapacity: frameCount) else { return nil }
        buffer.frameLength = frameCount

        let samples = buffer.floatChannelData![0]
        var phase: Double = 0
        for i in 0..<Int(frameCount) {
            let t    = Double(i) / sampleRate
            let freq = startFreq + (endFreq - startFreq) * (t / duration)
            let env  = envelope(t: t, duration: duration, fadeIn: 0.01, fadeOut: 0.06)
            phase   += 2 * .pi * freq / sampleRate
            samples[i] = amplitude * env * Float(sin(phase))
        }
        return buffer
    }

    /// Linear fade-in / fade-out envelope clamped to [0, 1].
    private func envelope(t: Double, duration: Double,
                          fadeIn: Double, fadeOut: Double) -> Float {
        if t < fadeIn {
            return Float(t / fadeIn)
        } else if t > duration - fadeOut {
            return Float((duration - t) / fadeOut)
        }
        return 1.0
    }

    // MARK: - Private: setup

    private func configureAudioSession() {
        let session = AVAudioSession.sharedInstance()
        do {
            // .ambient mixes with other apps (e.g. background music) and does
            // not silence on silent-mode toggle — appropriate for game SFX.
            try session.setCategory(.ambient, mode: .default, options: [.mixWithOthers])
            try session.setActive(true)
        } catch {
            print("SoundManager: audio session setup failed: \(error)")
        }
    }

    private func startEngine() {
        do {
            try engine.start()
        } catch {
            print("SoundManager: engine start failed: \(error)")
        }
    }
}
