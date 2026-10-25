import SwiftUI
import UIKit

private struct EchoMotionKey: EnvironmentKey { static let defaultValue = false }
private struct EchoArtworkActiveKey: EnvironmentKey { static let defaultValue = true }
extension EnvironmentValues {
    var echoReducedMotion: Bool {
        get { self[EchoMotionKey.self] }
        set { self[EchoMotionKey.self] = newValue }
    }
    var echoArtworkActive: Bool {
        get { self[EchoArtworkActiveKey.self] }
        set { self[EchoArtworkActiveKey.self] = newValue }
    }
}

enum EchoStyle {
    static let background = Color(red: 0.035, green: 0.055, blue: 0.11)
    static let panel = Color(red: 0.075, green: 0.10, blue: 0.17)
    static let secondary = Color(red: 0.57, green: 0.65, blue: 0.77)
    static let accent = Color(red: 0.32, green: 0.9, blue: 0.84)
    static let colors: [Color] = [.init(red: 0.32, green: 0.9, blue: 0.84), .init(red: 0.66, green: 0.53, blue: 1),
                                  .init(red: 1, green: 0.7, blue: 0.36), .init(red: 1, green: 0.48, blue: 0.65)]
    static let symbols = ["drop.fill", "moon.fill", "sun.max.fill", "sparkle"]
    static let names = ["雨滴", "月光", "暖阳", "星火"]
}

extension View {
    func echoPanel() -> some View {
        padding(20).background(LinearGradient(colors: [EchoStyle.panel, EchoStyle.panel.opacity(0.7)], startPoint: .topLeading, endPoint: .bottomTrailing), in: RoundedRectangle(cornerRadius: 24))
            .overlay(RoundedRectangle(cornerRadius: 24).stroke(LinearGradient(colors: [.white.opacity(0.1), .white.opacity(0.025)], startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 1))
            .shadow(color: .black.opacity(0.1), radius: 15, y: 8)
    }
    func echoBackground() -> some View {
        background { EchoBackdrop().ignoresSafeArea() }.preferredColorScheme(.dark)
    }
    func echoInstrumentPanel() -> some View {
        padding(20).background {
            LinearGradient(colors: [Color(red: 0.13, green: 0.16, blue: 0.2), EchoStyle.panel], startPoint: .topLeading, endPoint: .bottomTrailing)
            MaterialTexture(asset: "Material-Metal").blendMode(.softLight).opacity(0.45)
        }.clipShape(RoundedRectangle(cornerRadius: 24))
            .overlay(RoundedRectangle(cornerRadius: 24).strokeBorder(LinearGradient(colors: [.white.opacity(0.25), .black.opacity(0.3)], startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 1))
            .overlay(alignment: .topTrailing) {
                HStack(spacing: 5) { ForEach(0..<3) { _ in Capsule().fill(.black.opacity(0.35)).frame(width: 2, height: 11) } }
                    .padding(12).allowsHitTesting(false).accessibilityHidden(true)
            }
            .shadow(color: .black.opacity(0.25), radius: 12, y: 8)
    }
}

struct EchoButtonStyle: ButtonStyle {
    var secondary = false
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(.system(.headline, design: .rounded))
            .frame(maxWidth: .infinity).padding(.vertical, 16).padding(.horizontal, 14)
            .foregroundStyle(secondary ? Color.white : EchoStyle.background)
            .background(secondary ? Color.white.opacity(0.08) : EchoStyle.accent,
                        in: RoundedRectangle(cornerRadius: 17))
            .opacity(configuration.isPressed ? 0.72 : 1)
    }
}

struct SectionTitle: View {
    var title: String
    var caption: String = ""
    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title).font(.system(.title3, design: .rounded, weight: .bold))
            Spacer()
            Text(caption).font(.caption).foregroundStyle(EchoStyle.secondary)
        }
    }
}

struct MetricView: View {
    var value: String
    var title: String
    var body: some View {
        VStack(spacing: 5) {
            Text(value).font(.system(.title2, design: .rounded, weight: .bold)).monospacedDigit()
            Text(title).font(.caption).foregroundStyle(EchoStyle.secondary)
        }.frame(maxWidth: .infinity)
    }
}

struct EchoMark: View {
    var body: some View {
        ZStack {
            ForEach(0..<3) { index in
                Circle().stroke(EchoStyle.accent.opacity(0.22 - Double(index) * 0.055), lineWidth: 1)
                    .frame(width: CGFloat(70 + index * 28), height: CGFloat(70 + index * 28))
            }
            Image(systemName: "waveform").font(.system(size: 35, weight: .medium)).foregroundStyle(EchoStyle.accent)
        }.frame(width: 132, height: 132).accessibilityHidden(true)
    }
}

