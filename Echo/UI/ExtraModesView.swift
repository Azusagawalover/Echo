import SwiftUI

struct ChainChallengeView: View {
    @AppStorage("Echo.longestChain") private var longest = 0
    @State private var notes = [BeatNote(tick: 0, lane: 0), BeatNote(tick: 2, lane: 1), BeatNote(tick: 4, lane: 2)]
    @State private var round = 1
    @State private var ended = false
    @State private var pending: RhythmResult?
    @State private var game: GameRequest?
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                PhotoBanner(eyebrow: "CHAIN / 节奏接龙", title: "把回声，再延长一点。", asset: "Hub-Wave")
                Text("再多记住，一点点。") .font(.system(.largeTitle, design: .rounded, weight: .bold))
                Text("从 3 个音符开始。每轮保留原来的节奏，再增加一个音符；最多挑战 32 个。中途退出单局可重新尝试，离开接龙页则重新开始。") .foregroundStyle(EchoStyle.secondary)
                HStack { MetricView(value: "\(round)", title: "当前轮次"); MetricView(value: "\(notes.count)", title: "需要记住"); MetricView(value: "\(longest)", title: "最佳音符数") }.echoPanel()
                if ended {
                    Text(notes.count == 32 && pending?.passed == true ? "32 个音符，全都记住了。" : "这一段已经很棒，下次再多一个。") .font(.title2.bold())
                    Button { reset() } label: { Text("重新开始接龙") }.buttonStyle(EchoButtonStyle())
                } else {
                    Button {
                        pending = nil
                        game = GameRequest(pattern: RhythmPattern(id: "chain-" + UUID().uuidString, title: "接龙 · 第 \(round) 轮", detail: "保留过去，再添一声", chapter: 0, bpm: 84, notes: notes))
                    } label: { Label("挑战第 \(round) 轮", systemImage: "play.fill") }.buttonStyle(EchoButtonStyle())
                }
                Text("标准通关本轮才会进入下一轮。重听转为练习后，不推进接龙。接龙成绩不影响章节地图。") .font(.footnote).foregroundStyle(EchoStyle.secondary)
            }.padding(24).frame(maxWidth: 680).frame(maxWidth: .infinity)
        }.accessibilityHidden(game != nil).echoBackground().navigationTitle("节奏接龙").navigationBarTitleDisplayMode(.inline)
            .fullScreenCover(item: $game, onDismiss: advance) { request in
                GameView(request: request, returnTitle: "回到接龙") { result, practice in pending = practice ? nil : result }
            }
    }
    private func advance() {
        guard let pending else { return }
        if pending.passed {
            longest = max(longest, notes.count)
            if notes.count == 32 { ended = true; return }
            let tick = notes.last!.tick + (round % 3 == 0 ? 1 : 2)
            notes.append(BeatNote(tick: tick, lane: Int.random(in: 0..<4))); round += 1
        } else { ended = true }
    }
    private func reset() {
        notes = (0..<3).map { BeatNote(tick: $0 * 2, lane: Int.random(in: 0..<4)) }
        round = 1; ended = false; pending = nil
    }
}

