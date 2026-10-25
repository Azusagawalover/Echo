import SwiftUI

struct MaterialTexture: View {
    var asset: String
    var body: some View {
        GeometryReader { geometry in
            Image(decorative: asset).resizable().scaledToFill()
                .frame(width: geometry.size.width, height: geometry.size.height).clipped()
        }.allowsHitTesting(false).accessibilityHidden(true)
    }
}

struct MaskedLight: View {
    var asset = "Mask-Halo"
    var color = EchoStyle.accent
    var body: some View {
        GeometryReader { geometry in
            Image(asset).resizable().renderingMode(.template).foregroundStyle(color)
                .scaledToFill().frame(width: geometry.size.width, height: geometry.size.height).clipped()
        }.allowsHitTesting(false).accessibilityHidden(true)
    }
}

struct NightSessionHero: View {
    let pattern: RhythmPattern
    let completed: Int
    var start: () -> Void
    @Environment(\.verticalSizeClass) private var verticalSize
    private var compactLandscape: Bool { verticalSize == .compact }
    private var color: Color { EchoStyle.colors[min(3, max(0, pattern.chapter))] }
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if compactLandscape {
                HStack {
                    Text("ECHO / 回声").font(.system(size: 10, weight: .bold)).tracking(2).foregroundStyle(color)
                    Spacer()
                    Text("让城市，重新有声音。").font(.system(.subheadline, design: .rounded, weight: .semibold))
                }
            } else {
              HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("ECHO  /  回声").font(.system(size: 10, weight: .bold)).tracking(3).foregroundStyle(color)
                    Text("今晚，也有新的回声。")
                        .font(.system(.title3, design: .rounded, weight: .bold))
                }
                Spacer(minLength: 6)
                VStack(spacing: 6) {
                    Image(systemName: LevelCatalog.symbols[min(3, max(0, pattern.chapter))]).font(.title3)
                    Text(String(format: "%02d / 04", pattern.chapter + 1)).font(.system(size: 9, design: .monospaced))
                }.foregroundStyle(color).padding(12)
                    .background(.black.opacity(0.28), in: RoundedRectangle(cornerRadius: 16))
              }
            }
            HStack(alignment: .center, spacing: 18) {
                VStack(alignment: .leading, spacing: compactLandscape ? 6 : 9) {
                    Label("继续声音之旅", systemImage: "waveform").font(.caption2.weight(.medium)).foregroundStyle(.white.opacity(0.8))
                    Text(pattern.title).font(.system(.title2, design: .rounded, weight: .semibold)).lineLimit(2)
                    HStack(spacing: 8) {
                        Text("\(Int(pattern.bpm)) BPM").monospacedDigit()
                        Circle().fill(color).frame(width: 3, height: 3)
                        Text("\(pattern.notes.count) 个音符")
                    }.font(.caption2).foregroundStyle(.white.opacity(0.8))
                }
                Spacer(minLength: 0)
                RecordSleeve(chapter: pattern.chapter).frame(width: 58, height: 58)
            }
            VStack(spacing: 11) {
                HStack {
                    Text(LevelCatalog.chapters[min(3, max(0, pattern.chapter))] + " · 声音旅程")
                    Spacer()
                    Text("\(completed) / 24").monospacedDigit()
                }.font(.system(size: 10, weight: .medium)).foregroundStyle(.white.opacity(0.75))
                ProgressView(value: Double(completed), total: 24).tint(color)
                Button(action: start) {
                    HStack { Text(completed == 24 ? "再次聆听" : completed == 0 ? "开始挑战" : "继续挑战"); Spacer(); Image(systemName: "arrow.right") }
                }.buttonStyle(EchoButtonStyle()).accessibilityIdentifier("startChallenge")
            }
        }.padding(20).frame(maxWidth: .infinity, alignment: .leading)
            .background {
                ChapterArtwork(chapter: pattern.chapter, showCaption: false)
                if pattern.chapter == 0 {
                    MaterialTexture(asset: "Atmosphere-Rain").opacity(0.28)
                        .mask(LinearGradient(colors: [.clear, .white], startPoint: .leading, endPoint: .trailing))
                }
                LinearGradient(stops: [.init(color: EchoStyle.background.opacity(0.08), location: 0),
                                       .init(color: EchoStyle.background.opacity(0.84), location: 0.54),
                                       .init(color: EchoStyle.background, location: 1)], startPoint: .top, endPoint: .bottom)
                LinearGradient(colors: [EchoStyle.background.opacity(0.5), .clear], startPoint: .leading, endPoint: .trailing)
                MaskedLight(asset: "Mask-Beam", color: color).opacity(0.13)
                    .mask(LinearGradient(colors: [.white, .clear], startPoint: .top, endPoint: .bottom))
            }
            .clipShape(RoundedRectangle(cornerRadius: 28))
            .overlay(RoundedRectangle(cornerRadius: 28).strokeBorder(LinearGradient(colors: [.white.opacity(0.25), color.opacity(0.12), .white.opacity(0.04)], startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 1))
            .shadow(color: color.opacity(0.07), radius: 24, y: 10)
    }
}

