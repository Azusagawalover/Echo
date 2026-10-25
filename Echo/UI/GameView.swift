import SwiftUI
import AVFoundation

struct GameView: View {
    @State private var activeRequest: GameRequest
    private let returnTitle: String
    private let onCompletion: ((RhythmResult, Bool) -> Void)?
    init(request: GameRequest, returnTitle: String = "返回声音地图", onCompletion: ((RhythmResult, Bool) -> Void)? = nil) {
        _activeRequest = State(initialValue: request)
        self.returnTitle = returnTitle; self.onCompletion = onCompletion
    }
    var body: some View {
        GameRoundView(request: activeRequest, returnTitle: returnTitle, onCompletion: onCompletion,
                      onNext: { activeRequest = $0 }).id(activeRequest.id)
    }
}

private struct GameRoundView: View {
    @EnvironmentObject private var library: EchoLibrary
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.horizontalSizeClass) private var horizontalSize
    @StateObject private var session: GameSession
    @State private var showExit = false
    @State private var saved = false
    @State private var saveFailed = false
    @State private var practice: GameRequest?
    @State private var snnRecording: SNNLabRecording?
    @State private var replaying: String?
    @State private var replayTask: Task<Void, Never>?
    @State private var practiceSpeed = 0.75
    private let returnTitle: String
    private let onCompletion: ((RhythmResult, Bool) -> Void)?
    private let onNext: (GameRequest) -> Void
    init(request: GameRequest, returnTitle: String, onCompletion: ((RhythmResult, Bool) -> Void)?, onNext: @escaping (GameRequest) -> Void) {
        _session = StateObject(wrappedValue: GameSession(request: request))
        self.returnTitle = returnTitle; self.onCompletion = onCompletion
        self.onNext = onNext
        _practiceSpeed = State(initialValue: request.speed == 1 ? 0.75 : request.speed)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    if let result = session.result {
                        ResultView(result: result, pattern: session.request.pattern, practice: session.isPractice)
                        if saveFailed {
                            Label("本次成绩未能保存。请检查存储空间；原存档未被覆盖。", systemImage: "exclamationmark.triangle")
                                .font(.footnote).foregroundStyle(EchoStyle.colors[2])
                        }
                        if let next = nextLevel(result) {
                            Button { stopReplay(); onNext(GameRequest(pattern: next)) } label: {
                                Label("下一关 · " + next.title, systemImage: "arrow.right")
                            }.buttonStyle(EchoButtonStyle()).accessibilityIdentifier("nextLevel")
                        } else if session.isPractice, result.passed, session.request.speed < 1 {
                            let speed = session.request.speed < 0.75 ? 0.75 : session.request.speed < 0.9 ? 0.9 : 1.0
                            Button {
                                stopReplay(); onNext(GameRequest(pattern: session.request.pattern, mode: session.request.mode, speed: speed, practiceOnly: true))
                            } label: { Text("提速到 \(Int(speed * 100))% · 仍为练习") }
                                .buttonStyle(EchoButtonStyle()).accessibilityIdentifier("speedUpPractice")
                        }
                        Button { stopReplay(); saved = false; session.start(settings: library.state.settings) } label: {
                            Label("再听一次，重新挑战", systemImage: "arrow.counterclockwise")
                        }.buttonStyle(EchoButtonStyle(secondary: nextLevel(result) != nil))
                        practicePanel(result)
                        Button {
                            stopReplay()
                            snnRecording = SNNLabRecording(pattern: session.request.pattern, taps: session.taps,
                                mode: session.request.mode, speed: session.request.speed)
                        } label: { Label("用 SNN 分析这段节奏", systemImage: "waveform.path.ecg") }
                            .buttonStyle(EchoButtonStyle(secondary: true)).accessibilityIdentifier("snnAnalyzeRound")
                        HStack(spacing: 12) {
                            Button { replay(user: false) } label: { Text(replaying == "standard" ? "停止示范" : "听听标准节奏") }
                            Button { replay(user: true) } label: { Text(replaying == "user" ? "停止回放" : "听听我的演奏") }.disabled(session.taps.isEmpty)
                        }.buttonStyle(EchoButtonStyle(secondary: true)).disabled(!library.state.settings.sound)
                        Button(returnTitle) { dismiss() }.font(.subheadline).foregroundStyle(EchoStyle.secondary).padding(10)
                    } else {
                        gameContent
                    }
                }.padding(24).frame(maxWidth: 720).frame(maxWidth: .infinity)
            }.accessibilityHidden(practice != nil)
                .background { GameScenery(chapter: session.request.pattern.chapter) }
                .echoBackground().navigationTitle(session.request.pattern.title).navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                      if practice == nil {
                        Button { if session.phase == .ready || session.phase == .finished { dismiss() } else { session.pause(); showExit = true } } label: { Image(systemName: "xmark") }.accessibilityLabel("退出关卡")
                      }
                    }
                    ToolbarItem(placement: .topBarTrailing) {
                        if practice == nil && session.phase != .ready && session.phase != .finished && session.phase != .paused {
                            Button { session.pause() } label: { Image(systemName: "pause.fill") }.accessibilityLabel("暂停")
                        }
                    }
                }
        }.accessibilityHidden(practice != nil).interactiveDismissDisabled()
            .onChange(of: session.phase) { _, phase in
                if phase == .finished, !saved, let result = session.result {
                    saved = true
                    let firstClear = library.stars(session.request.pattern.id) == 0
                    saveFailed = !library.record(pattern: session.request.pattern, mode: session.request.mode, result: result, practice: session.isPractice)
                    if !saveFailed, firstClear, result.passed, !session.isPractice, session.request.mode == .echo,
                       session.request.pattern.id.hasPrefix("chapter-") {
                        session.audio.celebrate(chapter: session.request.pattern.chapter, settings: library.state.settings)
                    }
                    onCompletion?(result, session.isPractice)
                }
            }
            .onChange(of: scenePhase) { _, value in if value != .active { if replaying != nil { stopReplay() }; session.pause() } }
            .onReceive(NotificationCenter.default.publisher(for: AVAudioSession.interruptionNotification)) { _ in session.pause() }
            .onReceive(NotificationCenter.default.publisher(for: AVAudioSession.routeChangeNotification)) { _ in session.pause() }
            .onDisappear { replayTask?.cancel(); replaying = nil; session.stop() }
            .confirmationDialog("离开这一段回声？", isPresented: $showExit, titleVisibility: .visible) {
                Button("退出关卡", role: .destructive) { dismiss() }
                Button("留在这里", role: .cancel) { }
            } message: { Text("本轮尚未完成，不会记录成绩。") }
            .fullScreenCover(item: $practice) { GameView(request: $0) }
            .sheet(item: $snnRecording) { recording in
                NavigationStack {
                    SNNLabView(recording: recording)
                        .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("完成") { snnRecording = nil } } }
                }
            }
    }

    private var gameContent: some View {
        VStack(spacing: 16) {
            HStack {
                Label(session.request.mode.title, systemImage: session.request.mode.symbol).font(.caption.weight(.medium)).foregroundStyle(EchoStyle.accent)
                Spacer()
                Text("\(Int(session.request.pattern.bpm * session.request.speed)) BPM").font(.caption.monospacedDigit()).foregroundStyle(EchoStyle.secondary)
            }
            ZStack {
                Image("EchoLight").resizable().renderingMode(.template).foregroundStyle(EchoStyle.accent)
                    .scaledToFit().frame(width: horizontalSize == .regular ? 215 : 160).opacity(0.15)
                Circle().stroke(EchoStyle.accent.opacity(0.08), lineWidth: 18).frame(width: horizontalSize == .regular ? 144 : 94, height: horizontalSize == .regular ? 144 : 94)
                Circle().stroke(EchoStyle.accent.opacity(0.25), lineWidth: 1).frame(width: horizontalSize == .regular ? 170 : 120, height: horizontalSize == .regular ? 170 : 120)
                if session.phase == .waiting || session.phase == .countingIn {
                    Text("\(session.countdown)").font(.system(size: 64, weight: .light, design: .rounded)).foregroundStyle(EchoStyle.accent)
                } else {
                    Image(systemName: phaseSymbol).font(.system(size: 48, weight: .light)).foregroundStyle(EchoStyle.accent)
                }
            }.frame(height: horizontalSize == .regular ? 190 : 135).accessibilityHidden(true)
            Text(phaseTitle).font(.system(.title, design: .rounded, weight: .bold)).accessibilityIdentifier("gamePhase")
            Text(session.message).font(.subheadline).foregroundStyle(EchoStyle.secondary).multilineTextAlignment(.center).frame(minHeight: 40)

            if session.phase == .input {
                HStack(spacing: 5) {
                    ForEach(0..<session.request.pattern.notes.count, id: \.self) { index in
                        Capsule().fill(index < session.taps.count ? EchoStyle.accent : .white.opacity(0.12)).frame(height: 5)
                    }
                }.accessibilityLabel("已输入 \(session.taps.count) 个音符")
            }
            PadGrid(lit: session.litLane, enabled: session.phase == .input, compact: horizontalSize != .regular) { lane, time in session.tap(lane, timestamp: time) }

            if EchoAudio.shared.unavailable {
                Label("声音暂不可用，请检查音频设备。可退出后重试。", systemImage: "speaker.slash").font(.caption).foregroundStyle(EchoStyle.colors[2])
            }
            if session.isPractice {
                Text("练习记录 · 不计入章节解锁").font(.caption).foregroundStyle(EchoStyle.colors[2])
            }
            switch session.phase {
            case .ready:
                Text(session.request.mode.explanation).font(.subheadline).foregroundStyle(EchoStyle.secondary).multilineTextAlignment(.center)
                Button { saved = false; session.start(settings: library.state.settings) } label: { Label("准备好了，开始", systemImage: "play.fill") }.buttonStyle(EchoButtonStyle()).accessibilityIdentifier("beginRound")
            case .paused:
                Button { session.resume(settings: library.state.settings) } label: { Label("从短句开头继续", systemImage: "play.fill") }.buttonStyle(EchoButtonStyle())
            case .input:
                Button { session.finish() } label: { Text("完成复现") }.buttonStyle(EchoButtonStyle()).accessibilityIdentifier("finishRound")
                if session.request.mode == .echo {
                    Button("没记住？重听一遍（转为练习）") { session.start(settings: library.state.settings, replay: true) }.font(.caption).foregroundStyle(EchoStyle.secondary)
                }
            default:
                Label("正在播放，请先聆听", systemImage: "ear").font(.footnote).foregroundStyle(EchoStyle.secondary).padding(.vertical, 16)
            }
        }
    }
    private var phaseTitle: String {
        switch session.phase {
        case .ready: return "每一声，都有回应"
        case .countingIn: return "准备聆听"
        case .listening: return "仔细聆听"
        case .waiting: return "准备跟奏"
        case .input: return "轮到你了"
        case .paused: return "让回声停一会儿"
        case .finished: return "这一段，属于你"
        }
    }
    private var phaseSymbol: String {
        switch session.phase {
        case .listening: return "ear.badge.waveform"
        case .input: return "hand.tap"
        case .paused: return "pause"
        default: return "waveform"
        }
    }
    private func nextLevel(_ result: RhythmResult) -> RhythmPattern? {
        guard onCompletion == nil, result.passed, !session.isPractice, session.request.mode == .echo else { return nil }
        return library.nextChapterLevel(after: session.request.pattern.id)
    }
    private func practicePanel(_ result: RhythmResult) -> some View {
        let plan = PracticePlan.analyze(result, pattern: session.request.pattern)
        return VStack(alignment: .leading, spacing: 14) {
            Label(plan.title, systemImage: "scope").font(.headline).foregroundStyle(EchoStyle.accent)
            Text(plan.detail).font(.subheadline).foregroundStyle(EchoStyle.secondary)
            Picker("练习速度", selection: $practiceSpeed) {
                ForEach([0.6, 0.75, 0.9, 1.0], id: \.self) { Text("\(Int($0 * 100))%").tag($0) }
            }.pickerStyle(.segmented).accessibilityIdentifier("practiceSpeed")
            HStack(spacing: 10) {
                Button {
                    stopReplay(); practice = GameRequest(pattern: session.request.pattern, mode: session.request.mode, speed: practiceSpeed, practiceOnly: true)
                } label: { Text("完整练习") }.accessibilityIdentifier("fullPractice")
                Button {
                    stopReplay(); practice = GameRequest(pattern: plan.segment(of: session.request.pattern), mode: session.request.mode, speed: practiceSpeed, practiceOnly: true)
                } label: { Text("易错片段") }.accessibilityIdentifier("segmentPractice")
            }.buttonStyle(EchoButtonStyle(secondary: true))
            Text("按本次顺序与节奏偏差推荐。所有速度的练习均不解锁章节。")
                .font(.caption2).foregroundStyle(EchoStyle.secondary)
        }.echoPanel()
    }
    private func replay(user: Bool) {
        let key = user ? "user" : "standard"
        if replaying == key { stopReplay(); return }
        stopReplay(); replaying = key
        let events = user ? session.taps.map { SoundEvent(lane: $0.lane, time: $0.time) } : session.request.pattern.notes.map {
            SoundEvent(lane: $0.lane, time: session.request.pattern.time(of: $0, speed: session.request.speed))
        }
        session.audio.schedule(events, start: ProcessInfo.processInfo.systemUptime + 0.3, enabled: library.state.settings.sound)
        let length = max(1, (events.map(\.time).max() ?? 0) + 0.8)
        replayTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: UInt64(length * 1_000_000_000))
            if !Task.isCancelled { stopReplay() }
        }
    }
    private func stopReplay() { replayTask?.cancel(); replayTask = nil; replaying = nil; session.audio.stopSequence() }
}

