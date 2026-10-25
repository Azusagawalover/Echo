import SwiftUI
import UniformTypeIdentifiers

struct RhythmDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }
    var pattern: RhythmPattern
    init(pattern: RhythmPattern) { self.pattern = pattern }
    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents, data.count <= 128_000 else { throw CocoaError(.fileReadCorruptFile) }
        pattern = try JSONDecoder().decode(RhythmPattern.self, from: data)
        guard pattern.isValid else { throw CocoaError(.fileReadCorruptFile) }
    }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return FileWrapper(regularFileWithContents: try encoder.encode(pattern))
    }
}

struct EditorRequest: Identifiable { let id = UUID(); var pattern: RhythmPattern? }

struct StudioView: View {
    @EnvironmentObject private var library: EchoLibrary
    @Environment(\.scenePhase) private var scenePhase
    @State private var editor: EditorRequest?
    @State private var game: GameRequest?
    @State private var importing = false
    @State private var recording = false
    @State private var recordingStart: Double?
    @State private var events: [TapEvent] = []
    @State private var bpm = 96.0
    @State private var message = "点击音垫，随手弹一段。"
    @State private var deletion: RhythmPattern?
    @State private var confirmingDeletion = false
    @State private var exportPattern = LevelCatalog.levels[0]
    @State private var exporting = false
    @State private var recordClock = 0.0
    private let clock = Timer.publish(every: 0.2, on: .main, in: .common).autoconnect()
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 10) {
                    Text("ECHO / STUDIO").font(.caption.weight(.bold)).tracking(3).foregroundStyle(EchoStyle.accent)
                    Text("把灵感，敲成回声。") .font(.system(size: 28, weight: .bold, design: .rounded))
                    Text("自由演奏，或在格子里写下自己的节奏。") .font(.caption).foregroundStyle(.white.opacity(0.8))
                }.padding(22).frame(maxWidth: .infinity, minHeight: 150, alignment: .leading)
                    .background {
                        ScenicBackdrop(asset: "Hub-Studio", tint: EchoStyle.colors[1])
                        LinearGradient(colors: [EchoStyle.background.opacity(0.7), EchoStyle.background.opacity(0.15)], startPoint: .leading, endPoint: .trailing)
                    }.clipShape(RoundedRectangle(cornerRadius: 24))
                VStack(alignment: .leading, spacing: 20) {
                    SectionTitle(title: "随手一段", caption: recording ? "● 录制中 \(Int(recordClock))s · \(events.count)/32" : "四种声音")
                    PadGrid(compact: true) { lane, time in
                        EchoAudio.shared.hit(lane, settings: library.state.settings)
                        if recording, events.count < 32 {
                            if recordingStart == nil { recordingStart = time }
                            events.append(TapEvent(lane: lane, time: time - recordingStart!))
                            if events.count == 32 { stopRecording() }
                        }
                    }
                    BPMControl(value: $bpm, maximum: 160).disabled(recording)
                    Text(message).font(.caption).foregroundStyle(EchoStyle.secondary)
                    Button {
                        if recording { stopRecording() }
                        else { events = []; recordingStart = nil; recordClock = 0; recording = true; message = "第一下开始计时。最多录制 32 个音符或 20 秒。" }
                    } label: { Label(recording ? "停止并打开编辑器" : "录一段自己的节奏", systemImage: recording ? "stop.circle" : "record.circle") }.buttonStyle(EchoButtonStyle(secondary: true))
                }.echoInstrumentPanel()
                HStack(spacing: 12) {
                    Button { editor = EditorRequest() } label: { Label("格子编曲", systemImage: "plus") }.buttonStyle(EchoButtonStyle())
                    Button { importing = true } label: { Image(systemName: "square.and.arrow.down").font(.title3).padding(16).background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 16)) }.accessibilityLabel("导入节奏文件")
                }.disabled(recording)
                SectionTitle(title: "我的作品", caption: "\(library.state.creations.count) / 100")
                if library.state.creations.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "music.note.list").font(.largeTitle).foregroundStyle(EchoStyle.secondary)
                        Text("这里等着你的第一段节奏").font(.headline)
                        Text("保存后，可以试玩、编辑，或导出给朋友。") .font(.caption).foregroundStyle(EchoStyle.secondary)
                    }.frame(maxWidth: .infinity).padding(.vertical, 24).echoPanel()
                }
                ForEach(library.state.creations) { pattern in
                    VStack(alignment: .leading, spacing: 17) {
                        HStack {
                            VStack(alignment: .leading, spacing: 8) { Text(pattern.title).font(.headline); PatternDots(pattern: pattern) }
                            Spacer()
                            Menu {
                                Button("编辑", systemImage: "pencil") { editor = EditorRequest(pattern: pattern) }
                                Button("复制", systemImage: "doc.on.doc") {
                                    var copy = pattern; copy.id = "custom-" + UUID().uuidString; copy.title = String(pattern.title.prefix(35)) + " 副本"; library.save(copy)
                                }
                                Button("导出文件", systemImage: "square.and.arrow.up") { exportPattern = pattern; exporting = true }
                                Button("删除", systemImage: "trash", role: .destructive) { deletion = pattern; confirmingDeletion = true }
                            } label: { Image(systemName: "ellipsis").padding(12) }.accessibilityLabel("\(pattern.title) 更多操作")
                        }
                        RhythmMiniature(pattern: pattern)
                        HStack { Text("\(Int(pattern.bpm)) BPM · \(pattern.notes.count) 个音符").font(.caption).foregroundStyle(EchoStyle.secondary); Spacer(); Button("试玩 →") { game = GameRequest(pattern: pattern) }.font(.subheadline.bold()) }
                    }.echoPanel().disabled(recording)
                }
            }.padding(22).frame(maxWidth: 760).frame(maxWidth: .infinity)
        }.accessibilityHidden(game != nil || editor != nil).echoBackground().navigationTitle("创作").toolbar(.hidden, for: .navigationBar)
            .sheet(item: $editor) { PatternEditorView(original: $0.pattern) }
            .fullScreenCover(item: $game) { GameView(request: $0) }
            .fileImporter(isPresented: $importing, allowedContentTypes: [.json]) { result in importFile(result) }
            .fileExporter(isPresented: $exporting, document: RhythmDocument(pattern: exportPattern), contentType: .json,
                          defaultFilename: exportPattern.title) { result in
                if case .failure(let error) = result, (error as NSError).code != NSUserCancelledError { library.errorMessage = "导出没有完成，请重试。" }
            }
            .alert("删除这段节奏？", isPresented: $confirmingDeletion, presenting: deletion) { value in
                Button("删除作品", role: .destructive) { library.removeCreation(id: value.id); deletion = nil }
                Button("取消", role: .cancel) { }
            } message: { value in Text("将删除“\(value.title)”。已保存的游玩记录会保留。") }
            .onReceive(clock) { _ in
                guard recording, let recordingStart else { return }
                recordClock = max(0, ProcessInfo.processInfo.systemUptime - recordingStart)
                if recordClock >= 20 { stopRecording() }
            }
            .onChange(of: scenePhase) { _, phase in
                if phase != .active, recording { recording = false; message = "录制已中断，请重新录制。"; EchoAudio.shared.stopAll() }
            }
            .onAppear { EchoAudio.shared.prepare(palette: library.state.settings.palette) }
            .onDisappear { if recording { recording = false; message = "录制已停止，请重新录制。" }; EchoAudio.shared.stopAll() }
    }
    private func stopRecording() {
        recording = false
        var ticks: [Int: Int] = [:]
        for event in events {
            let tick = Int((event.time / (30 / bpm)).rounded())
            if tick < 64 { ticks[tick] = event.lane }
        }
        let notes = ticks.keys.sorted().map { BeatNote(tick: $0, lane: ticks[$0]!) }
        guard notes.count >= 2 else { message = "至少需要两个不同拍点，再试着录一段。"; return }
        let pattern = RhythmPattern(id: "custom-" + UUID().uuidString, title: "我的新节奏", detail: "自由演奏", chapter: 0, bpm: bpm, notes: notes)
        editor = EditorRequest(pattern: pattern)
        message = "已按半拍网格整理。可以在编辑器中调整后保存。"
    }
    private func importFile(_ result: Result<URL, Error>) {
        do {
            let url = try result.get()
            let access = url.startAccessingSecurityScopedResource(); defer { if access { url.stopAccessingSecurityScopedResource() } }
            let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
            guard size <= 128_000 else { throw CocoaError(.fileReadTooLarge) }
            let data = try Data(contentsOf: url)
            guard data.count <= 128_000 else { throw CocoaError(.fileReadTooLarge) }
            var pattern = try JSONDecoder().decode(RhythmPattern.self, from: data)
            guard pattern.isValid else { throw CocoaError(.fileReadCorruptFile) }
            pattern.id = "custom-" + UUID().uuidString; pattern.detail = "导入作品"; pattern.chapter = 0
            editor = EditorRequest(pattern: pattern)
        } catch {
            if (error as NSError).code != NSUserCancelledError { library.errorMessage = "无法导入。请选择有效的回声 JSON 关卡文件（不超过 128 KB）。" }
        }
    }
}