struct TicketOutline: Shape {
    func path(in rect: CGRect) -> Path {
        let r: CGFloat = 22, notch: CGFloat = 9, seam = max(r + notch, rect.height - 68)
        var path = Path()
        path.move(to: CGPoint(x: r, y: 0))
        path.addLine(to: CGPoint(x: rect.width - r, y: 0))
        path.addQuadCurve(to: CGPoint(x: rect.width, y: r), control: CGPoint(x: rect.width, y: 0))
        path.addLine(to: CGPoint(x: rect.width, y: seam - notch))
        path.addArc(center: CGPoint(x: rect.width, y: seam), radius: notch, startAngle: .degrees(-90), endAngle: .degrees(90), clockwise: true)
        path.addLine(to: CGPoint(x: rect.width, y: rect.height - r))
        path.addQuadCurve(to: CGPoint(x: rect.width - r, y: rect.height), control: CGPoint(x: rect.width, y: rect.height))
        path.addLine(to: CGPoint(x: r, y: rect.height))
        path.addQuadCurve(to: CGPoint(x: 0, y: rect.height - r), control: CGPoint(x: 0, y: rect.height))
        path.addLine(to: CGPoint(x: 0, y: seam + notch))
        path.addArc(center: CGPoint(x: 0, y: seam), radius: notch, startAngle: .degrees(90), endAngle: .degrees(270), clockwise: true)
        path.addLine(to: CGPoint(x: 0, y: r))
        path.addQuadCurve(to: CGPoint(x: r, y: 0), control: .zero)
        path.closeSubpath()
        return path
    }
}

