import Foundation

#if canImport(UIKit)
import AVFoundation
import UIKit

struct SoundEvent { var lane: Int; var time: Double }

@MainActor final class EchoAudio: ObservableObject {
    static let shared = EchoAudio()
    @Published private(set) var unavailable = false
    private var sounds: [Data] = []
    private var live: [[AVAudioPlayer]] = []
    private var cursors = [0, 0, 0, 0]
    private var scheduled: [AVAudioPlayer] = []
    private var prepared = false
    private var palette: SoundPalette = .crystal
    private let noteVolume: Float = 0.78

    func prepare(palette selected: SoundPalette? = nil) {
        if let selected, selected != palette {
            stopAll(); prepared = false; palette = selected
        }
        guard !prepared else { return }
        prepared = true
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
            try AVAudioSession.sharedInstance().setActive(true)
            sounds = (0..<4).map { EchoToneSynthesizer.wave(lane: $0, palette: palette) }
            sounds.append(EchoToneSynthesizer.wave(lane: 4, palette: .crystal))
            live = try (0..<4).map { lane in
                try (0..<4).map { _ in let player = try AVAudioPlayer(data: sounds[lane]); player.prepareToPlay(); return player }
            }
            unavailable = false
        } catch { unavailable = true; prepared = false }
    }

    func hit(_ lane: Int, settings: EchoSettings) {
        prepare(palette: settings.palette)
        guard (0..<4).contains(lane) else { return }
        if settings.sound, live.count == 4 {
            let player = live[lane][cursors[lane] % 4]; cursors[lane] += 1
            player.stop(); player.currentTime = 0; player.volume = noteVolume; player.play()
        }
        if settings.haptics { UIImpactFeedbackGenerator(style: .light).impactOccurred() }
    }

    func schedule(_ events: [SoundEvent], start: Double, enabled: Bool, palette: SoundPalette? = nil) {
        prepare(palette: palette); stopSequence()
        guard enabled, !unavailable else { return }
        do {
            try AVAudioSession.sharedInstance().setActive(true)
            scheduled = try events.map { event in
                let player = try AVAudioPlayer(data: sounds[min(4, max(0, event.lane))])
                player.volume = event.lane == 4 ? 0.22 : noteVolume
                player.prepareToPlay()
                return player
            }
            for (event, player) in zip(events, scheduled) {
                let delay = start + event.time - ProcessInfo.processInfo.systemUptime
                if delay >= 0 { player.play(atTime: player.deviceCurrentTime + delay) }
            }
        } catch { unavailable = true }
    }
    func stopSequence() { scheduled.forEach { $0.stop() }; scheduled.removeAll() }
    func stopAll() { stopSequence(); live.flatMap { $0 }.forEach { $0.stop() } }

    func celebrate(chapter: Int, settings: EchoSettings) {
        let lanes = (0..<8).map { ($0 + max(0, chapter)) % 4 }
        schedule(lanes.enumerated().map { SoundEvent(lane: $0.element, time: Double($0.offset) * 0.18) },
                 start: ProcessInfo.processInfo.systemUptime + 0.12, enabled: settings.sound, palette: settings.palette)
    }

}
#endif

/// 同一音垫在示范和触摸时使用相同 PCM；每条音轨有独立的发声结构。
enum EchoToneSynthesizer {
    static let sampleRate = 44100
    static let voiceNames = ["清脆水滴", "明亮铃声", "低沉木鼓", "短促沙锤"]

