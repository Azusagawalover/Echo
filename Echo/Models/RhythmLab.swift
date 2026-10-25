import Foundation

struct SNNLabRecording: Identifiable, Codable {
    let id: UUID
    let capturedAt: Date
    let pattern: RhythmPattern
    let taps: [TapEvent]
    var mode: PlayMode
    var speed: Double
    var simulated: Bool
    var sourceTitle: String

    init(id: UUID = UUID(), capturedAt: Date = Date(), pattern: RhythmPattern, taps: [TapEvent],
         mode: PlayMode = .echo, speed: Double = 1, simulated: Bool = false, sourceTitle: String = "你的实际演奏") {
        self.id = id; self.capturedAt = capturedAt; self.pattern = pattern; self.taps = taps
        self.mode = mode; self.speed = speed; self.simulated = simulated; self.sourceTitle = sourceTitle
    }
    static func example(_ state: RhythmState) -> SNNLabRecording {
        SNNLabRecording(pattern: SNNExamples.pattern, taps: SNNExamples.taps(state: state),
                        simulated: true, sourceTitle: "模拟样本 · " + state.title)
    }
    var isValid: Bool {
        pattern.isValid && speed.isFinite && (0.5...1.5).contains(speed) && taps.count <= 96 &&
        sourceTitle.count <= 120 && capturedAt.timeIntervalSince1970.isFinite &&
        (0...5_000_000_000).contains(capturedAt.timeIntervalSince1970) &&
        taps.allSatisfy { (0..<4).contains($0.lane) && $0.time.isFinite && (0...120).contains($0.time) } &&
        zip(taps, taps.dropFirst()).allSatisfy { $0.time < $1.time }
    }
    var reference: [TapEvent] {
        guard pattern.isValid, speed.isFinite, speed > 0 else { return [] }
        return pattern.notes.map { TapEvent(lane: $0.lane, time: pattern.time(of: $0, speed: speed)) }
    }
    var alignedTaps: [TapEvent] {
        let origin = mode == .echo ? (taps.first?.time ?? 0) : 0
        return taps.map { TapEvent(lane: $0.lane, time: $0.time - origin) }
    }
    /// Comparable groups never mix a different phrase, play mode or actual practice speed.
    var groupKey: String {
        "\(pattern.bpm.bitPattern)#\(mode.rawValue)#\(speed.bitPattern)#" +
        pattern.notes.map { "\($0.tick):\($0.lane)" }.joined(separator: ",")
    }
    var contentKey: String { groupKey + "#" + taps.map { "\($0.lane):\($0.time.bitPattern)" }.joined(separator: ",") }
}

struct LabMeasurement: Codable, Equatable {
    let mean: Double
    let meanAbsolute: Double
    let spread: Double
    let meanAbsoluteMS: Double
    let intervalCount: Int

    static func measure(_ recording: SNNLabRecording) -> LabMeasurement? {
        guard recording.isValid, recording.taps.count == recording.pattern.notes.count,
              zip(recording.pattern.notes, recording.taps).allSatisfy({ $0.lane == $1.lane }) else { return nil }
        let expected = recording.reference, actual = recording.alignedTaps
        var errors: [Double] = [], errorsMS: [Double] = []
        for index in 1..<expected.count {
            let target = expected[index].time - expected[index - 1].time
            let observed = actual[index].time - actual[index - 1].time
            errors.append(observed / target - 1); errorsMS.append(abs(observed - target) * 1000)
        }
        let count = Double(errors.count), mean = errors.reduce(0, +) / count
        return LabMeasurement(mean: mean, meanAbsolute: errors.map(abs).reduce(0, +) / count,
                              spread: sqrt(errors.reduce(0) { $0 + pow($1 - mean, 2) } / count),
                              meanAbsoluteMS: errorsMS.reduce(0, +) / count, intervalCount: errors.count)
    }
}

struct LabIssue: Identifiable {
    enum Kind { case wrongLane, missing, extra, timing, scope, invalid }
    let id: Int
    let kind: Kind
    let noteIndex: Int?
    let title: String
    let detail: String
}

struct LabDiagnostics {
    let issues: [LabIssue]
    let result: RhythmResult?
    var repairIndex: Int? { issues.first(where: { $0.noteIndex != nil })?.noteIndex }

