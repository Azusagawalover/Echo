import Foundation
import Combine

@MainActor final class RhythmLabStore: ObservableObject {
    static let shared = RhythmLabStore()
    @Published private(set) var state = LabArchiveState()
    @Published var errorMessage: String?
    private let url: URL
    private var readable = true

    init(url: URL? = nil) {
        self.url = url ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Echo", isDirectory: true).appendingPathComponent("lab-archive.json")
        guard FileManager.default.fileExists(atPath: self.url.path) else { return }
        do {
            let data = try Data(contentsOf: self.url)
            guard data.count <= 6_000_000 else { throw LabStorageError.invalid }
            let loaded = try JSONDecoder().decode(LabArchiveState.self, from: data)
            guard loaded.isValid else { throw LabStorageError.invalid }
            state = loaded
        } catch { readable = false; errorMessage = LabStorageError.protectedFile.localizedDescription }
    }
    private func commit(_ next: LabArchiveState) throws {
        guard readable else { throw LabStorageError.protectedFile }
        guard next.isValid else { throw LabStorageError.invalid }
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(next)
        guard data.count <= 6_000_000 else { throw LabStorageError.full }
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url, options: .atomic)
        state = next
    }
    static func entry(recording: SNNLabRecording, model: LabModelSnapshot?, label: RhythmState?, note: String) throws -> LabArchiveEntry {
        guard !recording.simulated else { throw LabStorageError.simulated }
        let entry = LabArchiveEntry(id: recording.id, recording: recording, savedAt: Date(),
            measurement: LabMeasurement.measure(recording), model: model, manualLabel: label, note: note)
        guard entry.isValid else { throw LabStorageError.invalid }
        return entry
    }
    func save(recording: SNNLabRecording, model: LabModelSnapshot?, label: RhythmState?, note: String) throws {
        guard !state.entries.contains(where: { $0.id == recording.id || $0.recording.contentKey == recording.contentKey }) else {
            throw LabStorageError.duplicate
        }
        guard state.entries.count < 200 else { throw LabStorageError.full }
        let entry = try Self.entry(recording: recording, model: model, label: label, note: note)
        var next = state; next.entries.insert(entry, at: 0); try commit(next)
    }
    func annotate(id: UUID, label: RhythmState?, note: String) throws {
        var next = state
        guard let index = next.entries.firstIndex(where: { $0.id == id }) else { throw LabStorageError.invalid }
        next.entries[index].manualLabel = label; next.entries[index].note = note; try commit(next)
    }
    func remove(id: UUID) throws {
        var next = state; next.entries.removeAll { $0.id == id }; try commit(next)
    }
    func removeAll() throws { try commit(LabArchiveState()) }
    func contains(_ recording: SNNLabRecording) -> Bool {
        state.entries.contains { $0.id == recording.id || $0.recording.contentKey == recording.contentKey }
    }
}
