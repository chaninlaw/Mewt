import AppKit
import SwiftUI

/// Brand palette, shared with `site/styles.css`.
enum Brand {
    static let background = Color(hex: 0xF7F7F5)
    static let backgroundLow = Color(hex: 0xEDEDE9)
    static let ink = Color(hex: 0x1F1F1D)
    static let inkMuted = Color(hex: 0x6E6E6A)
    static let wallpaperTop = Color(hex: 0xE4E0D8)
    static let wallpaperBottom = Color(hex: 0xC2BCB1)
    static let popover = Color(hex: 0x2A2A2C)
}

extension Color {
    init(hex: UInt32) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255
        )
    }
}

/// 960×600 pt artboard: caption on the left, a slice of desktop on the right.
struct Artboard<Stage: View>: View {
    let eyebrow: String
    let headline: String
    let detail: String
    @ViewBuilder let stage: Stage

    var body: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 18) {
                Text(eyebrow.uppercased())
                    .font(.system(size: 13, weight: .semibold))
                    .tracking(2.4)
                    .foregroundStyle(Brand.inkMuted)
                Text(headline)
                    .font(.system(size: 44, weight: .bold))
                    .tracking(-1.2)
                    .lineSpacing(-4)
                    .foregroundStyle(Brand.ink)
                    .fixedSize(horizontal: false, vertical: true)
                Text(detail)
                    .font(.system(size: 17))
                    .lineSpacing(3)
                    .foregroundStyle(Brand.inkMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(width: 400, alignment: .leading)
            .padding(.leading, 72)

            Spacer(minLength: 0)

            stage
                .frame(width: 420)
                .padding(.trailing, 56)
        }
        .frame(width: ScreenshotRenderer.canvas.width, height: ScreenshotRenderer.canvas.height)
        .background(
            LinearGradient(colors: [Brand.background, Brand.backgroundLow], startPoint: .top, endPoint: .bottom)
        )
        .environment(\.colorScheme, .light)
    }
}

/// Rounded slice of a desktop: wallpaper, menu bar, and whatever hangs below.
struct DesktopStage<Content: View>: View {
    var catState: MenuBarGlyph = .unmuted
    @ViewBuilder let content: Content

    var body: some View {
        VStack(spacing: 0) {
            MenuBarStrip(glyph: catState, highlighted: true)
            content
        }
        .padding(.bottom, 48)
        .wallpaperCard()
    }
}

extension View {
    /// Wallpaper-filled rounded card that hugs its content's height.
    func wallpaperCard() -> some View {
        background(
            LinearGradient(colors: [Brand.wallpaperTop, Brand.wallpaperBottom], startPoint: .topLeading, endPoint: .bottomTrailing)
        )
        .clipShape(.rect(cornerRadius: 22))
        .overlay(RoundedRectangle(cornerRadius: 22).strokeBorder(.black.opacity(0.06)))
        .shadow(color: .black.opacity(0.12), radius: 30, y: 16)
    }
}

enum MenuBarGlyph {
    case unmuted, talking, pushToTalk, muted

    var assetName: String {
        switch self {
        case .unmuted: "cat"
        case .talking, .pushToTalk: "talk-6"
        case .muted: "paw-print"
        }
    }
}

/// Mock menu bar, right-aligned like the real one. `catCenterFromTrailing`
/// tells the popover where to point its arrow.
struct MenuBarStrip: View {
    static let height: CGFloat = 30
    static let catCenterFromTrailing: CGFloat = 165

    let glyph: MenuBarGlyph
    var highlighted = false

    var body: some View {
        HStack(spacing: 16) {
            Spacer(minLength: 0)
            Image(nsImage: NSImage(named: glyph.assetName) ?? NSImage())
                .renderingMode(.template)
                .resizable()
                .frame(width: 18, height: 18)
                .foregroundStyle(glyph == .pushToTalk ? Color.blue : Brand.ink)
                .frame(width: 30, height: 22)
                .background(highlighted ? Color.white.opacity(0.45) : .clear, in: .rect(cornerRadius: 5))
            Image(systemName: "wifi")
            Image(systemName: "magnifyingglass")
            Text("Thu 9:41")
                .monospacedDigit()
        }
        .font(.system(size: 13, weight: .medium))
        .foregroundStyle(Brand.ink.opacity(0.85))
        .padding(.trailing, 16)
        .frame(height: Self.height)
        .background(.white.opacity(0.5))
    }
}