struct EchoResultTicket: View {
    let result: RhythmResult
    let pattern: RhythmPattern
    let practice: Bool
    @State private var arrived = false
    @State private var issuedAt = Date()
    @Environment(\.echoReducedMotion) private var reduceMotion
    private let ink = Color(red: 0.12, green: 0.18, blue: 0.21)
    private let mutedInk = Color(red: 0.32, green: 0.38, blue: 0.4)
    private var color: Color { EchoStyle.colors[min(3, max(0, pattern.chapter))] }
    private var chapterLabel: String {
        pattern.id.hasPrefix("chapter-") ? LevelCatalog.chapters[min(3, max(0, pattern.chapter))] : pattern.id.hasPrefix("daily-") ? "每日回声" : "声音片段"
    }
    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 18) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 7) {
                        Text("ECHO / SOUND TICKET").font(.system(size: 9, weight: .bold, design: .monospaced)).tracking(1)
                        Text(practice ? "练习完成" : "挑战结果").font(.caption.weight(.medium)).foregroundStyle(mutedInk)
                    }
                    Spacer()
                    Text(practice ? "练习留念" : result.passed ? "回声已点亮" : "再靠近一点")
                        .font(.system(size: 10, weight: .semibold)).padding(.horizontal, 9).padding(.vertical, 7)
                        .overlay(Capsule().strokeBorder(ink.opacity(0.3), lineWidth: 1))
                }
                HStack(spacing: 14) {
                    Image("Scene-\(min(3, max(0, pattern.chapter)))").resizable().scaledToFill()
                        .frame(width: 48, height: 56).clipped().clipShape(RoundedRectangle(cornerRadius: 6))
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 5) {
                        Text(chapterLabel).font(.system(size: 10, weight: .medium)).foregroundStyle(mutedInk)
                        Text(pattern.title).font(.system(.title2, design: .rounded, weight: .bold)).lineLimit(2)
                    }
                    Spacer(minLength: 0)
                }
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text(result.grade).font(.system(size: 70, weight: .light, design: .rounded))
                    Text("\(result.score)").font(.system(size: 54, weight: .semibold, design: .rounded)).monospacedDigit()
                    Text("/ 100").font(.caption).foregroundStyle(mutedInk)
                    Spacer(minLength: 0)
                }.accessibilityElement(children: .combine).accessibilityIdentifier("resultScore")
                HStack {
                    HStack(spacing: 7) {
                        ForEach(0..<3) { index in
                            Image(systemName: index < result.stars ? "star.fill" : "star")
                                .font(.system(size: 17)).foregroundStyle(index < result.stars ? ink : mutedInk.opacity(0.5))
                        }
                    }.accessibilityElement(children: .ignore).accessibilityLabel("\(result.stars) 颗星")
                    Spacer()
                    Text(practice ? "不计入章节解锁" : "\(Int(pattern.bpm)) BPM · \(pattern.notes.count) 音符")
                        .font(.system(size: 10, design: .monospaced)).foregroundStyle(mutedInk)
                }
                Rectangle().fill(ink.opacity(0.13)).frame(height: 1)
                HStack(spacing: 6) {
                    ticketMetric("\(result.order)%", title: "顺序正确")
                    ticketMetric("\(result.timing)%", title: "节奏准确")
                    ticketMetric(result.judgements.contains(where: \.correctLane) ? "\(Int(result.meanError * 1000)) ms" : "—", title: "平均偏差")
                }
            }.padding(22)
            HStack(spacing: 14) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("把这一刻，留在回声里。 ").font(.system(size: 10, weight: .medium))
                    Text(issuedAt, format: .dateTime.year().month(.twoDigits).day(.twoDigits))
                        .font(.system(size: 9, design: .monospaced)).foregroundStyle(mutedInk)
                }
                Spacer(minLength: 0)
                TicketRhythm(notes: pattern.notes).frame(width: 86, height: 26)
            }.frame(height: 68).padding(.horizontal, 22)
        }.foregroundStyle(ink).frame(maxWidth: .infinity)
            .background {
                Color(red: 0.9, green: 0.91, blue: 0.86)
                MaterialTexture(asset: "Material-Paper").blendMode(.multiply).opacity(0.85)
                LinearGradient(colors: [color.opacity(0.12), .clear], startPoint: .topLeading, endPoint: .bottomTrailing)
            }
            .overlay(alignment: .bottom) {
                Path { path in path.move(to: CGPoint(x: 0, y: 0)); path.addLine(to: CGPoint(x: 1200, y: 0)) }
                    .stroke(ink.opacity(0.25), style: StrokeStyle(lineWidth: 1, dash: [3, 4]))
                    .frame(height: 1).padding(.horizontal, 14).padding(.bottom, 68).clipped()
                    .allowsHitTesting(false).accessibilityHidden(true)
            }
            .clipShape(TicketOutline())
            .shadow(color: .black.opacity(0.22), radius: 18, y: 12)
            .offset(y: reduceMotion || arrived ? 0 : 8).opacity(reduceMotion || arrived ? 1 : 0)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.38), value: arrived)
            .onAppear { arrived = true }
    }
    private func ticketMetric(_ value: String, title: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(value).font(.system(.headline, design: .rounded)).monospacedDigit().lineLimit(1).minimumScaleFactor(0.75)
            Text(title).font(.system(size: 10)).foregroundStyle(mutedInk)
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct TicketRhythm: View {
    let notes: [BeatNote]
    var body: some View {
        Canvas { context, size in
            let excerpt = Array(notes.prefix(16))
            let step = size.width / CGFloat(max(1, excerpt.count))
            for (i, note) in excerpt.enumerated() {
                let h = CGFloat(7 + note.lane * 5)
                let rect = CGRect(x: CGFloat(i) * step, y: (size.height - h) / 2, width: max(2, step - 3), height: h)
                context.fill(Path(roundedRect: rect, cornerRadius: 1), with: .color(Color(red: 0.12, green: 0.18, blue: 0.21).opacity(0.65)))
            }
        }.allowsHitTesting(false).accessibilityHidden(true)
    }
}

struct EchoBackdrop: View {
    var body: some View {
        ZStack {
            EchoStyle.background
            RadialGradient(colors: [EchoStyle.accent.opacity(0.07), .clear], center: .topLeading, startRadius: 5, endRadius: 580)
            RadialGradient(colors: [EchoStyle.colors[1].opacity(0.06), .clear], center: .bottomTrailing, startRadius: 0, endRadius: 480)
        }.contentShape(Rectangle()).allowsHitTesting(false).accessibilityHidden(true)
    }
}

struct ScenicBackdrop: View {
    var asset: String
    var tint = EchoStyle.accent
    var body: some View {
        GeometryReader { geometry in
            Image(asset).resizable().scaledToFill()
                .frame(width: geometry.size.width, height: geometry.size.height).clipped().saturation(0.65)
                .overlay(LinearGradient(colors: [EchoStyle.background.opacity(0.15), EchoStyle.background.opacity(0.88)], startPoint: .top, endPoint: .bottom))
                .overlay(LinearGradient(colors: [tint.opacity(0.1), .clear], startPoint: .topLeading, endPoint: .bottomTrailing))
        }.allowsHitTesting(false).accessibilityHidden(true)
    }
}

struct PhotoBanner: View {
    var eyebrow: String
    var title: String
    var asset: String
    var color = EchoStyle.accent
    var body: some View {
        VStack(alignment: .leading, spacing: 11) {
            Text(eyebrow).font(.caption2.weight(.bold)).tracking(3).foregroundStyle(color)
            Spacer(minLength: 8)
            Text(title).font(.system(size: 24, weight: .bold, design: .rounded))
        }.padding(22).frame(maxWidth: .infinity, minHeight: 132, maxHeight: 150, alignment: .leading)
            .background { ScenicBackdrop(asset: asset, tint: color) }
            .clipShape(RoundedRectangle(cornerRadius: 24))
            .overlay(RoundedRectangle(cornerRadius: 24).stroke(.white.opacity(0.1), lineWidth: 1))
    }
}

struct RecordSleeve: View {
    var chapter: Int
    private var index: Int { min(3, max(0, chapter)) }
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                Image("Scene-\(index)").resizable().scaledToFill()
                    .frame(width: geometry.size.width, height: geometry.size.height).clipped()
                LinearGradient(colors: [.clear, .black.opacity(0.6)], startPoint: .topLeading, endPoint: .bottomTrailing)
                Circle().stroke(.white.opacity(0.15), lineWidth: 1).padding(10)
                Circle().stroke(.white.opacity(0.12), lineWidth: 1).padding(17)
                Circle().fill(EchoStyle.background.opacity(0.85)).frame(width: 25, height: 25)
                    .overlay(Circle().stroke(EchoStyle.colors[index].opacity(0.8), lineWidth: 1))
                    .overlay(Circle().fill(EchoStyle.colors[index]).frame(width: 5, height: 5))
            }.clipShape(RoundedRectangle(cornerRadius: 15))
                .overlay(RoundedRectangle(cornerRadius: 15).stroke(.white.opacity(0.18), lineWidth: 1))
                .rotationEffect(.degrees(5))
                .shadow(color: EchoStyle.colors[index].opacity(0.12), radius: 12, y: 5)
        }.allowsHitTesting(false).accessibilityHidden(true)
    }
}

