import Foundation

enum SoundPalette: String, Codable, CaseIterable, Identifiable {
    case crystal, keys, wood, electronic
    var id: String { rawValue }
    var title: String {
        switch self {
        case .crystal: return "水晶回声"
        case .keys: return "柔和琴键"
        case .wood: return "木质敲击"
        case .electronic: return "电子脉冲"
        }
    }
}

struct BeatNote: Codable, Equatable, Identifiable {
    var tick: Int
    var lane: Int
    var id: Int { tick }
}

struct RhythmPattern: Codable, Equatable, Identifiable {
    var id: String
    var title: String
    var detail: String
    var chapter: Int
    var bpm: Double
    var notes: [BeatNote]
    var secondsPerTick: Double { 30 / bpm }
    var duration: Double { Double(notes.last?.tick ?? 0) * secondsPerTick + 1.2 }
    var isValid: Bool {
        !id.isEmpty && id.count <= 120 && !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && title.count <= 40 &&
        bpm.isFinite && (50...180).contains(bpm) && (2...32).contains(notes.count) &&
        notes.first?.tick == 0 && notes.allSatisfy { (0..<4).contains($0.lane) && (0..<64).contains($0.tick) } &&
        zip(notes, notes.dropFirst()).allSatisfy { $0.tick < $1.tick }
    }
    func time(of note: BeatNote, speed: Double = 1) -> Double { Double(note.tick) * secondsPerTick / speed }
}

enum PlayMode: String, Codable, CaseIterable, Identifiable {
    case echo, follow, silence
    var id: String { rawValue }
    var title: String {
        switch self { case .echo: return "回声记忆"; case .follow: return "同步跟奏"; case .silence: return "消失节拍" }
    }
    var symbol: String {
        switch self { case .echo: return "waveform.path"; case .follow: return "dot.radiowaves.left.and.right"; case .silence: return "moon.stars" }
    }
    var explanation: String {
        switch self {
        case .echo: return "先听一段，再凭记忆复现颜色和节奏。第一次点击决定你的起点。"
        case .follow: return "跟随四拍倒数，在提示亮起时点击相同的音垫。"
        case .silence: return "先听节奏，复现时只保留前两次提示。让心里的节拍继续。"
        }
    }
}

struct TapEvent: Codable, Equatable {
    var lane: Int
    var time: Double
}

struct NoteJudgement: Identifiable {
    let id: Int
    let lane: Int
    let target: Double
    let actual: Double?
    let correctLane: Bool
    var delta: Double? { actual.map { $0 - target } }
    var label: String {
        guard let delta else { return "漏点" }
        if !correctLane { return "颜色有误" }
        if abs(delta) <= 0.08 { return "准确" }
        return delta < 0 ? "偏早" : "偏晚"
    }
}

struct RhythmResult {
    var score: Int
    var order: Int
    var timing: Int
    var judgements: [NoteJudgement]
    var extraCount: Int
    var meanError: Double
    var passed: Bool
    var stars: Int { !passed ? 0 : score >= 95 ? 3 : score >= 85 ? 2 : 1 }
    var grade: String { score >= 95 ? "S" : score >= 85 ? "A" : score >= 70 ? "B" : "C" }
    var advice: String {
        if order < 100 { return "先记住音垫顺序，再慢一点复现。可以重听或进入慢速练习。" }
        if timing < 80 { return "顺序已经记住了。试着轻数节拍，注意相邻两次点击之间的停顿。" }
        return "节奏很稳！试试取消视觉提示，或挑战下一段更长的回声。"
    }
}

