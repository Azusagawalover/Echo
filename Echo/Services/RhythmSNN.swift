import Foundation

enum RhythmState: String, CaseIterable, Codable, Identifiable {
    case steady, fast, slow, uneven
    var id: String { rawValue }
    var title: String {
        switch self {
        case .steady: return "节奏稳定"
        case .fast: return "整体偏快"
        case .slow: return "整体偏慢"
        case .uneven: return "间隔不稳"
        }
    }
    var suggestion: String {
        switch self {
        case .steady: return "相邻点击的间隔接近标准。可以试试隐藏提示，保持这份节拍感。"
        case .fast: return "多数间隔偏短。让停顿多留一点空间，再听一次标准节奏。"
        case .slow: return "多数间隔偏长。听示范时默数拍点，减少下一次点击前的犹豫。"
        case .uneven: return "间隔的长短偏差不一致。先放慢速度，把相邻两拍连得更均匀。"
        }
    }
}

struct SNNMetrics: Codable {
    let accuracy: Double
    let macroF1: Double
    let confusion: [[Int]]
}

struct SNNBenchmark: Codable {
    let seed: Int
    let dataSource: String
    let humanSamples: Int
    let trainCount: Int
    let validationCount: Int
    let testCount: Int
    let trainPatterns: Int
    let validationPatterns: Int
    let testPatterns: Int
    let split: String
    let labels: [String]
    let snn: SNNMetrics
    let rule: SNNMetrics
}

struct SNNWeights: Codable {
    let schema: Int
    let modelID: String
    let labels: [String]
    let steps: Int
    let slots: Int
    let hidden: Int
    let beta: Float
    let threshold: Float
    let errorScale: Double
    let gridSeconds: Double
    let w1: [[Float]]
    let b1: [Float]
    let w2: [[Float]]
    let b2: [Float]
    let benchmark: SNNBenchmark

    var isValid: Bool {
        schema == 1 && modelID == "echo-interval-lif-v1" &&
        labels == RhythmState.allCases.map(\.rawValue) && steps == 32 && slots == 16 && hidden == 48 &&
        beta == Float(0.9) && threshold == 1 && errorScale == 0.5 && gridSeconds == 0.01 &&
        w1.count == hidden && w1.allSatisfy { $0.count == slots * 2 && $0.allSatisfy(\.isFinite) } &&
        b1.count == hidden && b1.allSatisfy(\.isFinite) &&
        w2.count == 4 && w2.allSatisfy { $0.count == hidden && $0.allSatisfy(\.isFinite) } &&
        b2.count == 4 && b2.allSatisfy(\.isFinite) &&
        benchmark.dataSource == "synthetic_only" && benchmark.humanSamples == 0 &&
        benchmark.labels == labels && benchmark.testCount > 0 &&
        [benchmark.snn.accuracy, benchmark.snn.macroF1, benchmark.rule.accuracy, benchmark.rule.macroF1]
            .allSatisfy { $0.isFinite && (0...1).contains($0) }
    }
}

enum SNNError: LocalizedError {
    case model, unsupported(String)
    var errorDescription: String? {
        switch self {
        case .model: return "模型文件缺失或不兼容。请重新完整构建工程；正式游戏不受影响。"
        case .unsupported(let reason): return reason
        }
    }
}

struct SNNPrepared {
    let reference: [TapEvent]
    let actual: [TapEvent]
    let errors: [Double]
    let input: [[Float]]
    let mode: PlayMode
    var mean: Double { errors.reduce(0, +) / Double(errors.count) }
    var spread: Double { sqrt(errors.reduce(0) { $0 + pow($1 - mean, 2) } / Double(errors.count)) }
    var rule: RhythmState {
        if spread > 0.105 { return .uneven }
        if mean < -0.085 { return .fast }
        if mean > 0.085 { return .slow }
        return .steady
    }
    var alignmentNote: String {
        mode == .echo ? "以第一次点击对齐；只分析间隔，不判断起手早晚。" :
            "使用游戏已校准的点击时间；本模型只分析间隔，不判断整体起手偏移。"
    }
}

