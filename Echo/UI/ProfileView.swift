import SwiftUI
import AVFoundation

struct ProfileView: View {
    @EnvironmentObject private var library: EchoLibrary
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 25) {
                HStack {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("每次回应，都算数。") .font(.system(.title, design: .rounded, weight: .bold))
                        Text("这是只属于你的声音旅程。") .font(.subheadline).foregroundStyle(EchoStyle.secondary)
                    }
                    Spacer()
                    NavigationLink { SettingsView() } label: { Image(systemName: "slider.horizontal.3").font(.title2).padding(12) }.accessibilityLabel("设置")
                }.padding(20).frame(minHeight: 130)
                    .background {
                        ScenicBackdrop(asset: "Hub-City", tint: EchoStyle.accent)
                        EchoStyle.background.opacity(0.25)
                    }.clipShape(RoundedRectangle(cornerRadius: 24))
                HStack { MetricView(value: "\(library.completed)", title: "点亮关卡"); MetricView(value: "\(library.starTotal)", title: "收集星星"); MetricView(value: "\(library.state.records.count)", title: "最近挑战") }.echoPanel()
                NavigationLink { SNNLabView() } label: {
                    HStack(spacing: 16) {
                        Image(systemName: "waveform.path.ecg").font(.title).foregroundStyle(EchoStyle.accent)
                        VStack(alignment: .leading, spacing: 7) {
                            Text("SNN 节奏实验室").font(.headline).foregroundStyle(.white)
                            Text("看见脉冲，比较模型与规则。")
                                .font(.caption).foregroundStyle(EchoStyle.secondary)
                        }
                        Spacer()
                        Image(systemName: "chevron.right").font(.caption).foregroundStyle(EchoStyle.secondary)
                    }.echoPanel()
                }.buttonStyle(.plain).accessibilityIdentifier("snnLab")
                SectionTitle(title: "声音徽章", caption: "\(library.achievements.filter { $0.2 }.count) / 5")
                ForEach(Array(library.achievements.enumerated()), id: \.offset) { _, badge in
                    HStack(spacing: 17) {
                        Image(systemName: badge.2 ? "seal.fill" : "seal").font(.title).foregroundStyle(badge.2 ? EchoStyle.colors[2] : EchoStyle.secondary.opacity(0.4))
                        VStack(alignment: .leading, spacing: 7) { Text(badge.0).font(.headline); Text(badge.1).font(.caption).foregroundStyle(EchoStyle.secondary) }
                        Spacer()
                        if badge.2 { Image(systemName: "checkmark").foregroundStyle(EchoStyle.accent) }
                    }.echoPanel()
                }
                SectionTitle(title: "最近的回声", caption: "保存最近 500 次 · 展示 20 次")
                if library.state.records.isEmpty {
                    Text("还没有记录。从雨巷的第一段节奏开始吧。") .font(.subheadline).foregroundStyle(EchoStyle.secondary).frame(maxWidth: .infinity, alignment: .leading).echoPanel()
                }
                ForEach(library.state.records.prefix(20)) { record in
                    HStack {
                        VStack(alignment: .leading, spacing: 7) {
                            Text(record.title).font(.headline)
                            Text(record.mode.title + (record.practice ? " · 练习" : " · 标准")).font(.caption).foregroundStyle(EchoStyle.secondary)
                            Text(record.date, format: .dateTime.month().day().hour().minute()).font(.caption2).foregroundStyle(EchoStyle.secondary)
                        }
                        Spacer()
                        Text("\(record.score)").font(.system(.title, design: .rounded, weight: .bold)).foregroundStyle(EchoStyle.accent)
                    }.echoPanel()
                }
            }.padding(22).frame(maxWidth: 760).frame(maxWidth: .infinity)
        }.echoBackground().navigationTitle("我的").toolbar(.hidden, for: .navigationBar)
    }
}