struct ChapterArtwork: View {
    var chapter: Int
    var showCaption = true
    var photographic = true
    private var index: Int { min(3, max(0, chapter)) }
    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .bottomLeading) {
                LinearGradient(colors: [Color(red: 0.035, green: 0.055, blue: 0.13), EchoStyle.colors[index].opacity(0.15), EchoStyle.background], startPoint: .top, endPoint: .bottom)
                if photographic {
                    Image("Scene-\(index)").resizable().scaledToFill()
                        .frame(width: proxy.size.width, height: proxy.size.height).clipped().saturation(0.75)
                    LinearGradient(colors: [.black.opacity(0.05), EchoStyle.background.opacity(showCaption ? 0.8 : 0.5)], startPoint: .top, endPoint: .bottom)
                    LinearGradient(colors: [EchoStyle.background.opacity(0.28), .clear], startPoint: .leading, endPoint: .trailing)
                }
                RadialGradient(colors: [EchoStyle.colors[index].opacity(0.18), .clear], center: UnitPoint(x: 0.7, y: 0.55), startRadius: 0, endRadius: proxy.size.width * 0.65)
                if !photographic { Canvas { context, size in
                    drawCity(&context, size: size)
                    drawScene(&context, size: size)
                } }
                AmbientParticles(chapter: index)
                if showCaption {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("S O U N D S C A P E  /  0\(index + 1)").font(.system(size: 9, weight: .semibold)).tracking(2)
                            .foregroundStyle(EchoStyle.colors[index])
                        Text(LevelCatalog.chapters[index]).font(.system(size: 27, weight: .bold, design: .rounded)).foregroundStyle(.white)
                    }.padding(22)
                }
            }.clipped()
        }.allowsHitTesting(false).accessibilityLabel(LevelCatalog.chapters[index] + "的夜景插画")
    }
    private func drawCity(_ context: inout GraphicsContext, size: CGSize) {
        let w = size.width, h = size.height
        for i in 0..<14 {
            let x = CGFloat(i) * w / 13 - 8
            let height = h * (0.12 + CGFloat((i * 13 + index * 7) % 9) / 55)
            let rect = CGRect(x: x, y: h * 0.83 - height, width: w / 12, height: height)
            context.fill(Path(rect), with: .color(Color(red: 0.045, green: 0.075, blue: 0.13)))
            for row in 0..<3 {
                for column in 0..<2 where (i + row + column) % 3 != 0 {
                    let window = CGRect(x: x + 6 + CGFloat(column) * 8, y: rect.minY + 9 + CGFloat(row) * 11, width: 3, height: 4)
                    context.fill(Path(window), with: .color(EchoStyle.colors[index].opacity(0.16 + Double((i + row) % 3) * 0.1)))
                }
            }
        }
        var horizon = Path(); horizon.move(to: CGPoint(x: 0, y: h * 0.83)); horizon.addLine(to: CGPoint(x: w, y: h * 0.83))
        context.stroke(horizon, with: .color(EchoStyle.colors[index].opacity(0.18)), lineWidth: 1)
    }
    private func drawScene(_ context: inout GraphicsContext, size: CGSize) {
        let w = size.width, h = size.height, color = EchoStyle.colors[index]
        switch index {
        case 0:
            for i in 0..<3 {
                let x = w * (0.54 + CGFloat(i) * 0.17), y = h * (0.36 + CGFloat(i % 2) * 0.15)
                var post = Path(); post.move(to: CGPoint(x: x, y: h * 0.87)); post.addLine(to: CGPoint(x: x, y: y)); post.addLine(to: CGPoint(x: x + 15, y: y))
                context.stroke(post, with: .color(color.opacity(0.5)), lineWidth: 2)
                context.fill(Path(ellipseIn: CGRect(x: x + 10, y: y - 2, width: 10, height: 4)), with: .color(Color(red: 1, green: 0.82, blue: 0.52)))
                context.stroke(Path(ellipseIn: CGRect(x: x - 18, y: h * 0.89 + CGFloat(i) * 3, width: 54, height: 5)), with: .color(color.opacity(0.18)), lineWidth: 1)
            }
        case 1:
            let tower = CGRect(x: w * 0.64, y: h * 0.24, width: w * 0.16, height: h * 0.59)
            context.fill(Path(tower), with: .color(Color(red: 0.11, green: 0.12, blue: 0.23)))
            var roof = Path(); roof.move(to: CGPoint(x: tower.minX - 8, y: tower.minY)); roof.addLine(to: CGPoint(x: tower.midX, y: h * 0.08)); roof.addLine(to: CGPoint(x: tower.maxX + 8, y: tower.minY)); roof.closeSubpath()
            context.fill(roof, with: .color(color.opacity(0.34)))
            let radius = min(w * 0.05, h * 0.1), center = CGPoint(x: tower.midX, y: h * 0.4)
            context.stroke(Path(ellipseIn: CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)), with: .color(color.opacity(0.85)), lineWidth: 1.5)
            var hands = Path(); hands.move(to: CGPoint(x: center.x, y: center.y - radius * 0.7)); hands.addLine(to: center); hands.addLine(to: CGPoint(x: center.x + radius * 0.55, y: center.y + radius * 0.25))
            context.stroke(hands, with: .color(.white.opacity(0.8)), lineWidth: 1.4)
            context.fill(Path(CGRect(x: tower.midX - 3, y: h * 0.62, width: 6, height: 18)), with: .color(color.opacity(0.55)))
        case 2:
            for offset in [0.0, 0.13] {
                var rail = Path(); rail.move(to: CGPoint(x: w * (0.57 + offset), y: h * 0.73)); rail.addLine(to: CGPoint(x: w * (0.38 + offset * 2.5), y: h))
                context.stroke(rail, with: .color(color.opacity(0.38)), lineWidth: 2)
            }
            let train = CGRect(x: w * 0.48, y: h * 0.46, width: w * 0.4, height: h * 0.28)
            context.fill(Path(roundedRect: train, cornerRadius: 9), with: .color(Color(red: 0.20, green: 0.18, blue: 0.21)))
            context.stroke(Path(roundedRect: train, cornerRadius: 9), with: .color(color.opacity(0.5)), lineWidth: 1)
            for i in 0..<5 {
                let r = CGRect(x: train.minX + 9 + CGFloat(i) * train.width / 5.4, y: train.minY + 9, width: train.width / 7, height: train.height * 0.38)
                context.fill(Path(roundedRect: r, cornerRadius: 2), with: .color(color.opacity(0.7)))
            }
            var cable = Path(); cable.move(to: CGPoint(x: w * 0.4, y: h * 0.29)); cable.addLine(to: CGPoint(x: w, y: h * 0.29))
            context.stroke(cable, with: .color(.white.opacity(0.14)), lineWidth: 1)
        default:
            for i in 0..<4 {
                let height = h * (0.14 + CGFloat([1, 3, 4, 2][i]) * 0.055)
                let rect = CGRect(x: w * 0.5 + CGFloat(i) * w * 0.09, y: h * 0.76 - height, width: w * 0.045, height: height)
                context.fill(Path(roundedRect: rect, cornerRadius: 4), with: .color(EchoStyle.colors[i].opacity(0.65)))
                context.stroke(Path(ellipseIn: CGRect(x: rect.midX - 15, y: h * 0.81, width: 30, height: 4)), with: .color(EchoStyle.colors[i].opacity(0.25)), lineWidth: 1)
            }
            for i in 0..<3 {
                let r = CGRect(x: w * 0.44 - CGFloat(i) * 7, y: h * 0.77 + CGFloat(i) * 7, width: w * 0.46 + CGFloat(i) * 14, height: 3)
                context.fill(Path(r), with: .color(color.opacity(0.14)))
            }
        }
    }
}