struct DuoChallengeView: View {
    @EnvironmentObject private var library: EchoLibrary
    @Environment(\.scenePhase) private var scenePhase
    @State private var first = "玩家 A"
    @State private var second = "玩家 B"
    @State private var turn = 0
    @State private var recording = false
    @State private var anchor: Double?
    @State private var taps: [TapEvent] = []
    @State private var pattern: RhythmPattern?
    @State private var game: GameRequest?
    @State private var result: RhythmResult?
    @State private var scores: [Int] = []
    @State private var notice = "先由玩家 A 创作，再把设备交给玩家 B。"
    private var author: String { turn == 0 ? first : second }
    private var responder: String { turn == 0 ? second : first }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 23) {
                VStack(alignment: .leading, spacing: 12) {
                    Label("同一台设备 · 轮流出题", systemImage: "person.2.wave.2").font(.caption).foregroundStyle(EchoStyle.colors[3])
                    Text(scores.count == 2 ? "两段节奏，两次回应。" : "\(author)出题\n\(responder)回应") .font(.system(.title, design: .rounded, weight: .bold))
                }.padding(20).frame(maxWidth: .infinity, alignment: .leading)
                    .background { ScenicBackdrop(asset: "Hub-Studio", tint: EchoStyle.colors[3]) }
                    .clipShape(RoundedRectangle(cornerRadius: 24))
                if scores.count == 2 {
                    HStack { MetricView(value: "\(scores[0])", title: "\(second)的回应"); MetricView(value: "\(scores[1])", title: "\(first)的回应"); MetricView(value: "\((scores[0] + scores[1]) / 2)", title: "双人平均分") }.echoPanel()
                    Text("互相出题，不评输赢。换一段新节奏，继续听见对方。") .foregroundStyle(EchoStyle.secondary)
                    Button { scores = []; turn = 0; taps = []; pattern = nil; result = nil; notice = "新一轮开始，先录下第一段。" } label: { Text("再玩一轮") }.buttonStyle(EchoButtonStyle())
                } else {
                    if turn == 0 && pattern == nil && !recording {
                        HStack { TextField("玩家 A", text: $first); TextField("玩家 B", text: $second) }.textFieldStyle(.roundedBorder)
                            .onChange(of: first) { _, value in first = String(value.prefix(10)) }
                            .onChange(of: second) { _, value in second = String(value.prefix(10)) }
                    }
                    Text(notice).font(.subheadline).foregroundStyle(EchoStyle.secondary)
                    PadGrid(compact: true, action: { lane, time in
                        EchoAudio.shared.hit(lane, settings: library.state.settings)
                        if recording {
                            if anchor == nil { anchor = time }
                            taps.append(TapEvent(lane: lane, time: time - anchor!))
                            if taps.count >= 12 || time - anchor! >= 10 { endRecording() }
                        }
                    })
                    if let pattern {
                        PatternDots(pattern: pattern)
                        Button {
                            result = nil
                            game = GameRequest(pattern: pattern)
                        } label: { Text("交给\(responder)，开始挑战") }.buttonStyle(EchoButtonStyle())
                        Button("重新出题") { self.pattern = nil; taps = []; anchor = nil }.foregroundStyle(EchoStyle.secondary).font(.subheadline)
                    } else {
                        Button {
                            if recording { endRecording() }
                            else {
                                if first.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { first = "玩家 A" }
                                if second.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { second = "玩家 B" }
                                taps = []; anchor = nil; recording = true; notice = "按自然节奏敲击 2～12 个音符，完成后停止录制。按 96 BPM 半拍网格整理。"
                            }
                        } label: { Label(recording ? "停止出题（\(taps.count) 个音符）" : "\(author)开始出题", systemImage: recording ? "stop.circle" : "record.circle") }.buttonStyle(EchoButtonStyle())
                    }
                    Text("每人轮流创作一段。单局可以重试，返回此页后确认该次回应。本模式是轻松互动，不是公平竞技或能力测评。") .font(.footnote).foregroundStyle(EchoStyle.secondary)
                }
            }.padding(24).frame(maxWidth: 680).frame(maxWidth: .infinity)
        }.accessibilityHidden(game != nil).echoBackground().navigationTitle("双人回声").navigationBarTitleDisplayMode(.inline)
            .fullScreenCover(item: $game, onDismiss: {
                if let result {
                    scores.append(result.score); turn = 1; pattern = nil; taps = []; anchor = nil; self.result = nil
                    notice = "现在交换角色，由\(second)出题。"
                }
            }) { request in GameView(request: request, returnTitle: "确认这次回应") { value, _ in result = value } }
            .onChange(of: scenePhase) { _, phase in if phase != .active, recording { recording = false; notice = "录制被中断，请重新出题。" } }
            .onDisappear { recording = false }
    }
    private func endRecording() {
        recording = false
        var cells: [Int: Int] = [:]
        for tap in taps { let tick = Int((tap.time / (30.0 / 96)).rounded()); if tick < 64 { cells[tick] = tap.lane } }
        let notes = cells.keys.sorted().map { BeatNote(tick: $0, lane: cells[$0]!) }
        guard notes.count >= 2 else { notice = "至少需要两个不同拍点。再出一段吧。"; return }
        pattern = RhythmPattern(id: "duo-" + UUID().uuidString, title: "双人回声 · 第 \(turn + 1) 段", detail: "轮流出题", chapter: 0, bpm: 96, notes: notes)
        notice = "出题完成，请把设备交给\(responder)。系统会先播放整理后的节奏，再由对方复现。"
    }
}