/// Dark popover chrome around the real `ContentView`, arrow under the cat.
enum PopoverLayout {
    static let trailingInset: CGFloat = 24
}

struct PopoverFrame<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        let shape = PopoverShape(arrowX: 280 - (MenuBarStrip.catCenterFromTrailing - PopoverLayout.trailingInset))
        content
            .fixedSize(horizontal: false, vertical: true)
            .environment(\.colorScheme, .dark)
            .padding(.top, PopoverShape.arrowHeight)
            .background(shape.fill(Brand.popover))
            .overlay(shape.stroke(.white.opacity(0.14), lineWidth: 1))
            .clipShape(shape)
            .shadow(color: .black.opacity(0.35), radius: 22, y: 12)
            .frame(maxWidth: .infinity, alignment: .trailing)
            .padding(.trailing, PopoverLayout.trailingInset)
            .padding(.top, 2)
    }
}

struct PopoverShape: Shape {
    static let arrowHeight: CGFloat = 9
    let arrowX: CGFloat
    var radius: CGFloat = 12
    var arrowHalfWidth: CGFloat = 11

    func path(in rect: CGRect) -> Path {
        let top = rect.minY + Self.arrowHeight
        var p = Path()
        p.move(to: CGPoint(x: rect.minX + radius, y: top))
        p.addLine(to: CGPoint(x: arrowX - arrowHalfWidth, y: top))
        p.addQuadCurve(to: CGPoint(x: arrowX, y: rect.minY), control: CGPoint(x: arrowX - 3, y: top - 1))
        p.addQuadCurve(to: CGPoint(x: arrowX + arrowHalfWidth, y: top), control: CGPoint(x: arrowX + 3, y: top - 1))
        p.addLine(to: CGPoint(x: rect.maxX - radius, y: top))
        p.addArc(tangent1End: CGPoint(x: rect.maxX, y: top), tangent2End: CGPoint(x: rect.maxX, y: rect.maxY), radius: radius)
        p.addArc(tangent1End: CGPoint(x: rect.maxX, y: rect.maxY), tangent2End: CGPoint(x: rect.minX, y: rect.maxY), radius: radius)
        p.addArc(tangent1End: CGPoint(x: rect.minX, y: rect.maxY), tangent2End: CGPoint(x: rect.minX, y: top), radius: radius)
        p.addArc(tangent1End: CGPoint(x: rect.minX, y: top), tangent2End: CGPoint(x: rect.maxX, y: top), radius: radius)
        p.closeSubpath()
        return p
    }
}

/// Shot 5: the four menu-bar states, one strip each.
struct MenuBarStatesStage: View {
    private let rows: [(MenuBarGlyph, String, String)] = [
        (.unmuted, "Unmuted", "Mic is live"),
        (.talking, "Talking", "Cat animates while you speak"),
        (.pushToTalk, "Push-to-talk", "Held key opens the mic"),
        (.muted, "Muted", "System-wide, every app"),
    ]

    var body: some View {
        VStack(spacing: 22) {
                ForEach(rows, id: \.1) { glyph, title, detail in
                    VStack(alignment: .leading, spacing: 8) {
                        MenuBarStrip(glyph: glyph, highlighted: true)
                            .clipShape(.rect(cornerRadius: 9))
                        HStack(spacing: 8) {
                            Text(title).font(.system(size: 15, weight: .semibold)).foregroundStyle(Brand.ink)
                            Text(detail).font(.system(size: 14)).foregroundStyle(Brand.ink.opacity(0.6))
                        }
                        .padding(.leading, 4)
                    }
                }
            }
        .padding(.horizontal, 32)
        .padding(.vertical, 44)
        .wallpaperCard()
    }
}
