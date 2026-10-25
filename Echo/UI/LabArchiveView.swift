import SwiftUI
import Charts
import UniformTypeIdentifiers

struct LabJSONDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }
    let data: Data
    init(data: Data) { self.data = data }
    init(configuration: ReadConfiguration) throws { throw CocoaError(.fileReadUnsupportedScheme) }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper { FileWrapper(regularFileWithContents: data) }
}

struct LabConsentView: View {
    @Environment(\.dismiss) private var dismiss
    let exporting: Bool
    let recording: SNNLabRecording
    let completed: (RhythmState?, String) throws -> Void
    @State private var label: RhythmState?
    @State private var note = ""
    @State private var error: String?
    var body: some View {
        NavigationStack {
            Form {
                Section(exporting ? "确认导出这段演奏" : "确认保存到本机档案") {
                    Text(recording.pattern.title)
                    Text("包含原始点击时间、谱面、玩法、速度、规则测量，以及本次正式模型的预测（如有）。不含姓名或设备标识。")
                        .font(.subheadline).foregroundStyle(.secondary)
                    Text(exporting ? "导出不会同时保存到档案。选择文件位置后，文件由你管理；分享后他人能看到其中的数据。" :
                            "只有点击下方确认按钮才会保存。与游戏成绩分开；可在实验档案中删除或导出。")
                        .font(.caption).foregroundStyle(EchoStyle.colors[2])
                }
                Section("人工标注（可选，独立于模型预测）") {
                    LabLabelPicker(label: $label)
                    TextField("备注（最多 200 字）", text: $note, axis: .vertical).lineLimit(2...4)
                        .onChange(of: note) { _, value in note = String(value.prefix(200)) }
                    Text("默认不标注，不自动抄用 SNN 或 ANN 的结论。人工标签也不自动作为训练真值使用。")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Button(exporting ? "确认并选择导出位置" : "确认保存到本机") {
                    do { try completed(label, note); dismiss() } catch { self.error = error.localizedDescription }
                }.accessibilityIdentifier("labConfirmConsent")
                if let error { Text(error).font(.caption).foregroundStyle(.red) }
            }.scrollContentBackground(.hidden).echoBackground().navigationTitle(exporting ? "导出确认" : "保存确认")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } } }
        }
    }
}

struct LabLabelPicker: View {
    @Binding var label: RhythmState?
    var body: some View {
        Picker("我的人工标注", selection: $label) {
            Text("未标注").tag(Optional<RhythmState>.none)
            ForEach(RhythmState.allCases) { Text($0.title).tag(Optional($0)) }
        }.accessibilityIdentifier("labManualLabel")
    }
}