struct PadGrid: View {
    var lit: Int? = nil
    var enabled = true
    var compact = false
    var action: (Int, Double) -> Void
    var body: some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 14), GridItem(.flexible(), spacing: 14)], spacing: 14) {
            ForEach(0..<4) { lane in
                BeatPad(lane: lane, lit: lit == lane, enabled: enabled, compact: compact) { timestamp in action(lane, timestamp) }
            }
        }.frame(maxWidth: 560)
    }
}

struct BeatPad: View {
    @Environment(\.echoReducedMotion) private var reduceMotion
    let lane: Int
    var lit = false
    var enabled = true
    var compact = false
    var action: (Double) -> Void
    @State private var pressed = false
    @State private var ripple = 1.0
    private var active: Bool { lit || pressed }
    private var color: Color { EchoStyle.colors[lane] }
    private var corner: CGFloat { compact ? 18 : 26 }
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: corner).fill(Color(red: 0.06, green: 0.08, blue: 0.13))
            RoundedRectangle(cornerRadius: corner)
                .fill(LinearGradient(colors: [color.opacity(active ? 0.72 : 0.22), color.opacity(active ? 0.32 : 0.045)], startPoint: .topLeading, endPoint: .bottomTrailing))
            MaterialTexture(asset: "Material-Metal").blendMode(.softLight).opacity(0.3)
            MaskedLight(color: color).opacity(active ? 0.7 : 0.14)
            RoundedRectangle(cornerRadius: corner - 4)
                .strokeBorder(LinearGradient(colors: [.white.opacity(active ? 0.36 : 0.16), .white.opacity(0.01), .black.opacity(0.35)], startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 1)
                .padding(4)
            RoundedRectangle(cornerRadius: corner)
                .strokeBorder(LinearGradient(colors: [color.opacity(active ? 1 : 0.65), color.opacity(active ? 0.6 : 0.16)], startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: active ? 1.5 : 1)
            if !reduceMotion {
                PadVoiceEffect(lane: lane, progress: ripple)
                    .allowsHitTesting(false).accessibilityHidden(true)
            }
            VStack(spacing: compact ? 7 : 11) {
                Image(systemName: EchoStyle.symbols[lane]).font(.system(size: compact ? 23 : 31, weight: .medium))
                    .shadow(color: color.opacity(active ? 0.5 : 0.15), radius: 7)
                Text(EchoStyle.names[lane]).font(.system(.caption, design: .rounded, weight: .medium))
            }.foregroundStyle(active ? .white : color).accessibilityHidden(true)
            VStack {
                HStack {
                    Text(String(format: "%02d", lane + 1)).font(.system(size: 8, weight: .medium, design: .monospaced))
                        .foregroundStyle(color.opacity(0.65))
                    Spacer()
                    Capsule().fill(color.opacity(active ? 1 : 0.25)).frame(width: compact ? 13 : 19, height: 2)
                        .shadow(color: color.opacity(active ? 0.8 : 0), radius: 4)
                }
                Spacer(minLength: 0)
            }.padding(compact ? 11 : 15).allowsHitTesting(false).accessibilityHidden(true)
            PadTouchCapture(enabled: enabled, label: EchoStyle.names[lane], identifier: "pad-\(lane)",
                action: action, pressed: $pressed)
        }.frame(height: compact ? 88 : 130)
            .clipShape(RoundedRectangle(cornerRadius: corner))
            .shadow(color: .black.opacity(0.24), radius: pressed ? 2 : 5, y: pressed ? 1 : 5)
            .shadow(color: color.opacity(active ? 0.2 : 0), radius: 12)
            .scaleEffect(pressed && !reduceMotion ? 0.98 : 1)
            .offset(y: pressed && !reduceMotion ? 1 : 0)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.1), value: pressed)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: lit)
            .onChange(of: pressed) { _, value in if value { emitRipple() } }
            .onChange(of: lit) { _, value in if value { emitRipple() } }
            .onChange(of: enabled) { _, value in if !value { pressed = false } }
    }
    private func emitRipple() {
        guard !reduceMotion else { return }
        var transaction = Transaction(); transaction.disablesAnimations = true
        withTransaction(transaction) { ripple = 0 }
        withAnimation(.easeOut(duration: 0.48)) { ripple = 1 }
    }
}

