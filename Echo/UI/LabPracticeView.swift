import SwiftUI
import AVFoundation

struct LabPracticeConfiguration: Identifiable {
    let id = UUID()
    let pattern: RhythmPattern
    var mode: PlayMode = .echo
    var speed = 1.0
    var rounds = 1
    var progressive = false
    var title = "演奏实验短句"
}

struct LabPracticeView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    let configuration: LabPracticeConfiguration
    let completed: (SNNLabRecording) -> Void
    @State private var sequence: LabPracticeSequence
    @State private var feedback = false
    @State private var lastRecording: SNNLabRecording?
    @State private var lastResult: RhythmResult?
    @State private var autoAllowed = true
    @State private var delivered = false

    init(configuration: LabPracticeConfiguration, completed: @escaping (SNNLabRecording) -> Void) {
        self.configuration = configuration; self.completed = completed
        _sequence = State(initialValue: LabPracticeSequence(rounds: configuration.rounds, speed: configuration.speed,
                                                           progressive: configuration.progressive))
    }
    var body: some View {
        NavigationStack {
            Group {
                if feedback, let lastResult, let lastRecording {
                    VStack(spacing: 22) {
                        Image(systemName: lastResult.order == 100 ? "checkmark.circle" : "scope").font(.largeTitle).foregroundStyle(EchoStyle.accent)
                        Text("完成第 \(sequence.completed) / \(sequence.rounds) 轮").font(.title2.bold())
                        Text("本轮顺序 \(lastResult.order)% · 规则练习分 \(lastResult.score)") .font(.headline)
                        Text(sequence.finished ? "将这段演奏送回实验室。不会自动保存。" :
                                "下一轮 \(Int(sequence.speed * 100))% 速度。顺序全对且至少 85 分才会自动提速。")
                            .font(.subheadline).foregroundStyle(EchoStyle.secondary).multilineTextAlignment(.center)
                        if !sequence.finished {
                            Button("继续下一轮") { autoAllowed = true; advance() }.buttonStyle(EchoButtonStyle())
                        }
                        Button(sequence.finished ? "完成并分析" : "结束循环并分析本轮") { finish(lastRecording) }
                            .buttonStyle(EchoButtonStyle(secondary: true))
                        Text(sequence.finished ? "本组已完成，回到实验室查看结果。" : autoAllowed ? "短暂停顿后自动继续；最多三轮。" : "自动循环已因离开前台而暂停，请手动继续。")
                            .font(.caption).foregroundStyle(EchoStyle.secondary)
                    }.padding(24).frame(maxWidth: 620).frame(maxWidth: .infinity)
                        .task(id: sequence.completed) {
                            do { try await Task.sleep(nanoseconds: 1_500_000_000) } catch { return }
                            guard !Task.isCancelled, autoAllowed, scenePhase == .active else { return }; advance()
                        }
                } else {
                    LabPracticeRound(request: GameRequest(pattern: configuration.pattern, mode: configuration.mode,
                        speed: sequence.speed, practiceOnly: true), round: sequence.completed + 1, rounds: sequence.rounds,
                        autostart: sequence.completed > 0) { recording, result in
                            lastRecording = recording; lastResult = result
                            sequence.complete(passed: result.order == 100 && result.score >= 85); feedback = true
                        }.id(sequence.completed)
                }
            }.echoBackground().navigationTitle(configuration.title).navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .topBarLeading) { Button("取消") { dismiss() } } }
        }.interactiveDismissDisabled()
            .onChange(of: scenePhase) { _, phase in if phase != .active { autoAllowed = false } }
            .onReceive(NotificationCenter.default.publisher(for: AVAudioSession.interruptionNotification)) { _ in autoAllowed = false }
            .onReceive(NotificationCenter.default.publisher(for: AVAudioSession.routeChangeNotification)) { _ in autoAllowed = false }
    }
    private func advance() {
        if sequence.finished, let lastRecording { finish(lastRecording) } else { feedback = false }
    }
    private func finish(_ recording: SNNLabRecording) {
        guard !delivered else { return }; delivered = true; completed(recording); dismiss()
    }
}