enum RhythmScorer {
    /// 用序列对齐区分错色、漏点和多点，避免漏一拍导致后续全部错位。
    static func evaluate(pattern: RhythmPattern, taps: [TapEvent], mode: PlayMode, speed: Double = 1) -> RhythmResult {
        let clean = Array(taps.filter { (0..<4).contains($0.lane) && $0.time.isFinite && $0.time >= 0 }.prefix(96))
        let origin = mode == .echo ? (clean.first?.time ?? 0) : 0
        let input = clean.map { TapEvent(lane: $0.lane, time: $0.time - origin) }
        let target = pattern.notes
        let n = target.count, m = input.count
        guard pattern.isValid, speed.isFinite, speed > 0, n > 0 else {
            return RhythmResult(score: 0, order: 0, timing: 0, judgements: [], extraCount: m, meanError: 0, passed: false)
        }
        var costs = Array(repeating: Array(repeating: 0.0, count: m + 1), count: n + 1)
        var moves = Array(repeating: Array(repeating: 0, count: m + 1), count: n + 1)
        for i in 1...n { costs[i][0] = Double(i); moves[i][0] = 1 }
        if m > 0 { for j in 1...m { costs[0][j] = Double(j); moves[0][j] = 2 } }
        let tolerance = max(0.16, pattern.secondsPerTick / speed * 0.65)
        for i in 1...n {
            guard m > 0 else { continue }
            for j in 1...m {
                let expected = pattern.time(of: target[i - 1], speed: speed)
                let mismatch = target[i - 1].lane == input[j - 1].lane ? 0.0 : 1.0
                let tie = min(1, abs(input[j - 1].time - expected) / tolerance) * 0.08
                let candidates = [costs[i - 1][j - 1] + mismatch + tie, costs[i - 1][j] + 1, costs[i][j - 1] + 1]
                let move = candidates.enumerated().min { $0.element < $1.element }!.offset
                costs[i][j] = candidates[move]; moves[i][j] = move
            }
        }
        var aligned: [Int: Int] = [:]
        var i = n, j = m, extras = 0
        while i > 0 || j > 0 {
            switch moves[i][j] {
            case 0 where i > 0 && j > 0: aligned[i - 1] = j - 1; i -= 1; j -= 1
            case 1 where i > 0: i -= 1
            default: extras += 1; j -= 1
            }
        }
        let judgements = target.enumerated().map { index, note in
            let actual = aligned[index].map { input[$0] }
            return NoteJudgement(id: index, lane: note.lane, target: pattern.time(of: note, speed: speed),
                actual: actual?.time, correctLane: actual?.lane == note.lane)
        }
        let correct = judgements.filter(\.correctLane)
        let order = Int((Double(correct.count) / Double(max(n, m)) * 100).rounded())
        let rhythm = correct.reduce(0.0) { partial, note in
            partial + max(0, 1 - max(0, abs(note.delta ?? 0) - 0.045) / tolerance)
        }
        let timing = Int((rhythm / Double(max(n, m)) * 100).rounded())
        let score = Int((Double(order) * 0.6 + Double(timing) * 0.4).rounded())
        let mean = correct.isEmpty ? 0 : correct.reduce(0.0) { $0 + abs($1.delta ?? 0) } / Double(correct.count)
        return RhythmResult(score: score, order: order, timing: timing, judgements: judgements, extraCount: extras,
            meanError: mean, passed: order == 100 && score >= 75)
    }
}

struct PracticePlan {
    enum Focus { case sequence, early, late, longGap, steady }
    var focus: Focus
    var title: String
    var detail: String
    var noteIndex: Int

    static func analyze(_ result: RhythmResult, pattern: RhythmPattern) -> PracticePlan {
        let notes = result.judgements
        let worst = notes.indices.max {
            (notes[$0].correctLane ? abs(notes[$0].delta ?? 0) : 100) <
            (notes[$1].correctLane ? abs(notes[$1].delta ?? 0) : 100)
        } ?? 0
        if result.order < 100 {
            return PracticePlan(focus: .sequence, title: "先把顺序记稳", detail: "本次有错色、漏点或多点。先在短片段里记住形状顺序，再恢复速度。", noteIndex: worst)
        }
        let pairs = zip(notes, notes.dropFirst()).filter { $0.correctLane && $1.correctLane && $0.actual != nil && $1.actual != nil }
        if let gap = pairs.max(by: {
            abs(($0.1.actual! - $0.0.actual!) - ($0.1.target - $0.0.target)) <
            abs(($1.1.actual! - $1.0.actual!) - ($1.1.target - $1.0.target))
        }), pattern.notes.indices.contains(gap.0.id), pattern.notes.indices.contains(gap.1.id),
           pattern.notes[gap.1.id].tick - pattern.notes[gap.0.id].tick >= 3,
           abs((gap.1.actual! - gap.0.actual!) - (gap.1.target - gap.0.target)) > 0.12 {
            return PracticePlan(focus: .longGap, title: "留住停顿后的第一拍", detail: "本次较大的偏差出现在长停顿之后。空拍时继续默数，别急着接下一声。", noteIndex: gap.1.id)
        }
        // 第一拍在回声模式中固定为零；只用后续音符判断偏早/偏晚。
        let deltas = notes.dropFirst().filter(\.correctLane).compactMap(\.delta)
        let early = deltas.filter { $0 < -0.08 }.count
        let late = deltas.filter { $0 > 0.08 }.count
        if !deltas.isEmpty, Double(early) / Double(deltas.count) >= 0.6 {
            return PracticePlan(focus: .early, title: "放松一点，别抢拍", detail: "本次多数后续音符偏早。先用 75% 速度保持间隔，稳定后再提速。", noteIndex: worst)
        }
        if !deltas.isEmpty, Double(late) / Double(deltas.count) >= 0.6 {
            return PracticePlan(focus: .late, title: "让下一拍提前住进心里", detail: "本次多数后续音符偏晚。听示范时默数拍点，减少每次点击前的犹豫。", noteIndex: worst)
        }
        return PracticePlan(focus: .steady, title: result.passed ? "节拍已经连起来了" : "再把间隔磨匀一点", detail: result.passed ? "可以逐级提速，或回到标准挑战检验成果。练习即使达到原速，也不会解锁章节。" : "没有明显的单一偏差方向。先重练偏差最大的短片段，再完整演奏。", noteIndex: worst)
    }