struct LabArchiveView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var store: RhythmLabStore
    let open: (SNNLabRecording) -> Void
    @State private var selectedGroup = ""
    @State private var deleting: LabArchiveEntry?
    @State private var deletingAll = false
    @State private var annotation: LabArchiveEntry?
    @State private var exportConfirmation = false
    @State private var document: LabJSONDocument?
    @State private var exporting = false
    @State private var message: String?
    @State private var selectedIndex: Int?
    private var groups: [LabArchiveEntry] {
        var seen = Set<String>()
        return store.state.entries.filter { $0.measurement != nil && seen.insert($0.recording.groupKey).inserted }
    }
    private var group: String { groups.contains { $0.recording.groupKey == selectedGroup } ? selectedGroup : (groups.first?.recording.groupKey ?? "") }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("只记录你主动留下的回声。") .font(.system(.title2, design: .rounded, weight: .bold))
                        Text("\(store.state.entries.count) / 200 条 · 本机独立档案").font(.caption).foregroundStyle(EchoStyle.accent).accessibilityIdentifier("labArchiveCount")
                        Text("不自动采集，不混入模拟样本。进步趋势只比较同谱面、同玩法、同速度的完整演奏。")
                            .font(.caption).foregroundStyle(EchoStyle.secondary)
                    }.echoPanel()
                    if let latest = store.state.entries.first { latestPanel(latest) }
                    if !groups.isEmpty { trendPanel }
                    if store.state.entries.isEmpty {
                        ContentUnavailableView("还没有实验档案", systemImage: "waveform.path", description: Text("演奏后主动选择“保存到本机档案”。只浏览或试玩不会自动生成记录。"))
                            .accessibilityIdentifier("labArchiveEmpty")
                    }
                    ForEach(store.state.entries) { entry in entryCard(entry) }
                    if !store.state.entries.isEmpty {
                        Button { exportConfirmation = true } label: { Label("导出全部档案", systemImage: "square.and.arrow.up") }
                            .buttonStyle(EchoButtonStyle(secondary: true)).accessibilityIdentifier("labExportAll")
                        Button("删除全部实验档案", role: .destructive) { deletingAll = true }.font(.subheadline).padding(.vertical, 10)
                    }
                    if let message { Text(message).font(.caption).foregroundStyle(EchoStyle.colors[2]) }
                    if let error = store.errorMessage { Text(error).font(.caption).foregroundStyle(EchoStyle.colors[2]) }
                }.padding(22).frame(maxWidth: 780).frame(maxWidth: .infinity)
            }.echoBackground().navigationTitle("节奏能力档案").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("完成") { dismiss() } } }
        }
        .confirmationDialog("删除这份实验记录？", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }), titleVisibility: .visible) {
            Button("删除这份记录", role: .destructive) { if let entry = deleting { perform { try store.remove(id: entry.id) } }; deleting = nil }
        } message: { Text("仅删除实验档案，不改变关卡成绩。删除无法撤销，已导出的副本不受影响。") }
        .alert("删除全部实验档案？", isPresented: $deletingAll) {
            Button("取消", role: .cancel) { }
            Button("删除全部", role: .destructive) { perform { try store.removeAll() } }
        } message: { Text("仅清空这 \(store.state.entries.count) 条实验记录，不删除游戏存档。无法撤销，建议先导出。") }
        .confirmationDialog("确认导出全部 \(store.state.entries.count) 条？", isPresented: $exportConfirmation, titleVisibility: .visible) {
            Button("确认并选择位置") {
                perform { document = LabJSONDocument(data: try LabExportEnvelope(entries: store.state.entries).encoded()); exporting = true }
            }
        } message: { Text("包含原始点击和备注。人工标签与模型预测保持分开；文件不会自动上传。") }
        .fileExporter(isPresented: $exporting, document: document, contentType: .json, defaultFilename: "Echo-实验档案") { result in
            if case .failure(let error) = result { message = "导出未完成：" + error.localizedDescription }
        }
        .sheet(item: $annotation) { entry in LabAnnotationView(entry: entry, store: store) }
    }

    private var trendPanel: some View {
        let trend = LabTrend(entries: store.state.entries, groupKey: group)
        return VStack(alignment: .leading, spacing: 15) {
            SectionTitle(title: "原始节奏测量", caption: "最近 \(trend.entries.count) 次")
            groupPicker
            LabTrendPlot(entries: trend.entries, selection: $selectedIndex).frame(height: 190)
            if !trend.entries.isEmpty {
                let index = min(trend.entries.count - 1, max(0, selectedIndex ?? trend.entries.count - 1))
                let selected = trend.entries[index]
                HStack {
                    VStack(alignment: .leading, spacing: 5) {
                        Text("第 \(index + 1) 次 · " + selected.recording.capturedAt.formatted(.dateTime.month().day().hour().minute()))
                            .font(.caption).foregroundStyle(EchoStyle.secondary)
                        Text(String(format: "绝对间隔偏差 %.1f%%", (selected.measurement?.meanAbsolute ?? 0) * 100))
                            .font(.subheadline.monospacedDigit()).foregroundStyle(EchoStyle.accent)
                    }
                    Spacer()
                    Button("回放 / 重练") { open(selected.recording); dismiss() }
                        .font(.caption.weight(.semibold)).padding(.vertical, 10)
                }
                HStack {
                    Button { selectedIndex = max(0, index - 1) } label: { Image(systemName: "chevron.left") }
                        .accessibilityLabel("上一次演奏").disabled(index == 0)
                    Spacer()
                    Text("点选或拖动图表查看记录").font(.caption2).foregroundStyle(EchoStyle.secondary)
                    Spacer()
                    Button { selectedIndex = min(trend.entries.count - 1, index + 1) } label: { Image(systemName: "chevron.right") }
                        .accessibilityLabel("下一次演奏").disabled(index == trend.entries.count - 1)
                }.buttonStyle(.bordered)
            }
            Text("纵向：平均绝对间隔偏差（越低越接近标准）；横向：保存的演奏先后。不同条件不会连成一条趋势。")
                .font(.caption2).foregroundStyle(EchoStyle.secondary)
            Text(trendDescription(trend)).font(.caption).foregroundStyle(EchoStyle.accent)
        }.echoPanel().onChange(of: group) { _, _ in selectedIndex = nil }
    }
    private func latestPanel(_ entry: LabArchiveEntry) -> some View {
        VStack(alignment: .leading, spacing: 15) {
            SectionTitle(title: "最近留下的回声", caption: "原始测量")
            Text(entry.recording.pattern.title).font(.headline)
            Text(groupTitle(entry)).font(.caption).foregroundStyle(EchoStyle.secondary)
            if let value = entry.measurement {
                HStack {
                    MetricView(value: String(format: "%.1f%%", value.meanAbsolute * 100), title: "绝对间隔偏差")
                    MetricView(value: String(format: "%.1f%%", value.spread * 100), title: "波动程度")
                }
            } else {
                Text("这次顺序尚不完整，先修复音符，再比较节奏。")
                    .font(.subheadline).foregroundStyle(EchoStyle.colors[2])
            }
            Button { open(entry.recording); dismiss() } label: {
                Label("听听这次 / 再练一轮", systemImage: "play.circle")
            }.buttonStyle(EchoButtonStyle(secondary: true))
        }.echoPanel()
    }
    private var groupPicker: some View {
        Picker("比较条件", selection: Binding<String>(get: { group }, set: { selectedGroup = $0 })) {
            ForEach(groups) { entry in Text(groupTitle(entry)).tag(entry.recording.groupKey) }
        }.tint(EchoStyle.accent)
    }
    private func groupTitle(_ entry: LabArchiveEntry) -> String {
        "\(entry.recording.pattern.title) · \(entry.recording.mode.title) · \(Int(entry.recording.speed * 100))%"
    }
    private func trendDescription(_ trend: LabTrend) -> String {
        guard let change = trend.change else { return "同条件至少保存 6 次，才比较最早三次与最近三次；单次结果不代表能力变化。" }
        if abs(change) < 0.005 { return "最近与较早三次相比，变化不明显。" }
        let direction = change < 0 ? "减少" : "增加"
        return String(format: "最近三次比最早三次，平均绝对偏差%@ %.1f 个百分点。", direction, abs(change) * 100)
    }
    private func entryCard(_ entry: LabArchiveEntry) -> some View {
        let modeText = "\(entry.recording.mode.title) · \(Int(entry.recording.speed * 100))% · \(entry.recording.taps.count) 次点击"
        let snnText = entry.model?.snn?.title ?? "未分析或不确定"
        let annText = entry.model?.ann?.title ?? "未分析或不确定"
        let manualText = entry.manualLabel?.title ?? "未标注"
        return VStack(alignment: .leading, spacing: 13) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(entry.recording.pattern.title).font(.headline)
                    Text(entry.recording.capturedAt, format: .dateTime.month().day().hour().minute()).font(.caption2).foregroundStyle(EchoStyle.secondary)
                }
                Spacer()
                Menu {
                    Button("编辑人工标注") { annotation = entry }
                    Button("删除记录", role: .destructive) { deleting = entry }
                } label: { Image(systemName: "ellipsis").padding(10) }.accessibilityLabel("记录操作")
            }
            Text(modeText)
                .font(.caption).foregroundStyle(EchoStyle.secondary)
            if let measured = entry.measurement {
                Text(String(format: "规则测量：绝对间隔偏差 %.1f%% · 波动 %.1f%%", measured.meanAbsolute * 100, measured.spread * 100))
                    .font(.caption.monospacedDigit()).foregroundStyle(EchoStyle.accent)
            } else { Text("顺序不完整：不纳入间隔趋势。") .font(.caption).foregroundStyle(EchoStyle.colors[2]) }
            DisclosureGroup("模型意见与人工备注") {
            VStack(alignment: .leading, spacing: 8) {
            Text("SNN 意见：\(snnText) / ANN：\(annText)")
                .font(.caption).foregroundStyle(EchoStyle.secondary)
            Text("人工标注：\(manualText)").font(.caption).foregroundStyle(EchoStyle.colors[2])
            if !entry.note.isEmpty { Text(entry.note).font(.caption).foregroundStyle(EchoStyle.secondary) }
            }.frame(maxWidth: .infinity, alignment: .leading).padding(.top, 8)
            }.font(.caption).tint(EchoStyle.secondary)
            Button("打开这段演奏") { open(entry.recording); dismiss() }
                .font(.subheadline).foregroundStyle(EchoStyle.accent).padding(.vertical, 5)
        }.echoPanel().accessibilityIdentifier("labArchiveEntry")
    }
    private func perform(_ action: () throws -> Void) { do { try action() } catch { message = error.localizedDescription } }
}

