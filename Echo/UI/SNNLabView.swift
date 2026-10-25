import SwiftUI
import AVFoundation
import UniformTypeIdentifiers

private enum LabPage: String, CaseIterable { case analysis = "分析", practice = "练习", exploration = "神经元", comparison = "对照" }
private struct LabConsentIntent: Identifiable { let id = UUID(); let exporting: Bool }

struct SNNLabView: View {
    @EnvironmentObject private var library: EchoLibrary
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.echoReducedMotion) private var reduceMotion
    @State private var active: SNNLabRecording
    @State private var latestPerformance: SNNLabRecording?
    @State private var analysis: SNNAnalysis?
    @State private var error: String?
    @StateObject private var store = RhythmLabStore.shared
    @StateObject private var playback = LabPlaybackController()
    @State private var page: LabPage = .analysis
    @State private var practice: LabPracticeConfiguration?
    @State private var archive = false
    @State private var consent: LabConsentIntent?
    @State private var document: LabJSONDocument?
    @State private var exporting = false
    @State private var pendingExport = false
    @State private var notice: String?
    @State private var practiceSpeed = 0.75
    @State private var practiceRounds = 1
    @State private var progressive = true
    @State private var useSegment = true
    @State private var step = 31.0
    @State private var playing = false
    @State private var neuron = 0
    @State private var modelDetails = false
    @State private var practiceSettings = false
    @State private var sampleOptions = false
    private let clock = Timer.publish(every: 0.12, on: .main, in: .common).autoconnect()

    init(recording: SNNLabRecording? = nil) {
        _active = State(initialValue: recording ?? .example(.steady))
        _latestPerformance = State(initialValue: recording)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                hero
                controls
                if let notice { Text(notice).font(.caption).foregroundStyle(EchoStyle.accent).accessibilityIdentifier("labNotice") }
                Picker("实验功能", selection: $page) {
                    ForEach(LabPage.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }.pickerStyle(.segmented).accessibilityIdentifier("labPages")
                if page == .analysis {
                    listeningSummary
                    LabPlaybackView(playback: playback, recording: active)
                    if let error {
                    VStack(alignment: .leading, spacing: 13) {
                        Label("本次暂不分析", systemImage: "info.circle").font(.headline)
                        Text(error).font(.subheadline).foregroundStyle(EchoStyle.secondary)
                        Text("可以选择上方模拟样本了解模型，或重新演奏实验短句。")
                            .font(.caption).foregroundStyle(EchoStyle.secondary)
                    }.frame(maxWidth: .infinity, alignment: .leading).echoPanel().accessibilityIdentifier("snnUnsupported")
                    } else if analysis == nil {
                    ProgressView("正在运行离线模型…").frame(maxWidth: .infinity).padding(40)
                    }
                    Button { page = .practice } label: {
                        Label("开始针对性练习", systemImage: "scope")
                    }.buttonStyle(EchoButtonStyle()).disabled(!active.isValid).accessibilityIdentifier("labPracticeShortcut")
                    if !LabDiagnostics.inspect(active).issues.isEmpty { diagnosticsPanel }
                } else if page == .practice {
                    practicePanel
                    diagnosticsPanel
                } else if page == .exploration {
                    if let analysis {
                        LabExplorationView(analysis: analysis).id(active.id)
                        DisclosureGroup("正式模型的完整计算过程") {
                            rawEvents(analysis.prepared).padding(.top, 12)
                            neuralActivity(analysis)
                        }.tint(EchoStyle.accent)
                    }
                    else { Text("本次暂不能进入模型探索。请选择模拟样本，或先完成模型支持范围内的演奏。") .font(.subheadline).foregroundStyle(EchoStyle.secondary).echoPanel() }
                } else {
                    if let analysis {
                        verdict(analysis)
                        LabThreeWayView(analysis: analysis)
                        benchmark(analysis.weights)
                    }
                    else { Text("本次未运行分类模型，不能伪造三方对照。仍可在“分析”查看规则诊断。") .font(.subheadline).foregroundStyle(EchoStyle.secondary).echoPanel() }
                }
                dataControls
                Text("实验模块，不参与正式得分或章节解锁。数据在本机处理，不请求麦克风权限，也不会上传演奏。")
                    .font(.caption).foregroundStyle(EchoStyle.secondary)
            }.padding(22).frame(maxWidth: 780).frame(maxWidth: .infinity)
        }.echoBackground().navigationTitle("节奏实验室").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) { Button { playback.stop(); playing = false; archive = true } label: {
                    Image(systemName: "chart.xyaxis.line")
                }.accessibilityLabel("实验档案").accessibilityIdentifier("labArchive") }
            }
            .task(id: active.id) { await analyze() }
            .onReceive(clock) { _ in
                guard playing, scenePhase == .active, !reduceMotion else { return }
                if step < 31 { step += 1 } else { playing = false }
            }
            .onChange(of: scenePhase) { _, phase in if phase != .active { playing = false; playback.stop() } }
            .onChange(of: reduceMotion) { _, reduced in if reduced { playing = false } }
            .onChange(of: page) { _, _ in playback.stop(); playing = false }
            .onChange(of: library.state.settings.sound) { _, sound in if !sound { playback.stop() } }
            .onChange(of: library.state.settings.palette) { _, _ in playback.stop() }
            .onReceive(NotificationCenter.default.publisher(for: AVAudioSession.interruptionNotification)) { _ in playback.stop(); playing = false }
            .onReceive(NotificationCenter.default.publisher(for: AVAudioSession.routeChangeNotification)) { _ in playback.stop(); playing = false }
            .onDisappear { playing = false; playback.stop() }
            .fullScreenCover(item: $practice) { configuration in
                LabPracticeView(configuration: configuration) { recording in
                    latestPerformance = recording; select(recording)
                }
            }
            .sheet(isPresented: $archive) { LabArchiveView(store: store) { recording in latestPerformance = recording; select(recording) } }
            .sheet(item: $consent, onDismiss: {
                if pendingExport { pendingExport = false; exporting = true }
            }) { intent in
                LabConsentView(exporting: intent.exporting, recording: active) { label, note in
                    let snapshot = analysis.map { LabModelSnapshot(recordingID: active.id, analysis: $0) }
                    if intent.exporting {
                        let entry = try RhythmLabStore.entry(recording: active, model: snapshot, label: label, note: note)
                        document = LabJSONDocument(data: try LabExportEnvelope(entries: [entry]).encoded()); pendingExport = true
                    } else {
                        try store.save(recording: active, model: snapshot, label: label, note: note)
                        notice = "已保存到本机实验档案，未改变正式成绩。"
                    }
                }
            }
            .fileExporter(isPresented: $exporting, document: document, contentType: .json, defaultFilename: "Echo-本次演奏") { result in
                switch result {
                case .success: notice = "演奏已导出；没有因此自动保存到档案。"
                case .failure(let error): notice = "导出未完成：" + error.localizedDescription
                }
            }
    }

    private var hero: some View {
        VStack(alignment: .leading, spacing: 13) {
            HStack {
                Text("ECHO / PULSE LAB").font(.caption.weight(.bold)).tracking(2)
                Spacer()
                Image(systemName: "point.3.connected.trianglepath.dotted").font(.title2)
            }.foregroundStyle(EchoStyle.accent)
            Text("听见偏差，练得更稳。")
                .font(.system(.title2, design: .rounded, weight: .bold))
            Text("先听 A/B，再练片段。想了解原理，切到神经元与对照。")
                .font(.subheadline).foregroundStyle(EchoStyle.secondary)
        }.padding(23).frame(maxWidth: .infinity, alignment: .leading)
            .background {
                MaterialTexture(asset: "Atmosphere-Lab").opacity(0.4)
                LinearGradient(colors: [EchoStyle.colors[1].opacity(0.16), EchoStyle.panel, EchoStyle.accent.opacity(0.07)],
                               startPoint: .topLeading, endPoint: .bottomTrailing).opacity(0.88)
            }.clipShape(RoundedRectangle(cornerRadius: 25))
            .overlay(RoundedRectangle(cornerRadius: 25).stroke(EchoStyle.accent.opacity(0.22), lineWidth: 1))
    }

    private var controls: some View {
        VStack(alignment: .leading, spacing: 15) {
            Label(active.sourceTitle, systemImage: active.simulated ? "flask" : "hand.tap")
                .font(.headline).foregroundStyle(active.simulated ? EchoStyle.colors[2] : EchoStyle.accent)
                .accessibilityIdentifier("snnSource")
            Text(active.simulated ? "人为生成的节奏，不是真人测量。点击不同样本，查看同一个模型如何响应。" :
                    active.pattern.title + " · " + active.mode.title + " · 模型意见不改变本轮成绩")
                .font(.caption).foregroundStyle(EchoStyle.secondary)
            DisclosureGroup("切换模拟样本", isExpanded: $sampleOptions) {
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                ForEach(Array(RhythmState.allCases.enumerated()), id: \.element.id) { index, state in
                    Button { select(.example(state)) } label: {
                        HStack {
                            Circle().fill(EchoStyle.colors[index]).frame(width: 6, height: 6)
                            Text(state.title).font(.subheadline.weight(.medium))
                        }.frame(maxWidth: .infinity).padding(.vertical, 13)
                            .background(EchoStyle.colors[index].opacity(0.09), in: RoundedRectangle(cornerRadius: 12))
                            .overlay(RoundedRectangle(cornerRadius: 12).stroke(EchoStyle.colors[index].opacity(0.2)))
                    }.buttonStyle(.plain).accessibilityIdentifier("snnExample-" + state.rawValue)
                }
            }.padding(.top, 10)
            }.font(.caption).tint(EchoStyle.colors[1])
            Button {
                playback.stop(); playing = false; practice = LabPracticeConfiguration(pattern: SNNExamples.pattern)
            } label: {
                Label("亲手打一段", systemImage: "hand.tap.fill")
            }.buttonStyle(EchoButtonStyle()).accessibilityIdentifier("snnPlay")
            if let latestPerformance, active.simulated {
                Button { select(latestPerformance) } label: { Label("返回我的实际演奏", systemImage: "arrow.uturn.backward") }
                    .font(.subheadline).foregroundStyle(EchoStyle.accent).padding(.vertical, 5)
                    .accessibilityIdentifier("snnRestorePerformance")
            }
        }.echoPanel()
    }

    private func verdict(_ analysis: SNNAnalysis) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 7) {
                    Text("SNN 模型倾向").font(.caption).foregroundStyle(EchoStyle.secondary)
                    Text(analysis.trace.uncertain ? "暂不能确定" : analysis.trace.winner.title)
                        .font(.system(.title, design: .rounded, weight: .bold))
                        .foregroundStyle(EchoStyle.accent).accessibilityIdentifier("snnVerdict")
                }
                Spacer()
                Image(systemName: analysis.trace.uncertain ? "questionmark.circle" : "waveform.path.ecg")
                    .font(.title).foregroundStyle(EchoStyle.accent.opacity(0.6))
            }
            Text(analysis.trace.uncertain ? "类别得分比较接近，暂不提供训练建议。可以再演奏一次，并结合规则结果判断。" : analysis.trace.winner.suggestion)
                .font(.subheadline).foregroundStyle(EchoStyle.secondary)
            ForEach(Array(RhythmState.allCases.enumerated()), id: \.element.id) { index, state in
                HStack(spacing: 12) {
                    Text(state.title).font(.caption).frame(width: 70, alignment: .leading)
                    GeometryReader { geometry in
                        Capsule().fill(.white.opacity(0.06))
                        Capsule().fill(EchoStyle.colors[index]).frame(width: max(0, geometry.size.width * analysis.trace.probabilities[index]))
                    }.frame(height: 5).accessibilityHidden(true)
                    Text(String(format: "%.1f%%", analysis.trace.probabilities[index] * 100))
                        .font(.caption.monospacedDigit()).frame(width: 55, alignment: .trailing)
                }.accessibilityElement(children: .combine)
            }
            Text("百分比是模型的相对类别得分，不是经真人验证的可信概率。低得分或类别接近时显示不确定。")
                .font(.caption2).foregroundStyle(EchoStyle.secondary)
        }.echoPanel()
    }

    private func rawEvents(_ prepared: SNNPrepared) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            SectionTitle(title: "01 / 原始节奏", caption: "10 ms 时间格")
            HStack(spacing: 16) {
                Label("上四行：标准", systemImage: "circle.fill")
                Label("下四行：点击", systemImage: "diamond.fill")
            }.font(.caption2).foregroundStyle(EchoStyle.secondary)
            SNNRawEventPlot(reference: prepared.reference, actual: prepared.actual)
                .frame(height: 176)
            HStack {
                Text("\(prepared.actual.count) 次点击")
                Spacer()
                Text(String(format: "时长 %.2f s", max(prepared.reference.last?.time ?? 0, prepared.actual.last?.time ?? 0)))
            }.font(.caption.monospacedDigit()).foregroundStyle(EchoStyle.secondary)
            Text(prepared.alignmentNote).font(.caption).foregroundStyle(EchoStyle.secondary)
        }.echoPanel()
    }

    private func neuralActivity(_ analysis: SNNAnalysis) -> some View {
        VStack(alignment: .leading, spacing: 17) {
            SectionTitle(title: "02 / 脉冲与神经元", caption: "\(Int(step) + 1) / 32 步")
            Text("模型先计算相邻点击相对标准的间隔偏差，再重采样为 16 个位置。每个位置用正、负两路脉冲表示偏慢、偏快。")
                .font(.caption).foregroundStyle(EchoStyle.secondary)
            Text("输入脉冲 · 32 通道").font(.subheadline.weight(.medium))
            SNNRasterPlot(frames: analysis.prepared.input, step: Int(step), input: true).frame(height: 150)
            HStack(spacing: 14) {
                chip("偏慢 +", color: EchoStyle.colors[2])
                chip("偏快 −", color: EchoStyle.colors[0])
            }
            Text("LIF 发放 · 48 个神经元").font(.subheadline.weight(.medium))
            SNNRasterPlot(frames: analysis.trace.spikes, step: Int(step), input: false).frame(height: 175)
            HStack {
                Text("观察神经元").font(.caption).foregroundStyle(EchoStyle.secondary)
                Spacer()
                Picker("观察神经元", selection: $neuron) {
                    ForEach(0..<48) { Text(String(format: "神经元 %02d", $0 + 1)).tag($0) }
                }.tint(EchoStyle.accent).accessibilityIdentifier("snnNeuron")
            }
            SNNVoltagePlot(frames: analysis.trace.beforeReset, neuron: neuron, step: Int(step))
                .frame(height: 115)
            Text("曲线：发放前膜电位 · 虚线：发放阈值 1.0。所有点与曲线来自本次真实计算。")
                .font(.caption2).foregroundStyle(EchoStyle.secondary)
            Slider(value: $step, in: 0...31, step: 1) { Text("模型计算步") } onEditingChanged: { _ in playing = false }
                .accessibilityIdentifier("snnStep")
            HStack {
                Button {
                    if playing { playing = false } else { if step >= 31 { step = 0 }; playing = true }
                } label: { Label(playing ? "暂停" : "播放发放过程", systemImage: playing ? "pause.fill" : "play.fill") }
                    .disabled(reduceMotion).accessibilityIdentifier("snnAnimate")
                Spacer()
                Button("显示全部") { playing = false; step = 31 }.accessibilityIdentifier("snnShowAll")
            }.font(.subheadline).foregroundStyle(EchoStyle.accent)
            Text(reduceMotion ? "已开启减弱动态效果，可拖动滑块逐步查看。" : "慢放的是 32 个模型计算步，不是实际演奏时间，也不是 32 拍。")
                .font(.caption2).foregroundStyle(EchoStyle.secondary)
        }.echoPanel()
    }

    private func comparison(_ analysis: SNNAnalysis) -> some View {
        let prepared = analysis.prepared
        let agreement = !analysis.trace.uncertain && analysis.trace.winner == prepared.rule
        return VStack(alignment: .leading, spacing: 16) {
            SectionTitle(title: "03 / 同一演奏，两种方法")
            HStack(alignment: .top, spacing: 15) {
                comparisonCell("规则基线", value: prepared.rule.title, color: EchoStyle.colors[2])
                comparisonCell("SNN 模型", value: analysis.trace.uncertain ? "不确定" : analysis.trace.winner.title, color: EchoStyle.accent)
            }
            Label(agreement ? "本次结论一致" : "本次结论不同或模型不确定", systemImage: agreement ? "equal.circle" : "arrow.triangle.branch")
                .font(.subheadline).foregroundStyle(agreement ? EchoStyle.accent : EchoStyle.colors[2])
                .accessibilityIdentifier("snnAgreement")
            HStack {
                MetricView(value: String(format: "%+.1f%%", prepared.mean * 100), title: "平均间隔偏差")
                MetricView(value: String(format: "%.1f%%", prepared.spread * 100), title: "偏差标准差")
            }
            Text("规则：偏差标准差 >10.5% 为不稳；否则平均偏差 <−8.5% 为偏快，>8.5% 为偏慢，其余为稳定。这是实验分类基线，不是正式游戏评分。")
                .font(.caption2).foregroundStyle(EchoStyle.secondary)
            Divider().overlay(.white.opacity(0.05))
            HStack {
                MetricView(value: String(format: "%.2f ms", analysis.inferenceMS), title: "本机前向耗时")
                MetricView(value: "\(analysis.trace.spikeCount)", title: "本次神经元发放")
            }
            Text("耗时不含编码与界面绘制。发放次数只描述活动量，不代表设备省电。模型不替代原有判分。")
                .font(.caption2).foregroundStyle(EchoStyle.secondary)
        }.echoPanel()
    }

    private func benchmark(_ weights: SNNWeights) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Button { modelDetails.toggle() } label: {
                HStack {
                    Label("模型与实验说明", systemImage: "doc.text.magnifyingglass").font(.headline)
                    Spacer()
                    Image(systemName: modelDetails ? "chevron.down" : "chevron.right").font(.caption)
                }.foregroundStyle(EchoStyle.accent).frame(minHeight: 44).contentShape(Rectangle())
            }.buttonStyle(.plain).accessibilityIdentifier("snnModelDetails")
                .accessibilityValue(modelDetails ? "已展开" : "已收起")
            if modelDetails {
            VStack(alignment: .leading, spacing: 15) {
                Text("电脑训练 → 导出权重 → Swift 离线 LIF 推理").font(.subheadline.weight(.medium))
                Text("32 输入 → 48 LIF → 4 类读出，32 个计算步，1,780 个可训练参数。使用替代梯度训练；每段演奏重新清空膜电位。")
                    .font(.caption).foregroundStyle(EchoStyle.secondary)
                Text("训练 \(weights.benchmark.trainCount) / 验证 \(weights.benchmark.validationCount) / 测试 \(weights.benchmark.testCount) 条。按基础谱面分组切分，三组谱面互不重叠。")
                    .font(.caption).foregroundStyle(EchoStyle.secondary)
                HStack {
                    comparisonCell("合成测试准确率 · SNN", value: String(format: "%.1f%%", weights.benchmark.snn.accuracy * 100), color: EchoStyle.accent)
                    comparisonCell("合成测试准确率 · 规则", value: String(format: "%.1f%%", weights.benchmark.rule.accuracy * 100), color: EchoStyle.colors[2])
                }
                Text(String(format: "宏 F1：SNN %.3f / 规则 %.3f", weights.benchmark.snn.macroF1, weights.benchmark.rule.macroF1))
                    .font(.caption.monospacedDigit()).foregroundStyle(EchoStyle.secondary)
                Text("目前全部为受控合成数据，真人验证样本为 0。规则在这项简单任务上同样有效；不能据此宣称 SNN 更准确、更省电或能诊断个人能力。复杂节奏、设备延迟和真实手部抖动仍需单独验证。")
                    .font(.caption).foregroundStyle(EchoStyle.colors[2])
                Text("训练代码与原始指标随工程保存在“节奏实验资料”。模型：" + weights.modelID)
                    .font(.caption2).foregroundStyle(EchoStyle.secondary)
            }.padding(.top, 17)
            }
        }.echoPanel()
    }

    private func comparisonCell(_ title: String, value: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.caption).foregroundStyle(EchoStyle.secondary)
            Text(value).font(.system(.headline, design: .rounded)).foregroundStyle(color)
        }.frame(maxWidth: .infinity, alignment: .leading)
    }

    private func chip(_ title: String, color: Color) -> some View {
        Text(title).font(.caption2.weight(.medium)).foregroundStyle(color)
            .padding(.horizontal, 10).padding(.vertical, 7)
            .background(color.opacity(0.08), in: Capsule())
    }

    private func select(_ recording: SNNLabRecording) {
        playback.stop(); playing = false; analysis = nil; error = nil; notice = nil; page = .analysis; active = recording
    }

    private var listeningSummary: some View {
        let measured = LabMeasurement.measure(active)
        let plan = LabPracticePlan(recording: active, analysis: analysis)
        let heading = measured.map { value in
            value.spread > 0.105 ? "有几处间隔不太均匀" : value.mean < -0.085 ? "这次间隔偏短，稍微放慢" : value.mean > 0.085 ? "这次间隔偏长，稍微跟紧" : "整体节奏接近标准"
        } ?? "先把音符顺序找回来"
        return VStack(alignment: .leading, spacing: 16) {
            Label(active.simulated ? "模拟节奏速览" : "这次的节奏", systemImage: "waveform.path")
                .font(.caption.weight(.semibold)).foregroundStyle(EchoStyle.accent)
            Text(heading).font(.system(.title2, design: .rounded, weight: .bold))
            if let measured {
                HStack {
                    MetricView(value: String(format: "%+.1f%%", measured.mean * 100), title: "间隔偏差")
                    MetricView(value: String(format: "%.1f%%", measured.spread * 100), title: "波动程度")
                }
            }
            Text(plan.explanation).font(.subheadline).foregroundStyle(EchoStyle.secondary)
            if let analysis {
                HStack {
                    Text("SNN 参考意见").foregroundStyle(EchoStyle.secondary)
                    Spacer()
                    Text(analysis.trace.uncertain ? "暂不能确定" : analysis.trace.winner.title)
                        .foregroundStyle(EchoStyle.colors[1]).accessibilityIdentifier("snnVerdict")
                }.font(.caption)
            }
            Text("上方结论来自原始间隔测量，不是能力评分；模型仅作参考。")
                .font(.caption2).foregroundStyle(EchoStyle.secondary)
        }.echoPanel()
    }

    private var dataControls: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("留下这次练习（自愿）", systemImage: "tray.and.arrow.down").font(.headline)
            Text(active.simulated ? "模拟样本不进入个人档案或真人数据导出。可先亲手演奏一段，档案不会自动填入演示数据。" :
                    store.contains(active) ? "这段演奏已经在本机实验档案中，可在档案中编辑人工标注、导出或删除。模型意见与原始测量分开保留。" :
                    "原始点击只在当前页面内存中；主动确认后才会保存或导出。人工标注默认留空，与模型预测分开。")
                .font(.caption).foregroundStyle(EchoStyle.secondary)
            HStack(spacing: 10) {
                Button { beginConsent(exporting: false) } label: { Text(store.contains(active) ? "本次已保存" : "保存到本机档案") }
                    .disabled(store.contains(active)).accessibilityIdentifier("labSave")
                Button { beginConsent(exporting: true) } label: { Text("导出本次演奏") }.accessibilityIdentifier("labExportCurrent")
            }.buttonStyle(EchoButtonStyle(secondary: true))
                .disabled(active.simulated || !active.isValid || (analysis == nil && error == nil))
            Button { playback.stop(); archive = true } label: { Text("查看节奏能力档案 · \(store.state.entries.count) 条") }
                .font(.subheadline).foregroundStyle(EchoStyle.accent).padding(.vertical, 8)
            if let error = store.errorMessage { Text(error).font(.caption).foregroundStyle(EchoStyle.colors[2]) }
        }.echoPanel()
    }
    private func beginConsent(exporting: Bool) {
        playback.stop(); playing = false; consent = LabConsentIntent(exporting: exporting)
    }
    private var practicePanel: some View {
        let plan = LabPracticePlan(recording: active, analysis: analysis)
        return VStack(alignment: .leading, spacing: 17) {
            SectionTitle(title: "针对这次演奏练习", caption: "独立练习")
            Text(plan.explanation).font(.subheadline).foregroundStyle(EchoStyle.secondary)
            Picker("练习范围", selection: $useSegment) {
                Text("易错片段").tag(true); Text("完整短句").tag(false)
            }.pickerStyle(.segmented)
            Text(useSegment ? plan.rangeTitle : "完整 \(plan.full.notes.count) 拍").font(.caption).foregroundStyle(EchoStyle.accent)
            HStack {
                Label("\(Int(practiceSpeed * 100))% 速度", systemImage: "speedometer")
                Spacer()
                Text("\(practiceRounds) 轮" + (progressive ? " · 达标提速" : " · 固定速度"))
            }.font(.caption).foregroundStyle(EchoStyle.accent)
            DisclosureGroup("速度与循环设置", isExpanded: $practiceSettings) {
            VStack(alignment: .leading, spacing: 14) {
            Picker("练习速度", selection: $practiceSpeed) {
                ForEach([0.6, 0.75, 0.9, 1.0], id: \.self) { Text("\(Int($0 * 100))%").tag($0) }
            }.pickerStyle(.segmented).accessibilityIdentifier("labPracticeSpeed")
            Picker("循环次数", selection: $practiceRounds) {
                Text("单次").tag(1); Text("2 轮").tag(2); Text("3 轮").tag(3)
            }.pickerStyle(.segmented).accessibilityIdentifier("labPracticeRounds")
            Toggle("达标后逐级提速", isOn: $progressive).font(.subheadline)
            Text("最多三轮。顺序全对且至少 85 分，下一轮才提速；未达标保持原速。离开前台会暂停循环。")
                .font(.caption2).foregroundStyle(EchoStyle.secondary)
            }.padding(.top, 12)
            }.tint(EchoStyle.accent)
            Button {
                startPractice(plan: plan, fragment: useSegment)
            } label: { Label("开始针对练习", systemImage: "repeat") }
                .buttonStyle(EchoButtonStyle()).disabled(!active.isValid).accessibilityIdentifier("labStartPractice")
            Text("所有速度均不写入正式游戏成绩。只返回最后一轮，仍需你确认才进入档案。")
                .font(.caption2).foregroundStyle(EchoStyle.secondary)
        }.echoPanel()
    }
    private var diagnosticsPanel: some View {
        let diagnostics = LabDiagnostics.inspect(active)
        return VStack(alignment: .leading, spacing: 15) {
            SectionTitle(title: "规则定位与修复", caption: "不猜测模型结论")
            if let result = diagnostics.result {
                Text("顺序匹配 \(result.order)% · 多点 \(result.extraCount) 次")
                    .font(.caption.monospacedDigit()).foregroundStyle(EchoStyle.accent)
            }
            if diagnostics.issues.isEmpty {
                Text("未发现超过 80 ms 的逐拍偏差或顺序问题。可以到“练习”巩固，或到“神经元”探索模型。")
                    .font(.caption).foregroundStyle(EchoStyle.secondary)
            }
            ForEach(diagnostics.issues) { issue in
                VStack(alignment: .leading, spacing: 8) {
                    Text(issue.title).font(.subheadline.weight(.semibold)).foregroundStyle(EchoStyle.colors[2])
                    Text(issue.detail).font(.caption).foregroundStyle(EchoStyle.secondary)
                    if let index = issue.noteIndex {
                        Button("重练第 \(index + 1) 拍附近") {
                            startPractice(plan: LabPracticePlan(recording: active, analysis: analysis, focusIndex: index), fragment: true)
                        }.font(.caption.weight(.medium)).foregroundStyle(EchoStyle.accent).padding(.vertical, 7)
                            .accessibilityIdentifier("labRepair-\(index)")
                    }
                }.frame(maxWidth: .infinity, alignment: .leading).padding(12).background(.white.opacity(0.025), in: RoundedRectangle(cornerRadius: 12))
            }
            Text("定位采用已有序列对齐规则；错色、漏点和超范围时不编造 SNN 分类。多点只报告数量，不虚构所属拍点。")
                .font(.caption2).foregroundStyle(EchoStyle.secondary)
        }.echoPanel()
    }
    private func startPractice(plan: LabPracticePlan, fragment: Bool) {
        playback.stop(); playing = false
        practice = LabPracticeConfiguration(pattern: fragment ? plan.segment : plan.full, mode: plan.mode,
            speed: practiceSpeed, rounds: practiceRounds, progressive: progressive, title: fragment ? plan.rangeTitle : "完整短句练习")
    }

    @MainActor private func analyze() async {
        analysis = nil; error = nil; playing = false
        let recording = active
        do {
            let output = try await Task.detached(priority: .userInitiated) {
                try RhythmSNN.analyze(pattern: recording.pattern, taps: recording.taps, mode: recording.mode, speed: recording.speed)
            }.value
            try Task.checkCancellation()
            analysis = output; step = 31
            neuron = (0..<48).max { lhs, rhs in
                output.trace.spikes.reduce(0) { $0 + $1[lhs] } < output.trace.spikes.reduce(0) { $0 + $1[rhs] }
            } ?? 0
        } catch is CancellationError { } catch {
            guard !Task.isCancelled else { return }; self.error = error.localizedDescription
        }
    }
}

