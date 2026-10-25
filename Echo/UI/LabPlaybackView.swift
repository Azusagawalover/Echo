import SwiftUI
import AVFoundation

@MainActor final class LabPlaybackController: ObservableObject {
    @Published private(set) var source: LabPlaybackSource?
    @Published private(set) var position = 0.0
    @Published private(set) var duration = 1.0
    @Published private(set) var message: String?
    private var timer: Timer?
    private var startTime = 0.0

    func play(_ recording: SNNLabRecording, source next: LabPlaybackSource, settings: EchoSettings) {
        if source == next { stop(); return }
        stop()
        guard settings.sound else { message = "声音已关闭，请先在设置中开启。"; return }
        do {
            let plan = try LabPlaybackPlan(recording: recording, source: next)
            startTime = ProcessInfo.processInfo.systemUptime + 0.25
            EchoAudio.shared.schedule(plan.events.map { SoundEvent(lane: $0.lane, time: $0.time) },
                start: startTime, enabled: settings.sound, palette: settings.palette)
            guard !EchoAudio.shared.unavailable else { message = "音频暂不可用，请检查播放设备。"; return }
            duration = plan.duration; source = next; message = nil
            let timer = Timer(timeInterval: 1 / 30.0, repeats: true) { [weak self] _ in
                Task { @MainActor [weak self] in self?.update() }
            }
            self.timer = timer; RunLoop.main.add(timer, forMode: .common)
        } catch { message = error.localizedDescription }
    }
    private func update() {
        position = min(duration, max(0, ProcessInfo.processInfo.systemUptime - startTime))
        if position >= duration { stop(reset: false) }
    }
    func stop(reset: Bool = true) {
        timer?.invalidate(); timer = nil
        if source != nil { EchoAudio.shared.stopSequence() }
        source = nil; if reset { position = 0 }
    }
    deinit { timer?.invalidate() }
}

struct LabPlaybackView: View {
    @EnvironmentObject private var library: EchoLibrary
    @Environment(\.echoReducedMotion) private var reduceMotion
    @ObservedObject var playback: LabPlaybackController
    let recording: SNNLabRecording
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            SectionTitle(title: "A / B 节奏回放", caption: "同一种音色")
            if recording.isValid {
                HStack(spacing: 15) {
                    Label("A 标准", systemImage: "circle.fill").foregroundStyle(EchoStyle.accent)
                    Label(recording.simulated ? "B 模拟" : "B 我的演奏", systemImage: "diamond.fill").foregroundStyle(EchoStyle.colors[1])
                }.font(.caption2)
                SNNRawEventPlot(reference: recording.reference, actual: recording.alignedTaps,
                    cursor: !reduceMotion && playback.source != nil ? playback.position : nil)
                    .frame(height: 176)
                HStack(spacing: 10) {
                    Button { playback.play(recording, source: .reference, settings: library.state.settings) } label: {
                        Label(playback.source == .reference ? "停止标准" : "A · 标准", systemImage: playback.source == .reference ? "stop.fill" : "play.fill")
                    }.accessibilityIdentifier("labReplayA")
                    Button { playback.play(recording, source: .performance, settings: library.state.settings) } label: {
                        Label(playback.source == .performance ? "停止演奏" : recording.simulated ? "B · 模拟演奏" : "B · 我的演奏", systemImage: playback.source == .performance ? "stop.fill" : "play.fill")
                    }.disabled(recording.taps.isEmpty).accessibilityIdentifier("labReplayB")
                }.buttonStyle(EchoButtonStyle(secondary: true)).disabled(!library.state.settings.sound)
                HStack {
                    Text(playback.source == .reference ? "正在听标准" : playback.source == .performance ? "正在听演奏" : "每次切换从头开始")
                        .accessibilityIdentifier("labReplayStatus")
                    Spacer()
                    Text(String(format: "%.1f s", playback.position)).monospacedDigit()
                }.font(.caption).foregroundStyle(EchoStyle.secondary)
                ProgressView(value: playback.position, total: playback.duration).tint(EchoStyle.accent)
                Text("上四行：标准；下四行：原始点击。回声模式按第一下对齐；跟奏保留已校准的起手偏移。游标与声音使用同一计时起点，显示更新约 30 Hz。")
                    .font(.caption2).foregroundStyle(EchoStyle.secondary)
                if !library.state.settings.sound { Text("声音已关闭，可到“我的 → 设置”开启。") .font(.caption).foregroundStyle(EchoStyle.colors[2]) }
            } else {
                Text("记录包含无效时间，不能安全回放；请重新演奏。") .font(.subheadline).foregroundStyle(EchoStyle.secondary)
            }
            if let message = playback.message { Text(message).font(.caption).foregroundStyle(EchoStyle.colors[2]) }
        }.echoPanel()
    }
}