private struct PadVoiceEffect: View, Animatable {
    let lane: Int
    var progress: Double
    var animatableData: Double { get { progress } set { progress = newValue } }
    var body: some View {
        Canvas { context, size in
            guard progress < 1 else { return }
            let center = CGPoint(x: size.width / 2, y: size.height / 2)
            let radius = min(size.width, size.height) * (0.12 + progress * 0.8)
            let color = EchoStyle.colors[lane].opacity((1 - progress) * 0.65)
            switch lane {
            case 0:
                for scale in [0.65, 1.0, 1.35] {
                    let r = radius * scale
                    context.stroke(Path(ellipseIn: CGRect(x: center.x - r, y: center.y - r * 0.6, width: r * 2, height: r * 1.2)), with: .color(color), lineWidth: 1.2)
                }
            case 1:
                for index in 0..<12 {
                    let angle = Double(index) * .pi / 6
                    var ray = Path()
                    ray.move(to: CGPoint(x: center.x + cos(angle) * radius * 0.7, y: center.y + sin(angle) * radius * 0.7))
                    ray.addLine(to: CGPoint(x: center.x + cos(angle) * radius, y: center.y + sin(angle) * radius))
                    context.stroke(ray, with: .color(color), style: StrokeStyle(lineWidth: 2, lineCap: .round))
                }
            case 2:
                let rect = CGRect(x: center.x - radius, y: center.y - radius * 0.55, width: radius * 2, height: radius * 1.1)
                context.stroke(Path(roundedRect: rect, cornerRadius: radius * 0.4), with: .color(color), lineWidth: 3 * (1 - progress) + 1)
                var line = Path(); line.move(to: CGPoint(x: center.x - radius, y: center.y)); line.addLine(to: CGPoint(x: center.x + radius, y: center.y))
                context.stroke(line, with: .color(color), lineWidth: 1)
            default:
                for index in 0..<16 {
                    let angle = Double(index) * 2.39996
                    let distance = radius * (0.45 + Double(index % 4) * 0.22)
                    let x = center.x + cos(angle) * distance, y = center.y + sin(angle) * distance * 0.6
                    context.fill(Path(ellipseIn: CGRect(x: x, y: y, width: 2 + Double(index % 2), height: 2 + Double(index % 2))), with: .color(color))
                }
            }
        }
    }
}

struct BPMControl: View {
    @Binding var value: Double
    var maximum = 180.0
    var body: some View {
        VStack(spacing: 9) {
            HStack {
                Text("\(Int(value))").font(.system(.title2, design: .rounded, weight: .semibold)).monospacedDigit()
                Text("BPM").font(.caption).foregroundStyle(EchoStyle.secondary)
                Spacer()
                Button { value = max(50, value - 1) } label: { Image(systemName: "minus").frame(width: 36, height: 32) }
                    .accessibilityLabel("速度减一")
                Button { value = min(maximum, value + 1) } label: { Image(systemName: "plus").frame(width: 36, height: 32) }
                    .accessibilityLabel("速度加一")
            }.buttonStyle(.bordered)
            Slider(value: $value, in: 50...maximum, step: 1).accessibilityLabel("谱面速度")
        }
    }
}

struct RhythmMiniature: View {
    let pattern: RhythmPattern
    var body: some View {
        Canvas { context, size in
            let last = Double(max(8, (pattern.notes.last?.tick ?? 0) + 1))
            for lane in 0..<4 {
                let y = (Double(lane) + 0.5) * size.height / 4
                var line = Path(); line.move(to: CGPoint(x: 0, y: y)); line.addLine(to: CGPoint(x: size.width, y: y))
                context.stroke(line, with: .color(.white.opacity(0.06)), lineWidth: 1)
            }
            for note in pattern.notes {
                let x = Double(note.tick) / last * (size.width - 8) + 4
                let y = (Double(note.lane) + 0.5) * size.height / 4
                context.fill(Path(roundedRect: CGRect(x: x - 2, y: y - 3, width: 4, height: 6), cornerRadius: 2), with: .color(EchoStyle.colors[note.lane]))
            }
        }.frame(height: 42).accessibilityLabel("节奏缩略图，共 \(pattern.notes.count) 个音符")
    }
}

struct PadTouchCapture: UIViewRepresentable {
    var enabled: Bool
    var label: String
    var identifier: String
    var action: (Double) -> Void
    @Binding var pressed: Bool
    func makeUIView(context: Context) -> TouchSurface { TouchSurface() }
    func updateUIView(_ view: TouchSurface, context: Context) {
        view.action = action; view.changed = { pressed = $0 }
        view.isUserInteractionEnabled = enabled
        view.accessibilityLabel = label; view.accessibilityIdentifier = identifier
        view.isAccessibilityElement = true; view.accessibilityTraits = enabled ? .button : [.button, .notEnabled]
    }
    final class TouchSurface: UIView {
        var action: ((Double) -> Void)?
        var changed: ((Bool) -> Void)?
        override init(frame: CGRect) { super.init(frame: frame); backgroundColor = .clear; isMultipleTouchEnabled = false }
        required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
        override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
            guard let touch = touches.first else { return }; changed?(true); action?(touch.timestamp)
        }
        override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) { changed?(false) }
        override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) { changed?(false) }
        override func accessibilityActivate() -> Bool { action?(ProcessInfo.processInfo.systemUptime); return true }
    }
}

struct PatternDots: View {
    var pattern: RhythmPattern
    var body: some View {
        HStack(spacing: 6) {
            ForEach(Array(pattern.notes.prefix(12).enumerated()), id: \.offset) { _, note in
                Image(systemName: EchoStyle.symbols[note.lane]).font(.system(size: 9))
                    .foregroundStyle(EchoStyle.colors[note.lane])
            }
        }.accessibilityLabel("\(pattern.notes.count) 个音符")
    }
}