struct PatternEditorView: View {
    var original: RhythmPattern?
    @EnvironmentObject private var library: EchoLibrary
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @State private var title = "我的新节奏"
    @State private var bpm = 96.0
    @State private var notes: [BeatNote] = []
    @State private var steps = 16
    @State private var undo: [[BeatNote]] = []
    @State private var redo: [[BeatNote]] = []
    @State private var playing = false
    @State private var previewTask: Task<Void, Never>?
    @State private var showDiscard = false
    @State private var loaded = false
    @State private var game: GameRequest?
    @State private var patternID = "custom-" + UUID().uuidString
    @State private var previewStart = 0.0
    @State private var previewBaseTick = 0
    @Environment(\.echoReducedMotion) private var reduceMotion
    private var pattern: RhythmPattern {
        let base = notes.first?.tick ?? 0
        return RhythmPattern(id: patternID, title: title.trimmingCharacters(in: .whitespacesAndNewlines), detail: "我的创作", chapter: 0,
                             bpm: bpm, notes: notes.map { BeatNote(tick: $0.tick - base, lane: $0.lane) })
    }
    private var isDirty: Bool { title != (original?.title ?? "我的新节奏") || bpm != (original?.bpm ?? 96) || notes != (original?.notes ?? []) }
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    Text("每一格，是半拍。") .font(.system(.title, design: .rounded, weight: .bold))
                    Text("点击格子添加声音，同一拍只保留一种颜色。首个音符自动作为起点。") .font(.subheadline).foregroundStyle(EchoStyle.secondary)
                    TextField("给这段节奏取个名字", text: $title).textFieldStyle(.roundedBorder).accessibilityIdentifier("patternTitle")
                        .onChange(of: title) { _, value in title = String(value.prefix(40)) }
                    BPMControl(value: $bpm).disabled(playing)
                    beatGrid
                    HStack {
                        Button { if let previous = undo.popLast() { redo.append(notes); notes = previous } } label: { Image(systemName: "arrow.uturn.backward") }.disabled(undo.isEmpty)
                        Button { if let next = redo.popLast() { undo.append(notes); notes = next } } label: { Image(systemName: "arrow.uturn.forward") }.disabled(redo.isEmpty)
                        Spacer()
                        Text("\(notes.count) / 32 音符").font(.caption).foregroundStyle(EchoStyle.secondary)
                        if steps < 64 { Button("扩展 8 拍") { steps += 16 }.font(.caption) }
                    }.disabled(playing)
                    Button { preview() } label: { Label(playing ? "停止预览" : "播放预览", systemImage: playing ? "stop.fill" : "play.fill") }.buttonStyle(EchoButtonStyle(secondary: true)).disabled(notes.count < 2)
                    Button { stopPreview(); game = GameRequest(pattern: pattern, speed: 0.75) } label: { Text("进入试玩") }.buttonStyle(EchoButtonStyle(secondary: true)).disabled(!pattern.isValid)
                    Text("保存至少需要 2 个音符。作品只存储音符与节奏，不包含录音。") .font(.footnote).foregroundStyle(EchoStyle.secondary)
                }.padding(24).frame(maxWidth: 760).frame(maxWidth: .infinity)
            }.accessibilityHidden(game != nil).echoBackground().navigationTitle("节奏编辑器").navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) { Button("取消") { if isDirty { showDiscard = true } else { dismiss() } } }
                    ToolbarItem(placement: .topBarTrailing) { Button("保存") { stopPreview(); if library.save(pattern) { dismiss() } }.bold().disabled(!pattern.isValid).accessibilityIdentifier("savePattern") }
                }
        }.interactiveDismissDisabled(isDirty)
            .onAppear {
                guard !loaded else { return }; loaded = true
                if let original { title = original.title; bpm = original.bpm; notes = original.notes; patternID = original.id; steps = min(64, max(16, ((notes.last?.tick ?? 0) / 16 + 1) * 16)) }
            }
            .onDisappear { stopPreview() }
            .onChange(of: scenePhase) { _, value in if value != .active { stopPreview() } }
            .confirmationDialog("放弃尚未保存的修改？", isPresented: $showDiscard, titleVisibility: .visible) {
                Button("放弃修改", role: .destructive) { stopPreview(); dismiss() }
                Button("继续编辑", role: .cancel) { }
            }
            .fullScreenCover(item: $game) { GameView(request: $0) }
    }
    private func toggle(_ tick: Int, lane: Int) {
        let selected = notes.contains(BeatNote(tick: tick, lane: lane))
        guard selected || notes.contains(where: { $0.tick == tick }) || notes.count < 32 else { return }
        undo.append(notes); if undo.count > 80 { undo.removeFirst() }; redo = []
        notes.removeAll { $0.tick == tick }
        if !selected { notes.append(BeatNote(tick: tick, lane: lane)); notes.sort { $0.tick < $1.tick }; EchoAudio.shared.hit(lane, settings: library.state.settings) }
    }
    private func preview() {
        if playing { stopPreview(); return }
        playing = true
        let value = pattern
        previewStart = ProcessInfo.processInfo.systemUptime + 0.3
        previewBaseTick = notes.first?.tick ?? 0
        EchoAudio.shared.schedule(value.notes.map { SoundEvent(lane: $0.lane, time: value.time(of: $0)) }, start: previewStart, enabled: library.state.settings.sound, palette: library.state.settings.palette)
        previewTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: UInt64((value.duration + 0.3) * 1_000_000_000))
            if !Task.isCancelled { playing = false; EchoAudio.shared.stopSequence() }
        }
    }
    private func stopPreview() { previewTask?.cancel(); previewTask = nil; playing = false; EchoAudio.shared.stopSequence() }

    private var beatGrid: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("步进音序器", systemImage: "slider.horizontal.3").font(.headline)
                Spacer()
                Text("4/4 · 每格 ½ 拍").font(.caption.monospacedDigit()).foregroundStyle(EchoStyle.accent)
            }
            TimelineView(.animation(minimumInterval: reduceMotion ? 0.1 : 1 / 30, paused: !playing)) { _ in
                let elapsed = ProcessInfo.processInfo.systemUptime - previewStart
                let cursor = playing && elapsed >= 0 ? previewBaseTick + Int(elapsed / (30 / bpm)) : -1
                HStack(alignment: .top, spacing: 8) {
                    VStack(spacing: 9) {
                        Color.clear.frame(height: 20)
                        Color.clear.frame(height: 24)
                        ForEach(0..<4) { lane in
                            Image(systemName: EchoStyle.symbols[lane]).foregroundStyle(EchoStyle.colors[lane])
                                .frame(width: 24, height: 44)
                        }
                    }.frame(width: 24).padding(.vertical, 5).accessibilityHidden(true)
                ScrollViewReader { proxy in
                    ScrollView(.horizontal) {
                        VStack(spacing: 9) {
                            HStack(spacing: 6) {
                                ForEach(0..<(steps / 8), id: \.self) { bar in
                                    Text("第 \(bar + 1) 小节").font(.caption2).foregroundStyle(EchoStyle.secondary)
                                        .frame(width: 298, alignment: .leading)
                                }
                            }
                            HStack(spacing: 6) {
                                ForEach(0..<steps, id: \.self) { step in
                                    Text(step % 2 == 0 ? "\((step % 8) / 2 + 1)" : "&")
                                        .font(.caption2.monospacedDigit()).foregroundStyle(cursor == step ? EchoStyle.background : EchoStyle.secondary)
                                        .frame(width: 32, height: 24)
                                        .background(cursor == step ? EchoStyle.accent : .clear, in: RoundedRectangle(cornerRadius: 5))
                                        .id("grid-step-\(step)")
                                }
                            }
                            ForEach(0..<4) { lane in gridRow(lane, cursor: cursor) }
                        }.padding(.vertical, 5)
                    }.onChange(of: cursor) { _, value in
                        if value >= 0, value < steps, value == previewBaseTick || value % 8 == 0 {
                            proxy.scrollTo("grid-step-\(value)", anchor: .leading)
                        }
                    }
                }
                }
            }
            Text(playing ? "播放头与声音使用同一起点；空格保留停顿。" : "亮格是音符，深色格是停顿。每 8 格为一个小节。")
                .font(.caption2).foregroundStyle(EchoStyle.secondary)
        }.echoInstrumentPanel().accessibilityIdentifier("studioSequencer")
    }
    private func gridRow(_ lane: Int, cursor: Int) -> some View {
        HStack(spacing: 6) {
            ForEach(0..<steps, id: \.self) { step in
                let selected = notes.contains(BeatNote(tick: step, lane: lane))
                Button { toggle(step, lane: lane) } label: {
                    RoundedRectangle(cornerRadius: 7)
                        .fill(selected ? EchoStyle.colors[lane] : .white.opacity(step % 8 == 0 ? 0.14 : 0.055))
                        .overlay(RoundedRectangle(cornerRadius: 7).stroke(cursor == step ? .white.opacity(0.85) : EchoStyle.colors[lane].opacity(step % 8 == 0 ? 0.5 : 0.16), lineWidth: cursor == step ? 2 : 1))
                        .overlay { if cursor == step { Color.white.opacity(0.12).clipShape(RoundedRectangle(cornerRadius: 7)) } }
                        .frame(width: 32, height: 44)
                }.disabled(playing)
                    .accessibilityLabel("\(EchoStyle.names[lane])，第 \(step + 1) 格")
                    .accessibilityValue(selected ? "已添加" : "空")
            }
        }
    }
}