private struct LabAnnotationView: View {
    @Environment(\.dismiss) private var dismiss
    let entry: LabArchiveEntry
    @ObservedObject var store: RhythmLabStore
    @State private var label: RhythmState?
    @State private var note: String
    @State private var error: String?
    init(entry: LabArchiveEntry, store: RhythmLabStore) {
        self.entry = entry; self.store = store
        _label = State(initialValue: entry.manualLabel); _note = State(initialValue: entry.note)
    }
    var body: some View {
        NavigationStack {
            Form {
                LabLabelPicker(label: $label)
                TextField("备注（最多 200 字）", text: $note, axis: .vertical).onChange(of: note) { _, value in note = String(value.prefix(200)) }
                Text("只修改人工标注和备注，不改写原始点击或当时的模型预测。") .font(.caption).foregroundStyle(.secondary)
                if let error { Text(error).foregroundStyle(.red) }
            }.navigationTitle("编辑人工标注").navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                    ToolbarItem(placement: .confirmationAction) { Button("保存") {
                        do { try store.annotate(id: entry.id, label: label, note: note); dismiss() } catch { self.error = error.localizedDescription }
                    } }
                }
        }
    }
}

private struct LabTrendPlot: View {
    let entries: [LabArchiveEntry]
    @Binding var selection: Int?
    private var maximum: Double { max(10, ceil((entries.compactMap { $0.measurement?.meanAbsolute }.max() ?? 0.1) * 100 / 5) * 5) }
    var body: some View {
        Chart {
            ForEach(Array(entries.enumerated()), id: \.element.id) { index, entry in
                let value = (entry.measurement?.meanAbsolute ?? 0) * 100
                AreaMark(x: .value("演奏", index), y: .value("偏差", value))
                    .foregroundStyle(LinearGradient(colors: [EchoStyle.accent.opacity(0.2), .clear], startPoint: .top, endPoint: .bottom))
                LineMark(x: .value("演奏", index), y: .value("偏差", value)).foregroundStyle(EchoStyle.accent)
                PointMark(x: .value("演奏", index), y: .value("偏差", value))
                    .symbolSize(index == (selection ?? entries.count - 1) ? 65 : 25)
                    .foregroundStyle(EchoStyle.accent)
                    .accessibilityLabel("第 \(index + 1) 次演奏")
                    .accessibilityValue(String(format: "绝对间隔偏差 %.1f%%", value))
            }
            if let selection, entries.indices.contains(selection) {
                RuleMark(x: .value("选中演奏", selection)).foregroundStyle(.white.opacity(0.3))
            }
        }.chartYScale(domain: 0...maximum).chartXScale(domain: -0.3...Double(max(1, entries.count - 1)) + 0.3)
            .chartYAxis { AxisMarks(position: .leading, values: .automatic(desiredCount: 4)) { value in
                AxisGridLine().foregroundStyle(.white.opacity(0.08))
                AxisValueLabel { if let number = value.as(Double.self) { Text(String(format: "%.0f%%", number)) } }
            } }
            .chartXAxis { AxisMarks(values: Array(entries.indices.filter { $0 == 0 || $0 == entries.count - 1 || $0 % 5 == 4 })) { value in
                AxisValueLabel { if let index = value.as(Int.self) { Text("\(index + 1)") } }
            } }
            .chartXSelection(value: $selection).padding(12)
            .background(.black.opacity(0.15), in: RoundedRectangle(cornerRadius: 12))
    }
}