struct SNNRawEventPlot: View {
    let reference: [TapEvent]
    let actual: [TapEvent]
    var cursor: Double? = nil
    var body: some View {
        Canvas { context, size in
            let left = 22.0, width = max(1, size.width - left - 10)
            let duration = max(1, (reference + actual).map(\.time).max() ?? 1) + 0.1
            for row in 0..<8 {
                let y = 9 + Double(row) * 21
                var line = Path(); line.move(to: CGPoint(x: left, y: y)); line.addLine(to: CGPoint(x: size.width, y: y))
                context.stroke(line, with: .color(.white.opacity(0.06)), lineWidth: 1)
                let label = Text("\(row % 4 + 1)").font(.system(size: 8, design: .monospaced)).foregroundColor(EchoStyle.colors[row % 4])
                context.draw(label, at: CGPoint(x: 6, y: y))
            }
            for (events, offset) in [(reference, 0), (actual, 4)] {
                for event in events {
                    let x = left + max(0, event.time) / duration * width
                    let y = 9 + Double(event.lane + offset) * 21
                    let rect = CGRect(x: x - 3, y: y - 5, width: 6, height: 10)
                    context.fill(Path(roundedRect: rect, cornerRadius: offset == 0 ? 3 : 1), with: .color(EchoStyle.colors[event.lane]))
                }
            }
            if let cursor {
                let x = left + min(duration, max(0, cursor)) / duration * width
                var line = Path(); line.move(to: CGPoint(x: x, y: 0)); line.addLine(to: CGPoint(x: x, y: 172))
                context.stroke(line, with: .color(.white.opacity(0.75)), lineWidth: 1.5)
            }
        }.accessibilityElement(children: .ignore)
            .accessibilityLabel("标准节奏与实际点击时间轴。标准 \(reference.count) 次，点击 \(actual.count) 次，分别按四种音符排列。")
    }
}