    static func samples(lane: Int, palette: SoundPalette) -> [Double] {
        guard (0...4).contains(lane) else { return [] }
        let brightness: Double
        let release: Double
        let modulation: Double
        switch palette {
        case .crystal: (brightness, release, modulation) = (1, 1, 0)
        case .keys: (brightness, release, modulation) = (0.62, 0.88, 0)
        case .wood: (brightness, release, modulation) = (0.76, 1.45, 0)
        case .electronic: (brightness, release, modulation) = (1.12, 1.15, 0.45)
        }
        let durations = [0.20, 0.38, 0.18, 0.095, 0.065]
        let count = Int(durations[lane] * Double(sampleRate))
        var values = [Double](); values.reserveCapacity(count)
        let paletteIndex = SoundPalette.allCases.firstIndex(of: palette) ?? 0
        var seed = UInt64(0xEC40 + lane * 97 + paletteIndex * 131)
        var noiseLow = 0.0
        var noiseBand = 0.0
        var noiseSmooth = 0.0
        for index in 0..<count {
            let t = Double(index) / Double(sampleRate)
            seed = seed &* 6364136223846793005 &+ 1442695040888963407
            let noise = Double(seed >> 32) / Double(UInt32.max) * 2 - 1
            let signal: Double
            switch lane {
            case 0:
                // 水滴先亮后落，积分相位使音高滑动连续，不产生接缝。
                let phase = 2 * Double.pi * (560 * t + 420 * 0.018 * (1 - exp(-t / 0.018)))
                let body = sin(phase + modulation * sin(phase * 2) * exp(-t * 45))
                let glint = 0.2 * brightness * sin(phase * 2.08) * exp(-t * 45)
                signal = (body + glint) * exp(-t * 23 * release)
            case 1:
                // 非整数倍泛音和较长余音，形成与水滴明显不同的铃声。
                let phase = 2 * Double.pi * 1174.66 * t
                let fundamental = 0.72 * sin(phase + modulation * sin(phase * 2)) * exp(-t * 9 * release)
                let overtone = 0.23 * brightness * sin(phase * 2.76) * exp(-t * 19 * release)
                let sparkle = 0.1 * brightness * sin(phase * 4.07) * exp(-t * 32 * release)
                signal = fundamental + overtone + sparkle
            case 2:
                // 低频鼓身加短暂木质敲击；中频泛音减轻手机扬声器低频不足的影响。
                let phase = 2 * Double.pi * (185 * t + 130 * 0.012 * (1 - exp(-t / 0.012)))
                let body = sin(phase) * exp(-t * 29 * release)
                let knock = 0.4 * sin(phase * 2.43) * exp(-t * 62 * release)
                signal = body + knock + 0.15 * brightness * noise * exp(-t * 160)
            case 3:
                // 带限噪声产生短促沙声，避免第四个音符仍像另一颗低音。
                noiseLow += 0.12 * (noise - noiseLow)
                noiseBand += 0.32 * ((noise - noiseLow) - noiseBand)
                noiseSmooth += 0.32 * (noiseBand - noiseSmooth)
                let body = noiseSmooth * exp(-t * 53 * release)
                let tick = 0.12 * brightness * sin(2 * Double.pi * 3400 * t) * exp(-t * 105)
                signal = body + tick
            default:
                signal = sin(2 * Double.pi * 1450 * t) * exp(-t * 85)
            }
            let attack = min(1, t / (lane == 3 ? 0.001 : 0.002))
            let tail = min(1, Double(count - 1 - index) / (Double(sampleRate) * 0.005))
            values.append(signal * attack * tail)
        }
        // 对齐起始段能量并留出余量，避免低鼓太轻、铃声或沙锤突然刺耳。
        let window = min(count, Int(Double(sampleRate) * 0.12))
        let rms = sqrt(values.prefix(window).reduce(0) { $0 + $1 * $1 } / Double(window))
        let peak = values.map(abs).max() ?? 0
        let target = [0.17, 0.15, 0.19, 0.14, 0.12][lane]
        let gain = min(target / max(rms, 0.0001), 0.7 / max(peak, 0.0001))
        return values.map { $0 * gain }
    }

    static func wave(lane: Int, palette: SoundPalette) -> Data {
        pcm(samples: samples(lane: lane, palette: palette))
    }

    static func pcm(samples: [Double]) -> Data {
        let count = samples.count, rate = sampleRate
        var data = Data()
        func word<T: FixedWidthInteger>(_ value: T) { var v = value.littleEndian; withUnsafeBytes(of: &v) { data.append(contentsOf: $0) } }
        data.append(contentsOf: "RIFF".utf8); word(UInt32(36 + count * 2)); data.append(contentsOf: "WAVEfmt ".utf8)
        word(UInt32(16)); word(UInt16(1)); word(UInt16(1)); word(UInt32(rate)); word(UInt32(rate * 2))
        word(UInt16(2)); word(UInt16(16)); data.append(contentsOf: "data".utf8); word(UInt32(count * 2))
        for sample in samples {
            let value = sample.isFinite ? min(1, max(-1, sample)) : 0
            word(Int16((value * 32767).rounded()))
        }
        return data
    }
}