    static func inspect(_ recording: SNNLabRecording) -> LabDiagnostics {
        guard recording.isValid else {
            return LabDiagnostics(issues: [LabIssue(id: 0, kind: .invalid, noteIndex: nil, title: "输入时间或谱面无效",
                detail: "不能安全回放、保存或分析这份记录。请重新演奏；原有游戏存档不受影响。")], result: nil)
        }
        let result = RhythmScorer.evaluate(pattern: recording.pattern, taps: recording.taps,
                                          mode: recording.mode, speed: recording.speed)
        var issues: [LabIssue] = []
        for note in result.judgements {
            if note.actual == nil {
                issues.append(LabIssue(id: issues.count, kind: .missing, noteIndex: note.id,
                    title: "第 \(note.id + 1) 拍漏点", detail: "这一拍没有匹配到点击。先听清它前面的停顿，再练这个片段。"))
            } else if !note.correctLane {
                issues.append(LabIssue(id: issues.count, kind: .wrongLane, noteIndex: note.id,
                    title: "第 \(note.id + 1) 拍颜色不对", detail: "需要点击第 \(note.lane + 1) 种音符；先记顺序，再练间隔。"))
            } else if let delta = note.delta, abs(delta) > 0.08 {
                issues.append(LabIssue(id: issues.count, kind: .timing, noteIndex: note.id,
                    title: "第 \(note.id + 1) 拍" + (delta < 0 ? "偏早" : "偏晚"),
                    detail: String(format: "相对目标时刻偏差 %+.0f ms。该数值是规则测量，不是模型预测。", delta * 1000)))
            }
        }
        // Fix ordering mistakes before offering timing advice.
        issues.sort { lhs, rhs in
            let left = lhs.kind == .timing ? 1 : 0, right = rhs.kind == .timing ? 1 : 0
            return left == right ? (lhs.noteIndex ?? 0) < (rhs.noteIndex ?? 0) : left < right
        }
        if result.extraCount > 0 {
            issues.insert(LabIssue(id: 100, kind: .extra, noteIndex: nil, title: "多点了 \(result.extraCount) 次",
                detail: "多点无法可靠归给某一拍，因此不虚构具体位置。对照两条回放找出多出来的声音。"), at: 0)
        }
        if !(4...17).contains(recording.pattern.notes.count) {
            issues.append(LabIssue(id: 101, kind: .scope, noteIndex: nil, title: "短句长度超出模型范围",
                detail: "模型仅支持 4–17 个音符；仍可回放、查看规则结果并练习片段。"))
        }
        return LabDiagnostics(issues: issues, result: result)
    }
}

struct LabPracticePlan: Identifiable {
    let id = UUID()
    let full: RhythmPattern
    let segment: RhythmPattern
    let rangeTitle: String
    let explanation: String
    let mode: PlayMode

    init(recording: SNNLabRecording, analysis: SNNAnalysis? = nil, focusIndex: Int? = nil) {
        full = recording.pattern.isValid ? recording.pattern : SNNExamples.pattern; mode = recording.mode
        let diagnostics = LabDiagnostics.inspect(recording)
        let hasOrderIssue = diagnostics.issues.contains { $0.kind == .wrongLane || $0.kind == .missing || $0.kind == .extra }
        var intervalFocus: Int?
        if LabMeasurement.measure(recording) != nil {
            let expected = recording.reference, actual = recording.alignedTaps
            func error(_ index: Int) -> Double {
                abs((actual[index].time - actual[index - 1].time) / (expected[index].time - expected[index - 1].time) - 1)
            }
            intervalFocus = (1..<expected.count).max { error($0) < error($1) }
        }
        let focus = focusIndex ?? (hasOrderIssue ? diagnostics.repairIndex : intervalFocus) ?? 0
        let count = min(6, full.notes.count)
        let start = min(max(0, focus - 2), max(0, full.notes.count - count))
        let subset = Array(full.notes[start..<start + count])
        var piece = full
        piece.id = "lab-practice-" + UUID().uuidString
        piece.title = "片段 · " + String(full.title.prefix(24))
        piece.notes = subset.map { BeatNote(tick: $0.tick - subset[0].tick, lane: $0.lane) }
        segment = piece; rangeTitle = "原谱第 \(start + 1)–\(start + count) 拍"
        if hasOrderIssue {
            explanation = "先修复错色、漏点或多点，再练节拍。按规则定位片段，不使用模型猜测错误位置。"
        } else if let analysis, !analysis.trace.uncertain, analysis.trace.winner == analysis.prepared.rule {
            explanation = "模型与规则均倾向“\(analysis.trace.winner.title)”。" + analysis.trace.winner.suggestion
        } else {
            explanation = "按规则测到的较大偏差选择片段；模型不确定或意见不同，不强行采用模型建议。"
        }
    }
}

struct LabPracticeSequence {
    let rounds: Int
    let progressive: Bool
    private(set) var completed = 0
    private(set) var speed: Double
    init(rounds: Int, speed: Double, progressive: Bool) {
        self.rounds = min(3, max(1, rounds)); self.speed = speed.isFinite ? min(1, max(0.6, speed)) : 0.75
        self.progressive = progressive
    }
    mutating func complete(passed: Bool) {
        guard completed < rounds else { return }
        completed += 1
        if progressive, passed, completed < rounds {
            speed = [0.6, 0.75, 0.9, 1.0].first(where: { $0 > speed + 0.001 }) ?? 1
        }
    }
    var finished: Bool { completed >= rounds }
}

