import SwiftUI

struct ChallengeView: View {
    var openStudio: () -> Void = {}
    @EnvironmentObject private var library: EchoLibrary
    @State private var game: GameRequest?
    @State private var showTutorial = false
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 26) {
                NightSessionHero(pattern: library.nextLevel, completed: library.completed) {
                    game = GameRequest(pattern: library.nextLevel)
                }

                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 3), spacing: 10) {
                    NavigationLink { LevelDetailView(pattern: LevelCatalog.daily(), allowStandard: true) } label: {
                        quickEntry("今日回声", subtitle: "每天一段", icon: "sun.horizon", color: EchoStyle.colors[2])
                    }.buttonStyle(.plain).accessibilityIdentifier("dailyChallenge")
                    Button(action: openStudio) {
                        quickEntry("自由演奏", subtitle: "随手敲灵感", icon: "pianokeys", color: EchoStyle.accent)
                    }.buttonStyle(.plain).accessibilityIdentifier("homeStudio")
                    NavigationLink { SNNLabView() } label: {
                        quickEntry("节奏实验室", subtitle: "听见并练习", icon: "waveform.path.ecg", color: EchoStyle.colors[1])
                    }.buttonStyle(.plain).accessibilityIdentifier("homeLab")
                }
                CityMapView()
                HStack(spacing: 12) {
                    NavigationLink { ChainChallengeView() } label: {
                        smallCard("节奏接龙", subtitle: "每次多记住一个音符", icon: "arrow.triangle.2.circlepath", color: EchoStyle.accent, asset: "Hub-Wave")
                    }.buttonStyle(.plain).accessibilityIdentifier("chainMode")
                    NavigationLink { DuoChallengeView() } label: {
                        smallCard("双人回声", subtitle: "你来出题，我来回应", icon: "person.2.fill", color: EchoStyle.colors[3], asset: "Hub-Studio")
                    }.buttonStyle(.plain).accessibilityIdentifier("duoMode")
                }
                Button { showTutorial = true } label: {
                    HStack { Label("初次聆听 · 一分钟掌握玩法", systemImage: "ear.badge.waveform"); Spacer(); Image(systemName: "arrow.up.right") }
                        .font(.caption).foregroundStyle(EchoStyle.secondary).padding(.vertical, 8)
                }.accessibilityIdentifier("openTutorial")
                SectionTitle(title: "声音地图", caption: "4 个章节 · 24 段回声")
                ForEach(0..<4) { chapter in
                    NavigationLink { ChapterView(chapter: chapter) } label: {
                        HStack(spacing: 17) {
                            Image("Scene-\(chapter)").resizable().scaledToFill().frame(width: 55, height: 65)
                                .overlay(EchoStyle.colors[chapter].opacity(0.1)).clipShape(RoundedRectangle(cornerRadius: 12))
                                .accessibilityHidden(true)
                            VStack(alignment: .leading, spacing: 7) {
                                Text(String(format: "%02d  ", chapter + 1) + LevelCatalog.chapters[chapter]).font(.headline)
                                Text(LevelCatalog.subtitles[chapter]).font(.caption).foregroundStyle(EchoStyle.secondary)
                            }
                            Spacer()
                            let count = LevelCatalog.levels.filter { $0.chapter == chapter && library.stars($0.id) > 0 }.count
                            VStack(spacing: 8) { Text("\(count)/6").font(.caption.monospacedDigit()); Image(systemName: "chevron.right").font(.caption2) }.foregroundStyle(EchoStyle.secondary)
                        }.echoPanel()
                    }.buttonStyle(.plain).accessibilityIdentifier("chapter-\(chapter)")
                }
                Text("先聆听，再回应。无需联网，也不必懂乐理。")
                    .font(.footnote).foregroundStyle(EchoStyle.secondary).frame(maxWidth: .infinity).padding(.bottom, 10)
            }.padding(22).frame(maxWidth: 760).frame(maxWidth: .infinity)
        }.accessibilityHidden(game != nil || showTutorial)
            .environment(\.echoArtworkActive, game == nil && !showTutorial)
            .echoBackground().navigationTitle("回声").toolbar(.hidden, for: .navigationBar)
            .fullScreenCover(item: $game) { GameView(request: $0) }
            .sheet(isPresented: $showTutorial) { TutorialView() }
            .onAppear { EchoAudio.shared.prepare(palette: library.state.settings.palette); if !library.state.tutorialSeen { showTutorial = true } }
    }
    private func quickEntry(_ title: String, subtitle: String, icon: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            Image(systemName: icon).font(.title3).foregroundStyle(color)
            Text(title).font(.caption.weight(.semibold)).foregroundStyle(.white)
            Text(subtitle).font(.system(size: 10)).foregroundStyle(EchoStyle.secondary)
        }.frame(maxWidth: .infinity, minHeight: 92, alignment: .leading).padding(12)
            .background(color.opacity(0.07), in: RoundedRectangle(cornerRadius: 18))
            .overlay(RoundedRectangle(cornerRadius: 18).stroke(color.opacity(0.17)))
    }
    private func smallCard(_ title: String, subtitle: String, icon: String, color: Color, asset: String) -> some View {
        VStack(alignment: .leading, spacing: 11) {
            Image(systemName: icon).font(.system(size: 19)).foregroundStyle(color)
                .frame(width: 35, height: 35).background(.black.opacity(0.2), in: RoundedRectangle(cornerRadius: 10))
            Text(title).font(.headline)
            Text(subtitle).font(.caption2).foregroundStyle(EchoStyle.secondary).lineLimit(2).frame(minHeight: 28, alignment: .top)
        }.padding(20).frame(maxWidth: .infinity, minHeight: 151, alignment: .leading)
            .background { ScenicBackdrop(asset: asset, tint: color) }
            .clipShape(RoundedRectangle(cornerRadius: 22))
            .contentShape(RoundedRectangle(cornerRadius: 22))
            .overlay(RoundedRectangle(cornerRadius: 22).stroke(color.opacity(0.18), lineWidth: 1))
    }
}