struct SettingsView: View {
    @EnvironmentObject private var library: EchoLibrary
    @State private var tutorial = false
    var body: some View {
        Form {
            Section("声音与反馈") {
                Toggle("播放声音", isOn: setting(\.sound))
                Picker("演奏音色", selection: setting(\.palette)) {
                    ForEach(SoundPalette.allCases) { Text($0.title).tag($0) }
                }.pickerStyle(.menu).accessibilityIdentifier("soundPalette")
                Button("试听当前音色") {
                    EchoAudio.shared.schedule((0..<4).map { SoundEvent(lane: $0, time: Double($0) * 0.6) },
                        start: ProcessInfo.processInfo.systemUptime + 0.15, enabled: library.state.settings.sound, palette: library.state.settings.palette)
                }.disabled(!library.state.settings.sound)
                Toggle("音垫震动（支持的设备）", isOn: setting(\.haptics))
                Toggle("减弱动态效果", isOn: setting(\.reducedMotion))
                Toggle("播放时显示颜色提示", isOn: setting(\.visualCues)).disabled(!library.state.settings.sound)
                Text("声音关闭时保留视觉提示。颜色同时配有形状标识。") .font(.caption).foregroundStyle(EchoStyle.secondary)
            }
            Section("四个音符分别听") {
                ForEach(0..<4) { lane in
                    Button {
                        EchoAudio.shared.stopSequence()
                        EchoAudio.shared.hit(lane, settings: library.state.settings)
                    } label: {
                        HStack(spacing: 13) {
                            Image(systemName: EchoStyle.symbols[lane]).foregroundStyle(EchoStyle.colors[lane]).frame(width: 24)
                            Text(EchoStyle.names[lane]).foregroundStyle(.white)
                            Text(EchoToneSynthesizer.voiceNames[lane]).font(.caption).foregroundStyle(EchoStyle.secondary)
                            Spacer()
                            Image(systemName: "play.circle").foregroundStyle(EchoStyle.colors[lane])
                        }.padding(.vertical, 4)
                    }.disabled(!library.state.settings.sound).accessibilityIdentifier("previewLane-\(lane)")
                }
                Text("雨滴听音高下落，月光听铃声余音，暖阳听低鼓，星火听短沙声。音色套装改变质感，但保留这四种区别。")
                    .font(.caption).foregroundStyle(EchoStyle.secondary)
            }
            Section("跟奏判定校准") {
                NavigationLink { CalibrationView() } label: { Label("跟着节拍校准", systemImage: "metronome") }
                HStack { Text("手动偏移"); Spacer(); Text(String(format: "%+.0f ms", library.state.settings.offsetMS)).monospacedDigit().foregroundStyle(EchoStyle.accent) }
                Slider(value: setting(\.offsetMS), in: -250...250, step: 5).accessibilityLabel("判定偏移毫秒")
                Button("恢复零偏移") { var settings = library.state.settings; settings.offsetMS = 0; library.setSettings(settings) }
                Text("正值用于补偿整体偏晚。校准只影响跟奏和消失节拍，不改变回声模式的相对间隔。蓝牙延迟可能变化，演示建议使用扬声器。") .font(.caption).foregroundStyle(EchoStyle.secondary)
            }
            Section("玩法") { Button("重新体验互动教学") { tutorial = true } }
            Section("关于回声") {
                LabeledContent("版本", value: "1.4 · 节奏进阶实验")
                NavigationLink("素材与致谢") { AssetCreditsView() }
                Text("回声 Echo · 声音记忆之旅\n离线运行，不需要账户、麦克风或相册权限。音符由本地合成，不包含商业歌曲。") .font(.footnote).foregroundStyle(EchoStyle.secondary)
                Text("标准回声用于解锁章节；慢速、重听和片段练习单独记录。存档仅在本机保存，请保留工程和设备备份。") .font(.footnote).foregroundStyle(EchoStyle.secondary)
            }
        }.accessibilityHidden(tutorial).scrollContentBackground(.hidden).echoBackground().navigationTitle("设置").navigationBarTitleDisplayMode(.inline)
            .sheet(isPresented: $tutorial) { TutorialView() }
            .onChange(of: library.state.settings.palette) { _, palette in EchoAudio.shared.prepare(palette: palette) }
            .onChange(of: library.state.settings.sound) { _, sound in if !sound { EchoAudio.shared.stopAll() } }
            .onDisappear { EchoAudio.shared.stopAll() }
    }
    private func setting<T>(_ key: WritableKeyPath<EchoSettings, T>) -> Binding<T> {
        Binding(get: { library.state.settings[keyPath: key] }, set: { value in
            var next = library.state.settings; next[keyPath: key] = value
            if !next.sound { next.visualCues = true }
            library.setSettings(next)
        })
    }
}