struct LabModelSnapshot: Codable {
    let recordingID: UUID
    let snnModel: String
    let snn: RhythmState?
    let snnScores: [Double]
    let quantizedRule: RhythmState
    let annModel: String?
    let ann: RhythmState?
    let annScores: [Double]?

    var isValid: Bool {
        func valid(_ scores: [Double]) -> Bool {
            scores.count == 4 && scores.allSatisfy { $0.isFinite && (0...1).contains($0) } && abs(scores.reduce(0, +) - 1) < 0.0001
        }
        func predicted(_ scores: [Double]) -> RhythmState? {
            let ranked = scores.sorted(by: >)
            guard ranked[0] >= 0.65, ranked[0] - ranked[1] >= 0.15 else { return nil }
            return RhythmState.allCases[scores.indices.max { scores[$0] < scores[$1] } ?? 0]
        }
        guard snnModel == "echo-interval-lif-v1", valid(snnScores), snn == predicted(snnScores) else { return false }
        if let annScores {
            return annModel == "echo-interval-mlp-v1" && valid(annScores) && ann == predicted(annScores)
        }
        return annModel == nil && ann == nil
    }
}

struct LabArchiveEntry: Identifiable, Codable {
    let id: UUID
    let recording: SNNLabRecording
    let savedAt: Date
    let measurement: LabMeasurement?
    let model: LabModelSnapshot?
    var manualLabel: RhythmState?
    var note: String
    var isValid: Bool {
        recording.isValid && !recording.simulated && id == recording.id && note.count <= 200 &&
        savedAt.timeIntervalSince1970.isFinite && (0...5_000_000_000).contains(savedAt.timeIntervalSince1970) &&
        measurement == LabMeasurement.measure(recording) &&
        (model == nil || (model!.recordingID == recording.id && model!.isValid))
    }
}

struct LabArchiveState: Codable {
    var schema = 1
    var entries: [LabArchiveEntry] = []
    var isValid: Bool {
        schema == 1 && entries.count <= 200 && entries.allSatisfy(\.isValid) &&
        Set(entries.map(\.id)).count == entries.count && Set(entries.map { $0.recording.contentKey }).count == entries.count
    }
}

struct LabExportEnvelope: Codable {
    let schema: Int
    let kind: String
    let exportedAt: Date
    let description: String
    let entries: [LabArchiveEntry]

    init(entries: [LabArchiveEntry]) {
        schema = 1; kind = "EchoRhythmLab"; exportedAt = Date()
        description = "用户主动导出的本机演奏。manualLabel 是人工标注；model 是模型预测，不能当作真实标签。无姓名或设备标识。"
        self.entries = entries
    }
    func encoded() throws -> Data {
        guard !entries.isEmpty, entries.count <= 200, entries.allSatisfy(\.isValid) else { throw LabStorageError.invalid }
        let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(self)
    }
}

struct LabTrend {
    let entries: [LabArchiveEntry]
    init(entries: [LabArchiveEntry], groupKey: String) {
        self.entries = Array(entries.filter { $0.recording.groupKey == groupKey && $0.measurement != nil }
            .sorted { $0.recording.capturedAt < $1.recording.capturedAt }.suffix(20))
    }
    var change: Double? {
        guard entries.count >= 6 else { return nil }
        let early = entries.prefix(3).compactMap { $0.measurement?.meanAbsolute }.reduce(0, +) / 3
        let recent = entries.suffix(3).compactMap { $0.measurement?.meanAbsolute }.reduce(0, +) / 3
        return recent - early
    }
}

enum LabStorageError: LocalizedError {
    case invalid, simulated, duplicate, full, protectedFile
    var errorDescription: String? {
        switch self {
        case .invalid: return "演奏数据无效，未保存或导出。"
        case .simulated: return "模拟样本不进入个人档案，也不作为真人数据导出。"
        case .duplicate: return "这份演奏已经保存，不重复计入进步趋势。"
        case .full: return "档案已达 200 条，请先导出或删除不需要的记录；不会自动丢弃旧数据。"
        case .protectedFile: return "原实验档案暂时无法读取，已暂停写入以免覆盖。正式游戏存档不受影响。"
        }
    }
}

enum LabPlaybackSource: String { case reference, performance }

struct LabPlaybackPlan {
    let events: [TapEvent]
    let duration: Double
    init(recording: SNNLabRecording, source: LabPlaybackSource) throws {
        guard recording.isValid else { throw LabStorageError.invalid }
        events = source == .reference ? recording.reference : recording.alignedTaps
        guard !events.isEmpty else { throw SNNError.unsupported("本次没有可回放的点击。") }
        duration = max(1, max(recording.reference.last?.time ?? 0, recording.alignedTaps.last?.time ?? 0)) + 0.45
    }
}