struct ChapterView: View {
    let chapter: Int
    @EnvironmentObject private var library: EchoLibrary
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                ChapterArtwork(chapter: chapter).frame(height: 210).clipShape(RoundedRectangle(cornerRadius: 24))
                Text(LevelCatalog.subtitles[chapter]).font(.title2.bold())
                Text("按顺序完成标准回声，逐步点亮地图。未解锁的关卡也可以慢速练习。")
                    .font(.subheadline).foregroundStyle(EchoStyle.secondary)
                ForEach(Array(LevelCatalog.levels.enumerated()).filter { $0.element.chapter == chapter }, id: \.element.id) { index, pattern in
                    NavigationLink { LevelDetailView(pattern: pattern, allowStandard: library.unlocked(index)) } label: {
                        HStack(spacing: 16) {
                            Text(String(format: "%02d", index % 6 + 1)).font(.system(.title2, design: .rounded, weight: .bold)).foregroundStyle(EchoStyle.colors[chapter]).frame(width: 35)
                            VStack(alignment: .leading, spacing: 10) {
                                Text(pattern.title).font(.headline)
                                PatternDots(pattern: pattern)
                            }
                            Spacer()
                            if library.unlocked(index) {
                                HStack(spacing: 2) { ForEach(0..<3) { star in Image(systemName: star < library.stars(pattern.id) ? "star.fill" : "star").font(.caption2) } }.foregroundStyle(EchoStyle.colors[2])
                            } else { Image(systemName: "lock.fill").foregroundStyle(EchoStyle.secondary) }
                        }.echoPanel()
                    }.buttonStyle(.plain).accessibilityIdentifier("level-\(pattern.id)")
                }
            }.padding(22).frame(maxWidth: 760).frame(maxWidth: .infinity)
        }.echoBackground().navigationTitle(LevelCatalog.chapters[chapter]).navigationBarTitleDisplayMode(.inline)
    }
}

struct LevelDetailView: View {
    var pattern: RhythmPattern
    var allowStandard: Bool
    @EnvironmentObject private var library: EchoLibrary
    @State private var mode: PlayMode = .echo
    @State private var game: GameRequest?
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                ChapterArtwork(chapter: pattern.chapter).frame(height: 175).clipShape(RoundedRectangle(cornerRadius: 24))
                Text(pattern.title).font(.system(.largeTitle, design: .rounded, weight: .bold))
                Text(pattern.detail).foregroundStyle(EchoStyle.secondary)
                HStack { MetricView(value: "\(Int(pattern.bpm))", title: "BPM"); MetricView(value: "\(pattern.notes.count)", title: "音符"); MetricView(value: library.best(pattern.id, mode: mode).map { String($0.score) } ?? "—", title: "标准最佳") }.echoPanel()
                SectionTitle(title: "选择玩法")
                ForEach(PlayMode.allCases) { item in
                    Button { mode = item } label: {
                        HStack(spacing: 15) {
                            Image(systemName: item.symbol).foregroundStyle(EchoStyle.accent).frame(width: 28)
                            VStack(alignment: .leading, spacing: 6) { Text(item.title).font(.headline); Text(item.explanation).font(.caption).foregroundStyle(EchoStyle.secondary).multilineTextAlignment(.leading) }
                            Spacer(minLength: 0)
                            Image(systemName: mode == item ? "checkmark.circle.fill" : "circle").foregroundStyle(mode == item ? EchoStyle.accent : EchoStyle.secondary)
                        }.echoPanel()
                    }.buttonStyle(.plain).accessibilityIdentifier("mode-\(item.rawValue)")
                }
                if !allowStandard { Label("完成上一关的标准回声后解锁；现在可以先练习。", systemImage: "lock").font(.footnote).foregroundStyle(EchoStyle.colors[2]) }
                Button { game = GameRequest(pattern: pattern, mode: mode) } label: { Text("开始标准挑战") }
                    .buttonStyle(EchoButtonStyle()).disabled(!allowStandard).opacity(allowStandard ? 1 : 0.4)
                Button { game = GameRequest(pattern: pattern, mode: mode, speed: 0.75) } label: { Text("慢速练习 · 75%") }.buttonStyle(EchoButtonStyle(secondary: true))
                Text("练习与重听成绩单独记录，不用于章节解锁。只有标准回声通关会点亮地图。")
                    .font(.footnote).foregroundStyle(EchoStyle.secondary)
            }.padding(24).frame(maxWidth: 720).frame(maxWidth: .infinity)
        }.accessibilityHidden(game != nil).environment(\.echoArtworkActive, game == nil)
            .echoBackground().navigationBarTitleDisplayMode(.inline).fullScreenCover(item: $game) { GameView(request: $0) }
    }
}