struct SNNTrace {
    let logits: [Float]
    /// Values shown by the UI are the actual LIF forward-pass results, not illustrative animation.
    let spikes: [[Float]]
    let membrane: [[Float]]
    let beforeReset: [[Float]]
    var probabilities: [Double] {
        let maximum = Double(logits.max() ?? 0)
        let expValues = logits.map { exp(Double($0) - maximum) }
        let sum = expValues.reduce(0, +)
        return expValues.map { $0 / sum }
    }
    var winner: RhythmState {
        RhythmState.allCases[logits.indices.max { logits[$0] < logits[$1] } ?? 0]
    }
    var uncertain: Bool {
        let ranked = probabilities.sorted(by: >)
        return ranked[0] < 0.65 || ranked[0] - ranked[1] < 0.15
    }
    var spikeCount: Int { Int(spikes.flatMap { $0 }.reduce(0, +)) }
}

struct SNNAnalysis {
    let prepared: SNNPrepared
    let trace: SNNTrace
    let inferenceMS: Double
    let weights: SNNWeights
    var ann: ANNPrediction? = nil
}

struct SNNParameters: Equatable {
    var beta: Float = 0.9
    var threshold: Float = 1
    var isValid: Bool { beta.isFinite && threshold.isFinite && (0.5...0.99).contains(beta) && (0.4...2).contains(threshold) }
}

enum RhythmSNN {
    private static let bundled: Result<SNNWeights, Error> = Result {
        guard let url = Bundle.main.url(forResource: "EchoSNN", withExtension: "json") else { throw SNNError.model }
        return try load(url: url)
    }

    static func load(url: URL) throws -> SNNWeights {
        let data = try Data(contentsOf: url)
        guard data.count < 1_000_000 else { throw SNNError.model }
        let weights = try JSONDecoder().decode(SNNWeights.self, from: data)
        guard weights.isValid else { throw SNNError.model }
        return weights
    }

    static func prepare(pattern: RhythmPattern, taps: [TapEvent], mode: PlayMode, speed: Double = 1) throws -> SNNPrepared {
        guard pattern.isValid, speed.isFinite, (0.5...1.5).contains(speed) else {
            throw SNNError.unsupported("谱面或速度不在实验范围内。")
        }
        guard (4...17).contains(pattern.notes.count) else {
            throw SNNError.unsupported("第一版支持 4–17 个音符的完整短句。这段太短或太长，可以选择实验短句再试。")
        }
        guard taps.count == pattern.notes.count,
              taps.allSatisfy({ $0.time.isFinite && $0.time >= 0 && $0.time <= 120 && (0..<4).contains($0.lane) }),
              zip(taps, taps.dropFirst()).allSatisfy({ $0.time < $1.time }),
              zip(pattern.notes, taps).allSatisfy({ $0.lane == $1.lane }) else {
            throw SNNError.unsupported("本次有错色、漏点、多点或无效时间，暂不做间隔分类。先按原判定完成顺序练习。")
        }
        let reference = pattern.notes.map { TapEvent(lane: $0.lane, time: pattern.time(of: $0, speed: speed)) }
        let origin = mode == .echo ? taps[0].time : 0
        let actual = taps.map { TapEvent(lane: $0.lane, time: (($0.time - origin) / 0.01).rounded() * 0.01) }
        var errors: [Double] = []
        for index in 1..<reference.count {
            let target = reference[index].time - reference[index - 1].time
            let observed = actual[index].time - actual[index - 1].time
            guard (0.12...2.0).contains(target), observed > 0 else {
                throw SNNError.unsupported("间隔太短或太长，超出了当前模型的实验范围。试试中等速度的短句。")
            }
            let error = observed / target - 1
            guard abs(error) <= 0.5 else {
                throw SNNError.unsupported("部分间隔偏差超过标准的 50%，超出模型训练范围。本次保留规则分析，不强行给出模型结论。")
            }
            errors.append(error)
        }
        return SNNPrepared(reference: reference, actual: actual, errors: errors, input: encode(errors: errors), mode: mode)
    }

    /// Sixteen nearest-resampled interval slots, each with a positive and negative rate channel.
    /// These are derived interval-error spikes, not the eight raw lane event streams.
    static func encode(errors: [Double]) -> [[Float]] {
        guard !errors.isEmpty, errors.allSatisfy(\.isFinite) else { return [] }
        var input = Array(repeating: Array(repeating: Float(0), count: 32), count: 32)
        for slot in 0..<16 {
            let index = Int((Double(slot) * Double(errors.count - 1) / 15).rounded())
            let error = errors[index]
            let count = Int((min(abs(error) / 0.5, 1) * 32).rounded())
            let channel = slot * 2 + (error < 0 ? 1 : 0)
            for step in 0..<32 where (step + 1) * count / 32 > step * count / 32 { input[step][channel] = 1 }
        }
        return input
    }