struct SNNRasterPlot: View {
    let frames: [[Float]]
    let step: Int
    let input: Bool
    var body: some View {
        Canvas { context, size in
            let rows = frames.first?.count ?? 1
            let width = size.width / 32, height = size.height / Double(rows)
            for grid in 0...8 {
                let x = Double(grid) * size.width / 8
                var line = Path(); line.move(to: CGPoint(x: x, y: 0)); line.addLine(to: CGPoint(x: x, y: size.height))
                context.stroke(line, with: .color(.white.opacity(0.07)), lineWidth: 1)
            }
            for time in 0...min(step, frames.count - 1) {
                for row in frames[time].indices where frames[time][row] > 0 {
                    let rect = CGRect(x: Double(time) * width + width * 0.2, y: Double(row) * height + 0.5,
                                      width: max(1, width * 0.6), height: max(1, height - 1))
                    let color = input ? EchoStyle.colors[row % 2 == 0 ? 2 : 0] : EchoStyle.colors[1]
                    context.fill(Path(roundedRect: rect, cornerRadius: 1), with: .color(color.opacity(0.9)))
                }
            }
            let x = Double(step + 1) * width
            var cursor = Path(); cursor.move(to: CGPoint(x: x, y: 0)); cursor.addLine(to: CGPoint(x: x, y: size.height))
            context.stroke(cursor, with: .color(EchoStyle.accent.opacity(0.65)), lineWidth: 1)
        }.padding(8).background(.black.opacity(0.2), in: RoundedRectangle(cornerRadius: 10))
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(input ? "输入脉冲" : "神经元发放")图，第 \(step + 1) 个计算步，共 32 步。")
    }
}

