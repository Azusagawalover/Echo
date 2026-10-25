import Foundation

struct ANNBenchmark: Codable {
    let trainCount: Int
    let validationCount: Int
    let testCount: Int
    let humanSamples: Int
    let dataSource: String
    let split: String
    let datasetSHA256: String
    let snnModelSHA256: String
    let input: String
    let labels: [String]
    let ann: SNNMetrics
    let snn: SNNMetrics
    let rule: SNNMetrics
}

struct ANNWeights: Codable {
    let schema: Int
    let modelID: String
    let labels: [String]
    let inputs: Int
    let hidden: Int
    let w1: [[Float]]
    let b1: [Float]
    let w2: [[Float]]
    let b2: [Float]
    let benchmark: ANNBenchmark
    var isValid: Bool {
        schema == 1 && modelID == "echo-interval-mlp-v1" && labels == RhythmState.allCases.map(\.rawValue) &&
        inputs == 32 && hidden == 48 && w1.count == 48 && b1.count == 48 && w2.count == 4 && b2.count == 4 &&
        w1.allSatisfy { $0.count == 32 && $0.allSatisfy(\.isFinite) } && b1.allSatisfy(\.isFinite) &&
        w2.allSatisfy { $0.count == 48 && $0.allSatisfy(\.isFinite) } && b2.allSatisfy(\.isFinite) &&
        benchmark.humanSamples == 0 && benchmark.dataSource == "synthetic_only" &&
        benchmark.testCount == 576 && benchmark.labels == labels && benchmark.split == "disjoint_base_patterns" &&
        benchmark.datasetSHA256.count == 64 && benchmark.snnModelSHA256 == "9124b52ea1da54e2e27ec12b4d1ad9b237919f389c88cf4597643e7e312a0e37" &&
        [benchmark.ann.accuracy, benchmark.ann.macroF1, benchmark.snn.accuracy, benchmark.snn.macroF1,
         benchmark.rule.accuracy, benchmark.rule.macroF1].allSatisfy { $0.isFinite && (0...1).contains($0) }
    }
}

struct ANNPrediction {
    let logits: [Float]
    let inferenceMS: Double
    let weights: ANNWeights
    var probabilities: [Double] {
        let maximum = Double(logits.max() ?? 0)
        let values = logits.map { exp(Double($0) - maximum) }
        return values.map { $0 / values.reduce(0, +) }
    }
    var winner: RhythmState { RhythmState.allCases[logits.indices.max { logits[$0] < logits[$1] } ?? 0] }
    var uncertain: Bool {
        let sorted = probabilities.sorted(by: >)
        return sorted[0] < 0.65 || sorted[0] - sorted[1] < 0.15
    }
}

enum RhythmANN {
    private static let bundled: Result<ANNWeights, Error> = Result {
        guard let url = Bundle.main.url(forResource: "EchoANN", withExtension: "json") else { throw SNNError.model }
        return try load(url: url)
    }
    static func load(url: URL) throws -> ANNWeights {
        let data = try Data(contentsOf: url)
        guard data.count < 1_000_000 else { throw SNNError.model }
        let model = try JSONDecoder().decode(ANNWeights.self, from: data)
        guard model.isValid else { throw SNNError.model }; return model
    }
    static func forward(input: [[Float]], weights: ANNWeights) throws -> [Float] {
        guard weights.isValid, input.count == 32,
              input.allSatisfy({ $0.count == 32 && $0.allSatisfy { $0 == 0 || $0 == 1 } }) else { throw SNNError.model }
        let rates = (0..<32).map { channel in input.reduce(Float(0)) { $0 + $1[channel] } / 32 }
        let hidden = (0..<48).map { neuron -> Float in
            var value = weights.b1[neuron]
            for channel in 0..<32 { value += weights.w1[neuron][channel] * rates[channel] }
            return max(0, value)
        }
        let logits = (0..<4).map { index in
            var value = weights.b2[index]
            for neuron in 0..<48 { value += weights.w2[index][neuron] * hidden[neuron] }
            return value
        }
        guard logits.allSatisfy(\.isFinite) else { throw SNNError.model }; return logits
    }
    static func analyze(input: [[Float]]) throws -> ANNPrediction {
        let weights = try bundled.get(), start = ProcessInfo.processInfo.systemUptime
        let logits = try forward(input: input, weights: weights)
        guard logits.allSatisfy(\.isFinite) else { throw SNNError.model }
        return ANNPrediction(logits: logits, inferenceMS: (ProcessInfo.processInfo.systemUptime - start) * 1000, weights: weights)
    }
    static func bundledBytes(_ name: String) -> Int {
        guard let url = Bundle.main.url(forResource: name, withExtension: "json"), let data = try? Data(contentsOf: url) else { return 0 }
        return data.count
    }
}

extension LabModelSnapshot {
    init(recordingID: UUID, analysis: SNNAnalysis) {
        self.recordingID = recordingID; snnModel = analysis.weights.modelID
        snn = analysis.trace.uncertain ? nil : analysis.trace.winner; snnScores = analysis.trace.probabilities
        quantizedRule = analysis.prepared.rule
        annModel = analysis.ann?.weights.modelID; ann = analysis.ann.flatMap { $0.uncertain ? nil : $0.winner }
        annScores = analysis.ann?.probabilities
    }
}
