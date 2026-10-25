import SwiftUI

struct CityMapView: View {
    @EnvironmentObject private var library: EchoLibrary
    @Environment(\.echoReducedMotion) private var reduceMotion
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                VStack(alignment: .leading, spacing: 5) {
                    Text("一座正在醒来的城").font(.headline)
                    Text("每扇亮起的窗，都是你找回的回声。")
                        .font(.caption).foregroundStyle(EchoStyle.secondary)
                }
                Spacer(minLength: 4)
                Text("\(library.completed)/24").font(.caption.monospacedDigit()).foregroundStyle(EchoStyle.accent)
            }
            HStack(alignment: .bottom, spacing: 10) {
                ForEach(0..<4) { chapter in
                    NavigationLink { ChapterView(chapter: chapter) } label: {
                        district(chapter)
                    }.buttonStyle(.plain).accessibilityIdentifier("city-chapter-\(chapter)")
                        .accessibilityLabel("\(LevelCatalog.chapters[chapter])，已点亮 \(count(chapter)) 扇窗，共 6 扇。查看章节")
                }
            }.frame(height: 158, alignment: .bottom)
                .padding(.horizontal, 14).padding(.top, 12).padding(.bottom, 10)
                .background {
                    ChapterArtwork(chapter: library.nextLevel.chapter, showCaption: false, photographic: false).opacity(0.45)
                }.clipShape(RoundedRectangle(cornerRadius: 15))
                .background(alignment: .bottom) {
                    Ellipse().fill(EchoStyle.accent.opacity(0.08 + Double(library.completed) / 180))
                        .frame(height: 28).blur(radius: 8)
                }
                .animation(reduceMotion ? nil : .easeInOut(duration: 0.5), value: library.completed)
            Button {
                EchoAudio.shared.celebrate(chapter: library.nextLevel.chapter, settings: library.state.settings)
            } label: { Label("听听城市的短旋律", systemImage: "speaker.wave.2") }
                .font(.caption.weight(.medium)).foregroundStyle(EchoStyle.accent)
                .disabled(!library.state.settings.sound)
        }.echoPanel()
            .onDisappear { EchoAudio.shared.stopSequence() }
    }
    private func count(_ chapter: Int) -> Int {
        LevelCatalog.levels.filter { $0.chapter == chapter && library.stars($0.id) > 0 }.count
    }
    private func district(_ chapter: Int) -> some View {
        let color = EchoStyle.colors[chapter]
        let levels = LevelCatalog.levels.filter { $0.chapter == chapter }
        return VStack(spacing: 8) {
            GeometryReader { geometry in
                ZStack(alignment: .bottomTrailing) {
                    Image("Scene-\(chapter)").resizable().scaledToFill()
                        .frame(width: geometry.size.width, height: geometry.size.height).clipped()
                        .saturation(count(chapter) > 0 ? 0.8 : 0.35)
                    LinearGradient(colors: [.clear, .black.opacity(0.55)], startPoint: .top, endPoint: .bottom)
                    Image(systemName: LevelCatalog.symbols[chapter]).font(.system(size: 14)).foregroundStyle(color).padding(6)
                }.clipShape(RoundedRectangle(cornerRadius: 7))
            }.frame(height: chapter == 1 ? 53 : 44).allowsHitTesting(false)
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 5), GridItem(.flexible(), spacing: 5)], spacing: 6) {
                ForEach(levels) { level in
                    RoundedRectangle(cornerRadius: 3)
                        .fill(library.stars(level.id) > 0 ? color : Color.white.opacity(0.07))
                        .frame(height: 10)
                        .background {
                            if library.stars(level.id) > 0 {
                                MaskedLight(asset: "Mask-Window", color: color).padding(-5).opacity(0.6)
                            }
                        }
                        .overlay(RoundedRectangle(cornerRadius: 3).stroke(color.opacity(0.15), lineWidth: 1))
                        .shadow(color: library.stars(level.id) > 0 ? color.opacity(0.5) : .clear, radius: 5)
                }
            }.padding(.horizontal, 3)
            Text(LevelCatalog.chapters[chapter]).font(.system(size: 10, weight: .medium)).lineLimit(1).minimumScaleFactor(0.7)
                .foregroundStyle(count(chapter) > 0 ? color : EchoStyle.secondary)
            Text("\(count(chapter)) / 6").font(.system(size: 9, weight: .medium, design: .monospaced)).foregroundStyle(color.opacity(0.8))
        }.padding(8).frame(maxWidth: .infinity).contentShape(Rectangle())
            .background(.white.opacity(0.035), in: UnevenRoundedRectangle(topLeadingRadius: chapter == 0 ? 18 : 4, topTrailingRadius: chapter == 3 ? 18 : 4))
            .overlay(alignment: .top) { Rectangle().fill(color.opacity(count(chapter) > 0 ? 0.7 : 0.15)).frame(height: 2) }
    }
}