struct ResultView: View {
    let result: RhythmResult
    let pattern: RhythmPattern
    var practice: Bool
    @State private var details = false
    var body: some View {
        VStack(spacing: 24) {
            EchoResultTicket(result: result, pattern: pattern, practice: practice)
            Text("顺序全对且得分至少 75 分即可通关。平均偏差仅统计正确匹配的音符。")
                .font(.caption).foregroundStyle(EchoStyle.secondary).frame(maxWidth: .infinity, alignment: .leading)
            Text(result.advice).font(.subheadline).foregroundStyle(EchoStyle.secondary).frame(maxWidth: .infinity, alignment: .leading)
            DisclosureGroup(isExpanded: $details) {
              VStack(alignment: .leading, spacing: 17) {
                SectionTitle(title: "看见你的节奏", caption: "上：标准 / 下：你")
                RhythmTimeline(judgements: result.judgements)
                HStack { Text("多点：\(result.extraCount)"); Spacer(); Text("偏差以各玩法的起点计算") }.font(.caption2).foregroundStyle(EchoStyle.secondary)
              }.padding(.top, 16)
            VStack(spacing: 0) {
                ForEach(result.judgements) { note in
                    HStack {
                        Text(String(format: "%02d", note.id + 1)).font(.caption.monospacedDigit()).foregroundStyle(EchoStyle.secondary).frame(width: 28)
                        Image(systemName: EchoStyle.symbols[note.lane]).foregroundStyle(EchoStyle.colors[note.lane])
                        Text(note.label).font(.subheadline)
                        Spacer()
                        if let delta = note.delta { Text(String(format: "%+.0f ms", delta * 1000)).font(.caption.monospacedDigit()).foregroundStyle(EchoStyle.secondary) }
                        else { Text("—").foregroundStyle(EchoStyle.secondary) }
                    }.padding(.vertical, 12)
                    if note.id < result.judgements.count - 1 { Divider().overlay(.white.opacity(0.05)) }
                }
              }
            } label: { Label("展开逐拍分析", systemImage: "waveform.path.ecg").font(.subheadline.weight(.semibold)) }
                .tint(EchoStyle.accent).echoPanel().accessibilityIdentifier("resultDetails")
        }
    }
}

