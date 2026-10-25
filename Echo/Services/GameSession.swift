import Foundation
import Combine

struct GameRequest: Identifiable {
    let id = UUID()
    var pattern: RhythmPattern
    var mode: PlayMode = .echo
    var speed = 1.0
    var practiceOnly = false
}

@MainActor final class GameSession: ObservableObject {
    enum Phase { case ready, countingIn, listening, waiting, input, paused, finished }
    let request: GameRequest
    @Published private(set) var phase: Phase = .ready
    @Published private(set) var taps: [TapEvent] = []
    private(set) var elapsed = 0.0
    @Published private(set) var litLane: Int?
    @Published private(set) var message = "准备好听见回声了吗？"
    @Published private(set) var countdown = 0
    @Published private(set) var result: RhythmResult?
    @Published private(set) var usedReplay = false
    private var timer: Timer?
    private var startTime = 0.0
    private var inputStart: Double?
    private var limit = 0.0
    private var settings = EchoSettings()
    private var hasStarted = false
    private var replayCount = 0
    let audio: EchoAudio
    var isPractice: Bool { request.practiceOnly || request.speed != 1 || usedReplay }
    var beat: Double { 60 / request.pattern.bpm / request.speed }
    var duration: Double { request.pattern.time(of: request.pattern.notes.last!, speed: request.speed) + max(beat * 2, 1) }

    init(request: GameRequest, audio: EchoAudio? = nil) { self.request = request; self.audio = audio ?? .shared }
    deinit { timer?.invalidate() }

    func start(settings: EchoSettings, replay: Bool = false) {
        stop()
        self.settings = settings
        if replay { replayCount += 1 } else { replayCount = 0 }
        usedReplay = replayCount > 0
        hasStarted = true; taps = []; result = nil; inputStart = nil; elapsed = 0; litLane = nil
        audio.prepare(palette: settings.palette)
        let now = ProcessInfo.processInfo.systemUptime
        if request.mode == .echo || request.mode == .silence {
            startTime = now + 3
            phase = .countingIn; countdown = 3
            message = "先放好双手 · 倒数后聆听示范"
            audio.schedule(request.pattern.notes.map { SoundEvent(lane: $0.lane, time: request.pattern.time(of: $0, speed: request.speed)) }, start: startTime, enabled: settings.sound)
        } else {
            prepareGuided(at: now)
        }
        let ticker = Timer(timeInterval: 1.0 / 60, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in self?.update() }
        }
        RunLoop.main.add(ticker, forMode: .common); timer = ticker
    }

    private func update() {
        let now = ProcessInfo.processInfo.systemUptime
        let t = now - startTime
        elapsed = max(0, t)
        if phase == .countingIn {
            let count = max(1, Int(ceil(-t)))
            if countdown != count { countdown = count }
            if t >= 0 {
                phase = .listening
                message = request.mode == .silence ? "先听完整节奏 · 下一遍提示会消失" : "仔细听 · 记住颜色和间隔"
            }
        } else if phase == .listening {
            let light = settings.visualCues ? request.pattern.notes.last(where: {
                let d = t - request.pattern.time(of: $0, speed: request.speed)
                return d >= 0 && d < 0.16
            })?.lane : nil
            if litLane != light { litLane = light }
            if t >= duration {
                audio.stopSequence(); litLane = nil
                if request.mode == .silence {
                    prepareGuided(at: now)
                } else {
                    phase = .input; message = "轮到你了 · 点击开始复现"
                    startTime = now; inputStart = nil; limit = duration + 12
                }
            }
        } else if phase == .waiting {
            let count = min(4, max(1, Int(ceil(-t / beat))))
            if countdown != count { countdown = count }
            if t >= -0.15 { phase = .input; message = request.mode == .silence ? "提示会消失 · 保持节拍" : "跟着光点 · 同步点击"; limit = duration }
        } else if phase == .input {
            if request.mode != .echo {
                let guide = request.mode == .silence ? Array(request.pattern.notes.prefix(2)) : request.pattern.notes
                let light = settings.visualCues ? guide.last(where: {
                    let d = t - request.pattern.time(of: $0, speed: request.speed)
                    return d >= 0 && d < 0.16
                })?.lane : nil
                if litLane != light { litLane = light }
            }
            let end = request.mode == .echo ? (inputStart.map { $0 + duration + 0.6 } ?? (startTime + limit)) : (startTime + limit + 0.5)
            if now >= end { finish() }
        }
    }

    func tap(_ lane: Int, timestamp: Double = ProcessInfo.processInfo.systemUptime) {
        guard phase == .input, taps.count < 64 else { return }
        if request.mode != .echo, timestamp < startTime - 0.15 { return }
        audio.hit(lane, settings: settings)
        if inputStart == nil { inputStart = timestamp }
        let time = request.mode == .echo ? timestamp - inputStart! : timestamp - startTime - settings.offsetMS / 1000
        taps.append(TapEvent(lane: lane, time: max(0, time)))
        message = "已复现 \(taps.count) / \(request.pattern.notes.count) 个音符"
    }
    func finish() {
        guard phase == .input else { return }
        stop(); litLane = nil
        result = RhythmScorer.evaluate(pattern: request.pattern, taps: taps, mode: request.mode, speed: request.speed)
        phase = .finished
    }
    func pause() {
        guard hasStarted, phase != .finished, phase != .ready, phase != .paused else { return }
        stop(); litLane = nil; phase = .paused; message = "已暂停 · 继续时从短句开头重播"
    }
    func resume(settings: EchoSettings) { start(settings: settings, replay: usedReplay) }
    func stop() { timer?.invalidate(); timer = nil; audio.stopSequence() }
    private func prepareGuided(at now: Double) {
        startTime = now + 0.7 + beat * 4
        phase = .waiting; message = "跟随倒数 · 准备进入节拍"
        var events = (0..<4).map { SoundEvent(lane: 4, time: Double($0 - 4) * beat) }
        let guide = request.mode == .silence ? Array(request.pattern.notes.prefix(2)) : request.pattern.notes
        events += guide.map { SoundEvent(lane: $0.lane, time: request.pattern.time(of: $0, speed: request.speed)) }
        audio.schedule(events, start: startTime, enabled: settings.sound)
    }
}