    func segment(of pattern: RhythmPattern) -> RhythmPattern {
        let lower = min(max(0, noteIndex - 2), max(0, pattern.notes.count - 4))
        let subset = Array(pattern.notes[lower..<min(pattern.notes.count, lower + 4)])
        guard let first = subset.first else { return pattern }
        var copy = pattern
        copy.id = "practice-" + UUID().uuidString
        copy.title = "针对练习 · " + String(pattern.title.prefix(20))
        copy.notes = subset.map { BeatNote(tick: $0.tick - first.tick, lane: $0.lane) }
        return copy
    }
}

enum LevelCatalog {
    static let chapters = ["雨巷", "钟楼", "夜行列车", "回声广场"]
    static let subtitles = ["听见第一滴雨", "让停顿也有形状", "沿着节奏出发", "找回城市的声音"]
    static let symbols = ["cloud.rain", "clock", "tram", "sparkles"]
    static let levels: [RhythmPattern] = {
        let rhythms = [[0,2,4,6], [0,2,3,6], [0,1,4,6], [0,2,4,5,8], [0,1,3,6,8], [0,2,3,5,6,9]]
        let names = [["屋檐", "水洼", "细雨", "涟漪", "雨声渐密", "雨后初晴"],
                     ["摆钟", "刻度", "回廊", "钟摆之间", "午后钟声", "整点回响"],
                     ["出发信号", "车轮", "站台", "隧道微光", "交错轨迹", "抵达"],
                     ["路灯亮起", "街角", "人群", "四种颜色", "城市合奏", "最后的回声"]]
        return (0..<24).map { index in
            let chapter = index / 6, stage = index % 6
            let ticks = rhythms[stage] + (chapter >= 2 ? [12, 14 + stage % 2] : [])
            let lanes = ticks.enumerated().map { k, tick in
                BeatNote(tick: tick, lane: (k * (stage % 2 + 1) + stage + chapter) % (chapter == 0 && stage < 3 ? 2 : 4))
            }
            return RhythmPattern(id: "chapter-\(index)", title: names[chapter][stage], detail: subtitles[chapter],
                chapter: chapter, bpm: Double(72 + chapter * 12 + stage * 3), notes: lanes)
        }
    }()
    static func daily(date: Date = Date()) -> RhythmPattern {
        let parts = Calendar.current.dateComponents([.year, .month, .day], from: date)
        let stamp = String(format: "%04d-%02d-%02d", parts.year ?? 2026, parts.month ?? 1, parts.day ?? 1)
        var seed = stamp.utf8.reduce(UInt64(0)) { $0 &* 31 &+ UInt64($1) }
        func next() -> Int { seed = seed &* 6364136223846793005 &+ 1; return Int((seed >> 33) % 4) }
        var tick = 0
        let notes = (0..<8).map { _ -> BeatNote in
            let note = BeatNote(tick: tick, lane: next()); tick += next() % 2 + 1; return note
        }
        return RhythmPattern(id: "daily-\(stamp)", title: "今日回声", detail: stamp, chapter: 3, bpm: 96, notes: notes)
    }
}