struct RhythmTimeline: View {
    var judgements: [NoteJudgement]
    var body: some View {
        GeometryReader { geometry in
            let duration = max(1, (judgements.map(\.target) + judgements.compactMap(\.actual)).max() ?? 1) + 0.4
            let width = max(1, geometry.size.width - 22)
            ZStack(alignment: .topLeading) {
                ForEach([20.0, 68.0], id: \.self) { y in
                    Path { path in path.move(to: CGPoint(x: 10, y: y)); path.addLine(to: CGPoint(x: geometry.size.width - 10, y: y)) }.stroke(.white.opacity(0.13), lineWidth: 1)
                }
                ForEach(judgements) { note in
                    Circle().fill(EchoStyle.colors[note.lane]).frame(width: 12, height: 12)
                        .position(x: 11 + max(0, note.target) / duration * width, y: 20)
                    if let actual = note.actual {
                        Path { path in path.move(to: CGPoint(x: 11 + max(0, note.target) / duration * width, y: 28)); path.addLine(to: CGPoint(x: 11 + max(0, actual) / duration * width, y: 60)) }
                            .stroke(EchoStyle.colors[note.lane].opacity(0.25), style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
                        Image(systemName: note.correctLane ? "circle.fill" : "xmark.circle.fill").font(.system(size: 12)).foregroundStyle(note.correctLane ? EchoStyle.colors[note.lane] : .red)
                            .position(x: 11 + max(0, actual) / duration * width, y: 68)
                    } else {
                        Image(systemName: "minus.circle").font(.system(size: 12)).foregroundStyle(EchoStyle.secondary).position(x: 11 + note.target / duration * width, y: 68)
                    }
                }
            }
        }.frame(height: 90).accessibilityLabel("标准与输入节奏对照，详细偏差见下方逐音符列表")
    }
}
