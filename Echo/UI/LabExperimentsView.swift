import SwiftUI

struct LabExplorationView: View {
    let analysis: SNNAnalysis
    @State private var parameters = SNNParameters()
    @State private var trace: SNNTrace?
    @State private var error: String?
    @State private var neuron = 0
    @State private var step = 31.0
    private var key: String { "\(parameters.beta.bitPattern)-\(parameters.threshold.bitPattern)" }
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Label("探索模式 · 不改变正式模型", systemImage: "slider.horizontal.3").font(.headline).foregroundStyle(EchoStyle.colors[2])
            Text("只改变本次演示的衰减与阈值。下面比较相同输入下的真实膜电位与发放；改参后的分类读出不作为建议、档案预测或测试成绩。")
                .font(.caption).foregroundStyle(EchoStyle.secondary)
            HStack { Text("电位保留系数 β"); Spacer(); Text(String(format: "%.2f", parameters.beta)).monospacedDigit() }.font(.subheadline)
            Slider(value: $parameters.beta, in: 0.5...0.99, step: 0.01).accessibilityLabel("电位保留系数").accessibilityIdentifier("labBeta")
            HStack { Text("发放阈值"); Spacer(); Text(String(format: "%.2f", parameters.threshold)).monospacedDigit() }.font(.subheadline)
            Slider(value: $parameters.threshold, in: 0.4...2, step: 0.05).accessibilityLabel("发放阈值").accessibilityIdentifier("labThreshold")
            Text("β 越大，上一计算步的电位保留越多；阈值越高，通常越难发放，但结果还受输入与权重影响。")
                .font(.caption2).foregroundStyle(EchoStyle.secondary)
            Button("恢复训练参数（0.90 / 1.00）") { parameters = SNNParameters() }
                .font(.subheadline).foregroundStyle(EchoStyle.accent).accessibilityIdentifier("labResetParameters")
            if let trace {
                HStack {
                    MetricView(value: "\(analysis.trace.spikeCount)", title: "正式参数总发放")
                    MetricView(value: "\(trace.spikeCount)", title: "探索参数总发放")
                }.accessibilityIdentifier("labExplorationCounts")
                Picker("观察神经元", selection: $neuron) { ForEach(0..<48) { Text("神经元 \($0 + 1)").tag($0) } }.tint(EchoStyle.accent)
                Text("正式参数 · 发放前电位").font(.caption)
                SNNVoltagePlot(frames: analysis.trace.beforeReset, neuron: neuron, step: Int(step)).frame(height: 120)
                Text("探索参数 · 发放前电位").font(.caption)
                SNNVoltagePlot(frames: trace.beforeReset, neuron: neuron, step: Int(step), threshold: Double(parameters.threshold)).frame(height: 120)
                SNNRasterPlot(frames: trace.spikes, step: Int(step), input: false).frame(height: 170)
                Slider(value: $step, in: 0...31, step: 1).accessibilityLabel("探索计算步")
                Text("第 \(Int(step) + 1) / 32 步 · 阈值虚线随探索参数变化。当前只展示计算，不测量设备能耗。")
                    .font(.caption2).foregroundStyle(EchoStyle.secondary)
            } else { ProgressView("重新计算神经元…") }
            if let error { Text(error).font(.caption).foregroundStyle(EchoStyle.colors[2]) }
        }.echoPanel().task(id: key) {
            let requested = parameters
            trace = nil
            do {
                try await Task.sleep(nanoseconds: 80_000_000)
                let result = try await Task.detached(priority: .userInitiated) {
                    try RhythmSNN.forward(input: analysis.prepared.input, weights: analysis.weights, parameters: requested)
                }.value
                try Task.checkCancellation(); trace = result; error = nil
            } catch is CancellationError { } catch { if !Task.isCancelled { self.error = error.localizedDescription } }
        }
    }
}

struct LabThreeWayView: View {
    let analysis: SNNAnalysis
    private func time(_ ms: Double) -> String { ms < 0.01 ? "<0.01 ms" : String(format: "%.2f ms", ms) }
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Label("规则 / ANN / SNN", systemImage: "chart.bar.xaxis").font(.title3.bold())
            Text("三种方法使用同一份量化间隔误差。ANN 读取脉冲的时间平均值，SNN 按 32 个计算步递推；两种网络均为 1,780 参数。")
                .font(.caption).foregroundStyle(EchoStyle.secondary)
            method("规则", result: analysis.prepared.rule.title, detail: "固定阈值 · 非学习方法", color: EchoStyle.colors[2])
            method("SNN", result: analysis.trace.uncertain ? "不确定" : analysis.trace.winner.title,
                   detail: "本机前向 \(time(analysis.inferenceMS)) · 权重 \(RhythmANN.bundledBytes("EchoSNN")) B", color: EchoStyle.accent)
            if let ann = analysis.ann {
                method("ANN", result: ann.uncertain ? "不确定" : ann.winner.title,
                       detail: "本机前向 \(time(ann.inferenceMS)) · 权重 \(RhythmANN.bundledBytes("EchoANN")) B", color: EchoStyle.colors[1])
                let report = ann.weights.benchmark
                Divider().overlay(.white.opacity(0.05))
                Text("同一合成测试集 · \(report.testCount) 条").font(.headline)
                ForEach([("规则", report.rule), ("ANN", report.ann), ("SNN", report.snn)], id: \.0) { title, metric in
                    HStack {
                        Text(title).frame(width: 48, alignment: .leading)
                        Spacer()
                        Text(String(format: "准确率 %.1f%% · 宏 F1 %.3f", metric.accuracy * 100, metric.macroF1)).monospacedDigit()
                    }.font(.caption).accessibilityElement(children: .combine)
                }
                Text("训练 \(report.trainCount) / 验证 \(report.validationCount) / 测试 \(report.testCount)。基础谱面分组互不重叠；ANN 同样在验证集选取模型，不在测试集调参。")
                    .font(.caption).foregroundStyle(EchoStyle.secondary)
                Text("测试集指纹：" + String(report.datasetSHA256.prefix(16)) + "…")
                    .font(.caption2.monospaced()).foregroundStyle(EchoStyle.secondary)
                Text("三种方法在受控合成任务上都可能达到很高分，不能据此认为 SNN 胜出。真人测试仍为 0；单次前向耗时会波动，不含加载、编码与绘图，也不等同于耗电量。")
                    .font(.caption).foregroundStyle(EchoStyle.colors[2])
            } else {
                Text("ANN 权重暂不可用，未伪造对照结果。请完整重新构建工程。") .font(.caption).foregroundStyle(EchoStyle.colors[2])
            }
        }.echoPanel().accessibilityIdentifier("labThreeWay")
    }
    private func method(_ title: String, result: String, detail: String, color: Color) -> some View {
        HStack {
            Text(title).font(.headline).foregroundStyle(color).frame(width: 45, alignment: .leading)
            VStack(alignment: .leading, spacing: 6) {
                Text(result).font(.headline)
                Text(detail).font(.caption2.monospaced()).foregroundStyle(EchoStyle.secondary)
            }
            Spacer()
        }.padding(14).background(color.opacity(0.06), in: RoundedRectangle(cornerRadius: 14))
    }
}
