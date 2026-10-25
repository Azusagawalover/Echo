import Foundation
import Combine

struct EchoSettings: Codable, Equatable {
    var sound = true
    var haptics = true
    var visualCues = true
    var reducedMotion = false
    var offsetMS = 0.0
    var palette: SoundPalette = .crystal

    init() {}
    private enum CodingKeys: String, CodingKey { case sound, haptics, visualCues, reducedMotion, offsetMS, palette }
    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        sound = try values.decodeIfPresent(Bool.self, forKey: .sound) ?? true
        haptics = try values.decodeIfPresent(Bool.self, forKey: .haptics) ?? true
        visualCues = try values.decodeIfPresent(Bool.self, forKey: .visualCues) ?? true
        reducedMotion = try values.decodeIfPresent(Bool.self, forKey: .reducedMotion) ?? false
        offsetMS = try values.decodeIfPresent(Double.self, forKey: .offsetMS) ?? 0
        palette = try values.decodeIfPresent(SoundPalette.self, forKey: .palette) ?? .crystal
        if !sound { visualCues = true }
    }
}

struct PlayRecord: Codable, Identifiable {
    var id = UUID()
    var date = Date()
    var patternID: String
    var title: String
    var mode: PlayMode
    var score: Int
    var order: Int
    var timing: Int
    var stars: Int
    var practice: Bool
}

struct LibraryState: Codable {
    var version = 1
    var settings = EchoSettings()
    var records: [PlayRecord] = []
    var creations: [RhythmPattern] = []
    var tutorialSeen = false
    var bests: [String: PlayRecord] = [:]

    init() {}
    private enum CodingKeys: String, CodingKey { case version, settings, records, creations, tutorialSeen, bests }
    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        version = try values.decode(Int.self, forKey: .version)
        settings = try values.decode(EchoSettings.self, forKey: .settings)
        records = try values.decode([PlayRecord].self, forKey: .records)
        creations = try values.decode([RhythmPattern].self, forKey: .creations)
        tutorialSeen = try values.decodeIfPresent(Bool.self, forKey: .tutorialSeen) ?? false
        bests = try values.decodeIfPresent([String: PlayRecord].self, forKey: .bests) ?? [:]
        for record in records where !record.practice {
            let key = record.patternID + "#" + record.mode.rawValue
            if let old = bests[key], old.stars > record.stars || (old.stars == record.stars && old.score >= record.score) { continue }
            bests[key] = record
        }
    }
}

@MainActor final class EchoLibrary: ObservableObject {
    @Published private(set) var state = LibraryState()
    @Published var errorMessage: String?
    private let url: URL
    private var readable = true

    init(url: URL? = nil) {
        self.url = url ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Echo", isDirectory: true).appendingPathComponent("library.json")
        guard FileManager.default.fileExists(atPath: self.url.path) else { return }
        do {
            let data = try Data(contentsOf: self.url)
            guard data.count < 8_000_000 else { throw LibraryError.invalid }
            let decoded = try JSONDecoder().decode(LibraryState.self, from: data)
            guard decoded.version == 1, decoded.creations.count <= 100, decoded.creations.allSatisfy(\.isValid),
                  decoded.records.count <= 500, decoded.bests.count <= 2000, decoded.settings.offsetMS.isFinite,
                  (-250...250).contains(decoded.settings.offsetMS) else { throw LibraryError.invalid }
            state = decoded
        } catch {
            readable = false
            errorMessage = "无法读取存档，原文件已保留。暂不覆盖保存，你仍可以试玩内置关卡。"
        }
    }

    @discardableResult private func commit(_ value: LibraryState) -> Bool {
        guard readable else { errorMessage = "原存档暂时无法读取，已暂停保存，避免覆盖。"; return false }
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(value).write(to: url, options: .atomic)
            state = value
            return true
        } catch { errorMessage = "保存失败，请检查设备存储空间。当前文件未被替换。"; return false }
    }

    func setSettings(_ settings: EchoSettings) {
        var next = state; next.settings = settings; _ = commit(next)
    }
    func sawTutorial() { var next = state; next.tutorialSeen = true; _ = commit(next) }
    @discardableResult func record(pattern: RhythmPattern, mode: PlayMode, result: RhythmResult, practice: Bool) -> Bool {
        var next = state
        let record = PlayRecord(patternID: pattern.id, title: pattern.title, mode: mode,
            score: result.score, order: result.order, timing: result.timing, stars: result.stars, practice: practice)
        next.records.insert(record, at: 0)
        if !practice {
            let key = pattern.id + "#" + mode.rawValue
            if let old = next.bests[key] {
                if record.stars > old.stars || (record.stars == old.stars && record.score > old.score) { next.bests[key] = record }
            } else { next.bests[key] = record }
            if next.bests.count > 2000, let removable = next.bests.filter({ !$0.key.hasPrefix("chapter-") }).min(by: { $0.value.date < $1.value.date })?.key { next.bests.removeValue(forKey: removable) }
        }
        next.records = Array(next.records.prefix(500)); return commit(next)
    }
    @discardableResult func save(_ pattern: RhythmPattern) -> Bool {
        guard pattern.isValid else { errorMessage = "关卡需要 2～32 个音符、有效速度和不重复的时间点。"; return false }
        var next = state
        if let index = next.creations.firstIndex(where: { $0.id == pattern.id }) { next.creations[index] = pattern }
        else {
            guard next.creations.count < 100 else { errorMessage = "最多保存 100 个作品，请先移除不再需要的作品。"; return false }
            next.creations.insert(pattern, at: 0)
        }
        return commit(next)
    }
    func removeCreation(id: String) { var next = state; next.creations.removeAll { $0.id == id }; _ = commit(next) }
    func best(_ id: String, mode: PlayMode = .echo) -> PlayRecord? {
        state.bests[id + "#" + mode.rawValue]
    }
    func stars(_ id: String) -> Int {
        best(id)?.stars ?? 0
    }
    func unlocked(_ index: Int) -> Bool { index == 0 || stars(LevelCatalog.levels[index - 1].id) > 0 }
    var nextLevel: RhythmPattern { LevelCatalog.levels.first { stars($0.id) == 0 } ?? LevelCatalog.levels[0] }
    func nextChapterLevel(after id: String) -> RhythmPattern? {
        guard let index = LevelCatalog.levels.firstIndex(where: { $0.id == id }),
              index + 1 < LevelCatalog.levels.count, unlocked(index + 1) else { return nil }
        return LevelCatalog.levels[index + 1]
    }
    var completed: Int { LevelCatalog.levels.filter { stars($0.id) > 0 }.count }
    var starTotal: Int { LevelCatalog.levels.reduce(0) { $0 + stars($1.id) } }
    var achievements: [(String, String, Bool)] {
        [("第一声回响", "完成一次标准挑战", state.bests.values.contains { $0.stars > 0 }),
         ("节拍收藏家", "累计获得 12 颗章节星星", starTotal >= 12),
         ("完美复现", "在标准回声中获得 S 级", state.bests.values.contains { $0.mode == .echo && $0.stars > 0 && $0.score >= 95 }),
         ("声音创作者", "保存自己的第一个节奏", !state.creations.isEmpty),
         ("城市苏醒", "完成全部 24 个章节关卡", completed == 24)]
    }
    enum LibraryError: Error { case invalid }
}