private struct LabPracticeRound: View {
    @EnvironmentObject private var library: EchoLibrary
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var session: GameSession
    let round: Int
    let rounds: Int
    let autostart: Bool
    let finished: (SNNLabRecording, RhythmResult) -> Void
    @State private var delivered = false
    @State private var tappedLane: Int?
    @State private var tapLightTask: Task<Void, Never>?
    init(request: GameRequest, round: Int, rounds: Int, autostart: Bool, finished: @escaping (SNNLabRecording, RhythmResult) -> Void) {
        _session = StateObject(wrappedValue: GameSession(request: request))
        self.round = round; self.rounds = rounds; self.autostart = autostart; self.finished = finished
    }
    var body: some View {
        ScrollView {
            VStack(spacing: 21) {
                HStack {
                    Text("第 \(round) / \(rounds) 轮"); Spacer()
                    Text("\(Int(session.request.speed * 100))% · \(session.request.mode.title)")
                }.font(.caption).foregroundStyle(EchoStyle.accent)
                HStack(spacing: 5) {
                    ForEach(0..<rounds, id: \.self) { index in
                        Capsule().fill(index < round - 1 ? EchoStyle.accent : index == round - 1 ? EchoStyle.accent.opacity(0.4) : .white.opacity(0.1)).frame(height: 3)
                    }
                }.accessibilityHidden(true)
                stage
                Text(session.message).font(.subheadline).foregroundStyle(EchoStyle.secondary).multilineTextAlignment(.center)
                PatternDots(pattern: session.request.pattern)
                PadGrid(lit: tappedLane ?? session.litLane, enabled: session.phase == .input, compact: true) { lane, time in
                    session.tap(lane, timestamp: time)
                    tappedLane = lane; tapLightTask?.cancel()
                    tapLightTask = Task { @MainActor in
                        do { try await Task.sleep(nanoseconds: 160_000_000) } catch { return }
                        tappedLane = nil
                    }
                }
                HStack {
                    Label("\(Int(session.request.speed * 100))%", systemImage: "speedometer")
                    Spacer()
                    Text(round < rounds ? "本轮后按达标情况调整速度" : "最后一轮 · 完成后查看分析")
                }.font(.caption2).foregroundStyle(EchoStyle.secondary)
                if session.phase == .ready {
                    Text("聆听 \(session.request.pattern.notes.count) 个音符，再保持顺序与间隔。所有速度均是独立练习。")
                        .font(.subheadline).foregroundStyle(EchoStyle.secondary)
                }
                Text("不记正式成绩、不解锁、不自动保存；结束后可主动留下最后一轮。")
                    .font(.caption).foregroundStyle(EchoStyle.secondary)
                if EchoAudio.shared.unavailable { Text("音频暂不可用，请检查声音设备；可取消后重试。") .font(.caption).foregroundStyle(EchoStyle.colors[2]) }
            }.padding(24).frame(maxWidth: 620).frame(maxWidth: .infinity)
        }.safeAreaInset(edge: .bottom) {
            roundActions.padding(.horizontal, 24).padding(.vertical, 12)
                .frame(maxWidth: 620).frame(maxWidth: .infinity).background(EchoStyle.background.opacity(0.97))
        }.toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                if session.phase != .ready && session.phase != .finished && session.phase != .paused {
                    Button { session.pause() } label: { Image(systemName: "pause.fill") }.accessibilityLabel("暂停实验演奏")
                }
            }
        }.task { if autostart, scenePhase == .active { session.start(settings: library.state.settings) } }
            .onChange(of: session.phase) { _, phase in
                if phase == .finished, !delivered, let result = session.result {
                    delivered = true
                    finished(SNNLabRecording(pattern: session.request.pattern, taps: session.taps,
                        mode: session.request.mode, speed: session.request.speed), result)
                }
            }
            .onChange(of: scenePhase) { _, phase in if phase != .active { session.pause() } }
            .onReceive(NotificationCenter.default.publisher(for: AVAudioSession.interruptionNotification)) { _ in session.pause() }
            .onReceive(NotificationCenter.default.publisher(for: AVAudioSession.routeChangeNotification)) { _ in session.pause() }
            .onDisappear { tapLightTask?.cancel(); session.stop() }
    }
    @ViewBuilder private var roundActions: some View {
        if session.phase == .ready {
            Button { session.start(settings: library.state.settings) } label: { Label("聆听并开始", systemImage: "play.fill") }
                .buttonStyle(EchoButtonStyle()).accessibilityIdentifier("snnBegin")
        } else if session.phase == .input {
            Button { session.finish() } label: { Text("完成，送入实验室") }
                .buttonStyle(EchoButtonStyle()).accessibilityIdentifier("snnFinish")
        } else if session.phase == .paused {
            Button { session.resume(settings: library.state.settings) } label: { Text("从短句开头继续") }.buttonStyle(EchoButtonStyle())
        }
    }
    private var stage: some View {
        TimelineView(.animation(minimumInterval: 1 / 30, paused: session.phase == .ready || session.phase == .paused || session.phase == .finished)) { _ in
            let showingReference = session.phase == .listening && library.state.settings.visualCues
            let progress = showingReference ? min(1, session.elapsed / session.duration) : Double(session.taps.count) / Double(max(1, session.request.pattern.notes.count))
            let lane = tappedLane ?? session.litLane
            let color = lane.map { EchoStyle.colors[$0] } ?? EchoStyle.accent
            ZStack {
                MaterialTexture(asset: "Atmosphere-Lab").opacity(0.25)
                LinearGradient(colors: [EchoStyle.background.opacity(0.2), EchoStyle.background.opacity(0.8)], startPoint: .top, endPoint: .bottom)
                Circle().stroke(color.opacity(0.07), lineWidth: 20).frame(width: 176, height: 176)
                Circle().stroke(.white.opacity(0.1), style: StrokeStyle(lineWidth: 2, dash: [2, 9])).frame(width: 204, height: 204)
                Circle().trim(from: 0, to: min(1, max(0, progress)))
                    .stroke(color, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                    .rotationEffect(.degrees(-90)).frame(width: 176, height: 176)
                    .shadow(color: color.opacity(0.45), radius: 9)
                VStack(spacing: 10) {
                    Image(systemName: lane.map { EchoStyle.symbols[$0] } ?? "waveform")
                        .font(.system(size: 25, weight: .light)).foregroundStyle(color)
                    Text(title).font(.system(.headline, design: .rounded, weight: .bold))
                        .multilineTextAlignment(.center).accessibilityIdentifier("snnPlayPhase")
                    Text(session.phase == .input ? "\(session.taps.count) / \(session.request.pattern.notes.count) 音符" : "听 · 记 · 回应")
                        .font(.caption2.monospacedDigit()).foregroundStyle(EchoStyle.secondary)
                }.frame(maxWidth: 155)
            }.frame(height: 240).clipShape(RoundedRectangle(cornerRadius: 26))
                .overlay(RoundedRectangle(cornerRadius: 26).stroke(.white.opacity(0.08)))
        }.accessibilityIdentifier("labPracticeStage")
    }
    private var title: String {
        switch session.phase {
        case .ready: return "让模型听听你的节奏"
        case .countingIn: return "准备聆听 · \(session.countdown)"
        case .listening: return "仔细聆听"
        case .waiting: return "准备复现"
        case .input: return "轮到你了"
        case .paused: return "实验已暂停"
        case .finished: return "分析这段节奏"
        }
    }
}