struct SNNVoltagePlot: View {
    let frames: [[Float]]
    let neuron: Int
    let step: Int
    var threshold = 1.0
    var body: some View {
        Canvas { context, size in
            let values = frames.map { Double($0[neuron]) }
            let lower = min(-0.1, values.min() ?? 0) - 0.1
            let upper = max(threshold + 0.2, values.max() ?? 1) + 0.1
            func y(_ value: Double) -> Double { size.height * (1 - (value - lower) / (upper - lower)) }
            var thresholdLine = Path(); thresholdLine.move(to: CGPoint(x: 0, y: y(threshold))); thresholdLine.addLine(to: CGPoint(x: size.width, y: y(threshold)))
            context.stroke(thresholdLine, with: .color(EchoStyle.colors[2].opacity(0.6)), style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
            var curve = Path()
            for index in 0...min(step, values.count - 1) {
                let point = CGPoint(x: Double(index) / 31 * size.width, y: y(values[index]))
                if index == 0 { curve.move(to: point) } else { curve.addLine(to: point) }
            }
            context.stroke(curve, with: .color(EchoStyle.accent), lineWidth: 1.5)
        }.padding(8).background(.black.opacity(0.2), in: RoundedRectangle(cornerRadius: 10))
            .accessibilityElement(children: .ignore).accessibilityLabel("神经元 \(neuron + 1) 的发放前膜电位曲线，阈值 \(String(format: "%.2f", threshold))。")
    }
}