struct GameScenery: View {
    var chapter: Int
    var body: some View {
        GeometryReader { geometry in
            Image("Scene-\(min(3, max(0, chapter)))").resizable().scaledToFill()
                .frame(width: geometry.size.width, height: geometry.size.height).clipped()
                .saturation(0.35).blur(radius: 5)
                .overlay(EchoStyle.background.opacity(0.88))
                .overlay(LinearGradient(colors: [.clear, EchoStyle.background], startPoint: .top, endPoint: .bottom))
        }.ignoresSafeArea().allowsHitTesting(false).accessibilityHidden(true)
    }
}

struct AmbientParticles: View {
    var chapter = 0
    @State private var visible = false
    @Environment(\.echoReducedMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.echoArtworkActive) private var artworkActive
    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 12, paused: !visible || !artworkActive || reduceMotion || scenePhase != .active || ProcessInfo.processInfo.isLowPowerModeEnabled)) { time in
            Canvas { context, size in
                let elapsed = reduceMotion ? 0 : time.date.timeIntervalSinceReferenceDate
                for i in 0..<18 {
                    let x = CGFloat((i * 37 + 11) % 101) / 100 * size.width
                    let fraction = (Double(i * 19 % 100) / 100 + elapsed * (chapter == 0 ? 0.15 : 0.012)).truncatingRemainder(dividingBy: 1)
                    let y = fraction * size.height
                    if chapter == 0 {
                        var drop = Path(); drop.move(to: CGPoint(x: x, y: y)); drop.addLine(to: CGPoint(x: x - 3, y: y + 9))
                        context.stroke(drop, with: .color(EchoStyle.accent.opacity(0.1 + Double(i % 3) * 0.06)), lineWidth: 1)
                    } else {
                        var image = context.resolve(Image("EchoStar").renderingMode(.template))
                        image.shading = .color(EchoStyle.colors[min(3, max(0, chapter))])
                        context.opacity = 0.15 + Double(i % 3) * 0.12
                        let side = CGFloat(i % 3 == 0 ? 17 : 7)
                        context.draw(image, in: CGRect(x: x, y: y, width: side, height: side))
                    }
                }
            }
        }.onAppear { visible = true }.onDisappear { visible = false }
            .allowsHitTesting(false).accessibilityHidden(true)
    }
}

struct SuccessGlow: View {
    @Environment(\.echoReducedMotion) private var reduceMotion
    @State private var revealed = false
    var body: some View {
        GeometryReader { size in
            ZStack {
                Image("EchoLight").resizable().renderingMode(.template).foregroundStyle(EchoStyle.accent)
                    .scaledToFit().frame(width: 210).opacity(0.17)
                ForEach(0..<9) { i in
                    Image("EchoStar").resizable().renderingMode(.template).foregroundStyle(EchoStyle.colors[i % 4])
                        .frame(width: i % 2 == 0 ? 20 : 12, height: i % 2 == 0 ? 20 : 12)
                        .position(x: size.size.width * (0.08 + CGFloat(i) * 0.105), y: CGFloat([10, 65, 95, 20, 110, 12, 80, 25, 100][i]))
                }
            }.frame(maxWidth: .infinity, maxHeight: .infinity)
                .scaleEffect(reduceMotion || revealed ? 1 : 0.8)
                .opacity(reduceMotion || revealed ? 1 : 0)
                .animation(reduceMotion ? nil : .easeOut(duration: 0.7), value: revealed)
        }.task { revealed = true }.allowsHitTesting(false).accessibilityHidden(true)
    }
}