    static func forward(input: [[Float]], weights: SNNWeights, parameters: SNNParameters? = nil) throws -> SNNTrace {
        guard weights.isValid, input.count == weights.steps,
              input.allSatisfy({ $0.count == 32 && $0.allSatisfy { $0 == 0 || $0 == 1 } }) else { throw SNNError.model }
        guard parameters?.isValid ?? true else { throw SNNError.unsupported("探索参数超出安全范围。") }
        let beta = parameters?.beta ?? weights.beta, threshold = parameters?.threshold ?? weights.threshold
        var membrane = Array(repeating: Float(0), count: weights.hidden)
        var sums = Array(repeating: Float(0), count: weights.hidden)
        var spikeTrace: [[Float]] = [], membraneTrace: [[Float]] = [], voltageTrace: [[Float]] = []
        for frame in input {
            var spikes = Array(repeating: Float(0), count: weights.hidden)
            var voltages = spikes
            for neuron in 0..<weights.hidden {
                var current = weights.b1[neuron]
                for channel in 0..<32 { current += weights.w1[neuron][channel] * frame[channel] }
                // Match snnTorch 0.9.4 Leaky(reset_delay: false), including its prior-state reset.
                let priorReset: Float = membrane[neuron] > threshold ? 1 : 0
                let beforeReset = beta * membrane[neuron] + current - priorReset * threshold
                let spike: Float = beforeReset > threshold ? 1 : 0
                membrane[neuron] = beforeReset - (spike - priorReset) * threshold
                voltages[neuron] = beforeReset
                spikes[neuron] = spike; sums[neuron] += spike
            }
            spikeTrace.append(spikes); membraneTrace.append(membrane); voltageTrace.append(voltages)
        }
        let logits = (0..<4).map { output -> Float in
            var value = weights.b2[output]
            for neuron in 0..<weights.hidden { value += weights.w2[output][neuron] * (sums[neuron] / Float(weights.steps)) }
            return value
        }
        guard logits.allSatisfy(\.isFinite), membrane.allSatisfy(\.isFinite) else { throw SNNError.model }
        return SNNTrace(logits: logits, spikes: spikeTrace, membrane: membraneTrace, beforeReset: voltageTrace)
    }

    static func analyze(pattern: RhythmPattern, taps: [TapEvent], mode: PlayMode, speed: Double = 1) throws -> SNNAnalysis {
        let weights = try bundled.get()
        let prepared = try prepare(pattern: pattern, taps: taps, mode: mode, speed: speed)
        let start = ProcessInfo.processInfo.systemUptime
        let trace = try forward(input: prepared.input, weights: weights)
        let elapsed = (ProcessInfo.processInfo.systemUptime - start) * 1000
        return SNNAnalysis(prepared: prepared, trace: trace, inferenceMS: elapsed, weights: weights,
                           ann: try? RhythmANN.analyze(input: prepared.input))
    }
}

enum SNNExamples {
    static let pattern = RhythmPattern(id: "snn-lab", title: "实验短句", detail: "八声节拍 · 不记成绩", chapter: 2,
        bpm: 96, notes: zip([0, 2, 4, 6, 9, 11, 13, 15], [0, 1, 2, 3, 1, 0, 3, 2]).map { BeatNote(tick: $0.0, lane: $0.1) })

    static func taps(state: RhythmState) -> [TapEvent] {
        let errors: [Double]
        switch state {
        case .steady: errors = [0.01, -0.02, 0.02, 0, -0.01, 0.01, -0.02]
        case .fast: errors = [-0.21, -0.19, -0.23, -0.22, -0.20, -0.18, -0.22]
        case .slow: errors = [0.19, 0.22, 0.20, 0.23, 0.18, 0.21, 0.20]
        case .uneven: errors = [-0.23, 0.28, -0.25, 0.24, -0.27, 0.22, -0.24]
        }
        var time = 0.0
        return pattern.notes.enumerated().map { index, note in
            if index > 0 {
                let interval = pattern.time(of: note) - pattern.time(of: pattern.notes[index - 1])
                time += interval * (1 + errors[index - 1])
            }
            return TapEvent(lane: note.lane, time: time)
        }
    }
}
