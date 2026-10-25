import SwiftUI
import AVFoundation

struct TutorialView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @EnvironmentObject private var library: EchoLibrary
    private enum Stage { case ready, listening, input, success, retry }
    @State private var step = 0
    @State private var stage: Stage = .ready
    @State private var lit: Int?
    @State private var taps: [TapEvent] = []
    @State private var origin: Double?
    @State private var reference = 0.0
    @State private var message = "先听两个声音，再按相同顺序点击。"
    @State private var task: Task<Void, Never>?
    private let titles = ["先认出声音", "跟着光点点击", "最后，凭记忆回应"]
    private var pattern: RhythmPattern {
        let ticks = [[0, 2], [0, 2, 4], [0, 2, 3, 6]][step]
        let lanes = [[0, 1], [0, 1, 0], [0, 1, 2, 3]][step]
        return RhythmPattern(id: "lesson-\(step)", title: titles[step], detail: "互动教学", chapter: 0, bpm: 80,
                             notes: zip(ticks, lanes).map { BeatNote(tick: $0, lane: $1) })
    }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                HStack {
                    Text("初次聆听 / \(step + 1) · 3").font(.caption.weight(.bold)).foregroundStyle(EchoStyle.accent)
                    Spacer()
                    Image(systemName: stage == .success ? "checkmark.circle.fill" : "ear.badge.waveform")
                        .foregroundStyle(EchoStyle.accent).font(.title)
                }
                ProgressView(value: Double(step) + (stage == .success ? 1 : 0), total: 3).tint(EchoStyle.accent)
                Text(titles[step]).font(.system(.largeTitle, design: .rounded, weight: .bold))
                Text(step == 0 ? "不用抢时间，先记住雨滴和月光的顺序。" : step == 1 ? "亮起时点击对应音垫，感受两声之间的间隔。" : "听完再点。第一下决定起点，后面的间隔要与示范一致。")
                    .font(.subheadline).foregroundStyle(EchoStyle.secondary)
                Text(message).font(.headline).frame(maxWidth: .infinity, minHeight: 52, alignment: .leading)
                    .accessibilityIdentifier("lessonMessage").echoPanel()
                PadGrid(lit: lit, enabled: stage == .input, compact: true) { lane, time in tap(lane, time) }
                if stage == .ready || stage == .retry {
                    Button { begin() } label: { Label(stage == .retry ? "再示范一次" : "开始这一小步", systemImage: "play.fill") }
                        .buttonStyle(EchoButtonStyle()).accessibilityIdentifier("beginLesson")
                }
                if stage == .success {
                    Button {
                        if step == 2 { complete() }
                        else { step += 1; stage = .ready; message = "准备好后开始；这一步不计入成绩。" }
                    } label: { Text(step == 2 ? "学会了，开始声音之旅" : "继续下一小步") }
                        .buttonStyle(EchoButtonStyle()).accessibilityIdentifier("nextLesson")
                }
                if stage == .input { Text("已点击 \(taps.count) / \(pattern.notes.count) 次").font(.caption).foregroundStyle(EchoStyle.secondary) }
                Text("教学不影响成绩和章节。每次出错都可以重新听、重新试。")
                    .font(.footnote).foregroundStyle(EchoStyle.secondary)
            }.padding(24).frame(maxWidth: 650).frame(maxWidth: .infinity)
        }.safeAreaInset(edge: .bottom) {
            Button("暂时跳过，直接试玩") { complete() }
                .font(.subheadline).foregroundStyle(EchoStyle.secondary).padding(18).frame(maxWidth: .infinity)
                .background(EchoStyle.background).accessibilityIdentifier("finishTutorial")
        }.echoBackground().presentationDragIndicator(.visible)
            .onDisappear { cancel() }
            .onChange(of: scenePhase) { _, value in if value != .active { interrupt() } }
            .onReceive(NotificationCenter.default.publisher(for: AVAudioSession.interruptionNotification)) { _ in interrupt() }
            .onReceive(NotificationCenter.default.publisher(for: AVAudioSession.routeChangeNotification)) { _ in interrupt() }
    }
    private func begin() {
        cancel(); taps = []; origin = nil
        let p = pattern
        reference = ProcessInfo.processInfo.systemUptime + 0.7
        stage = step == 1 ? .input : .listening
        message = step == 1 ? "准备，跟着亮起的音垫点击。" : "先聆听，暂时不用点击。"
        EchoAudio.shared.schedule(p.notes.map { SoundEvent(lane: $0.lane, time: p.time(of: $0)) },
            start: reference, enabled: library.state.settings.sound, palette: library.state.settings.palette)
        task = Task { @MainActor in
            for note in p.notes {
                let delay = reference + p.time(of: note) - ProcessInfo.processInfo.systemUptime
                if delay > 0 { try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000)) }
                guard !Task.isCancelled else { return }
                lit = note.lane
                try? await Task.sleep(nanoseconds: 200_000_000)
                guard !Task.isCancelled else { return }
                lit = nil
            }
            try? await Task.sleep(nanoseconds: 650_000_000)
            guard !Task.isCancelled else { return }
            if step == 1 { finish() }
            else { stage = .input; message = step == 0 ? "轮到你了：雨滴，然后月光。" : "轮到你了，按记忆复现顺序和间隔。" }
        }
    }
    private func tap(_ lane: Int, _ timestamp: Double) {
        guard stage == .input, taps.count < pattern.notes.count else { return }
        if step == 1, timestamp < reference - 0.15 { return }
        EchoAudio.shared.hit(lane, settings: library.state.settings)
        if origin == nil { origin = timestamp }
        taps.append(TapEvent(lane: lane, time: max(0, timestamp - (step == 1 ? reference + library.state.settings.offsetMS / 1000 : origin!))))
        if taps.count == pattern.notes.count { finish() }
    }
    private func finish() {
        cancel()
        let result = RhythmScorer.evaluate(pattern: pattern, taps: taps, mode: step == 1 ? .follow : .echo)
        let passed = step == 0 ? result.order == 100 : result.order == 100 && result.meanError <= 0.25
        stage = passed ? .success : .retry
        message = passed ? (step == 2 ? "你已经学会了！听、记、回应，就是回声。" : "做到了！我们再前进一小步。") : (result.order < 100 ? "有一个声音没对上，没关系，再看一次示范。" : "顺序对了，再听听间隔：别太快，也别等太久。")
    }
    private func cancel() { task?.cancel(); task = nil; lit = nil; EchoAudio.shared.stopSequence() }
    private func interrupt() { cancel(); stage = .ready; message = "教学已暂停，准备好后可以重新开始这一小步。" }
    private func complete() { cancel(); library.sawTutorial(); dismiss() }
}