struct AssetCreditsView: View {
    var body: some View {
        List {
            Section("夜景摄影 / Unsplash") {
                Text("照片仅作为虚构章节的氛围背景，已做统一调色与遮罩；不表示摄影作者参与或推荐本作品。")
                    .font(.footnote).foregroundStyle(.secondary)
                Link("雨巷 · masahiro miyagi", destination: URL(string: "https://unsplash.com/photos/uZA3P4sA3tM")!)
                Link("钟楼 · your_mamacita", destination: URL(string: "https://unsplash.com/photos/AqNh8X3QVns")!)
                Link("夜行列车 · Michel Stockman", destination: URL(string: "https://unsplash.com/photos/y-pWfZbeh0s")!)
                Link("回声广场 · taha siddiqui", destination: URL(string: "https://unsplash.com/photos/FLJ0RbKAeSg")!)
                Link("创作 · Fethi Benattallah", destination: URL(string: "https://unsplash.com/photos/MoD3K8evGqw")!)
                Link("聆听 · insung yoon", destination: URL(string: "https://unsplash.com/photos/N1QwvJDvj4E")!)
                Link("光波 · Pawel Czerwinski", destination: URL(string: "https://unsplash.com/photos/eybM9n4yrpE")!)
                Link("城市 · Fabien BELLANGER", destination: URL(string: "https://unsplash.com/photos/atQvQu_Was0")!)
                Link("Unsplash License", destination: URL(string: "https://unsplash.com/license")!)
            }
            Section("粒子贴图 / CC0") {
                Link("Kenney · Particle Pack 1.1", destination: URL(string: "https://kenney.nl/assets/particle-pack")!)
                Text("使用 light_01、flare_01、star_04 三张透明贴图。原始许可和完整来源随源码保留。")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            Section("材质与灯光 / CC0") {
                Link("ambientCG · Paper 001", destination: URL(string: "https://ambientcg.com/view?id=Paper001")!)
                Link("ambientCG · Metal 030", destination: URL(string: "https://ambientcg.com/view?id=Metal030")!)
                Link("ambientCG 许可", destination: URL(string: "https://docs.ambientcg.com/license/")!)
                Link("Kenney · Light Masks", destination: URL(string: "https://kenney.nl/assets/light-masks")!)
                Text("纸纹用于回声票根；金属细纹用于演奏垫与创作面板；光晕、光环、光束、窗光来自 Light Masks。只打包实际使用的二维贴图。")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            Section("雨窗摄影 / Unsplash") {
                Link("雨窗散景 · 极雅 张 / northcity", destination: URL(string: "https://unsplash.com/photos/95vDQdX21rM")!)
                Text("使用 Unsplash License，本地打包，仅作为雨巷首页的低透明度氛围层。")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            Section("实验室光影 / Unsplash") {
                Link("蓝紫光影 · Liana S", destination: URL(string: "https://unsplash.com/photos/abstract-blue-and-purple-light-patterns-9lsSvIbYIUw")!)
                Text("使用 Unsplash License，离线打包为实验室与练习舞台的氛围层；节拍环、趋势图和四种触发反馈由原生图形绘制。")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            Section("声音与场景") {
                Text("音符、城市短旋律为本地程序合成；城市建筑、进度窗户与雨线由原生图形绘制。未提取商业音游的美术、音乐或谱面。")
                    .font(.footnote).foregroundStyle(.secondary)
            }
        }.scrollContentBackground(.hidden).echoBackground().navigationTitle("素材与致谢").navigationBarTitleDisplayMode(.inline)
    }
}

struct CalibrationView: View {
    @EnvironmentObject private var library: EchoLibrary
    @Environment(\.scenePhase) private var scenePhase
    @State private var running = false
    @State private var start = 0.0
    @State private var elapsed = 0.0
    @State private var offsets: [Int: Double] = [:]
    @State private var status = "听到声音时点击音垫，连续点击至少 6 拍。"
    private let beat = 0.65
    private let clock = Timer.publish(every: 1 / 60.0, on: .main, in: .common).autoconnect()
    private var median: Double {
        let values = offsets.values.sorted()
        guard !values.isEmpty else { return 0 }
        return values.count % 2 == 0 ? (values[values.count / 2 - 1] + values[values.count / 2]) / 2 : values[values.count / 2]
    }
    var body: some View {
        ScrollView {
            VStack(spacing: 28) {
                EchoMark()
                Text("找到你的拍点") .font(.system(.largeTitle, design: .rounded, weight: .bold))
                Text(status).font(.subheadline).foregroundStyle(EchoStyle.secondary).multilineTextAlignment(.center)
                BeatPad(lane: 0, lit: running && elapsed >= 0 && elapsed.truncatingRemainder(dividingBy: beat) < 0.12, enabled: running) { time in
                    let relative = time - start
                    let index = Int((relative / beat).rounded())
                    guard (0..<12).contains(index), offsets[index] == nil else { return }
                    let offset = relative - Double(index) * beat
                    guard abs(offset) <= 0.25 else { return }
                    offsets[index] = offset
                }.frame(maxWidth: 340)
                Text("\(offsets.count) / 12 拍").font(.headline.monospacedDigit()).foregroundStyle(EchoStyle.accent)
                if !running, offsets.count >= 6 {
                    Text(String(format: "估计偏移 %+.0f ms", median * 1000)).font(.title2.bold())
                    Button {
                        var next = library.state.settings; next.offsetMS = min(250, max(-250, (median * 200).rounded() * 5)); library.setSettings(next)
                        status = "已应用偏移。可以到跟奏模式中试一试，再按手感微调。"
                    } label: { Text("应用校准结果") }.buttonStyle(EchoButtonStyle())
                }
                Button {
                    if running { stop(); status = "校准已停止。" }
                    else {
                        offsets = [:]; elapsed = -1; start = ProcessInfo.processInfo.systemUptime + 1
                        EchoAudio.shared.schedule((0..<12).map { SoundEvent(lane: 0, time: Double($0) * beat) }, start: start, enabled: true, palette: library.state.settings.palette)
                        running = true; status = "听到每次声音就点击，不必追求用力或速度。"
                    }
                } label: { Text(running ? "停止校准" : "开始 12 拍校准") }.buttonStyle(EchoButtonStyle(secondary: true))
                Text("这是一项手动节拍估计，不是专业音频测量。尽量保持自然、均匀的点击。") .font(.footnote).foregroundStyle(EchoStyle.secondary)
            }.padding(26).frame(maxWidth: 620).frame(maxWidth: .infinity)
        }.echoBackground().navigationTitle("延迟校准").navigationBarTitleDisplayMode(.inline)
            .onReceive(clock) { _ in
                guard running else { return }; elapsed = ProcessInfo.processInfo.systemUptime - start
                if elapsed >= beat * 12 { stop(); status = offsets.count >= 6 ? "已完成。可以应用结果，或再校准一次。" : "有效点击不足 6 拍，请再试一次。" }
            }
            .onDisappear { stop() }
            .onChange(of: scenePhase) { _, phase in if phase != .active { stop(); status = "校准已中断，请重新开始。" } }
            .onReceive(NotificationCenter.default.publisher(for: AVAudioSession.interruptionNotification)) { _ in stop(); status = "音频被中断，请重新开始。" }
    }
    private func stop() { running = false; EchoAudio.shared.stopSequence() }
}
