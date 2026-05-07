import AppKit
import CoreGraphics
import Foundation

/// Asset-free fallback `PackSource`. Rasterises a cat-themed SF Symbol
/// composite per pose into a single sprite sheet so the existing
/// renderer (`PoseRenderer`, `FrameSelector`, integer-snap scaling)
/// drives it unchanged. Used as the user-facing default until real
/// pixel art lands; `BundledPackSource` is dark-launched behind
/// `MewtFeatureFlags.bundledPackEnabled`.
///
/// Each cell composes two symbols: `cat.fill` as identity (large,
/// centred) plus an optional state badge in the bottom-right corner
/// (`zzz`, `waveform`, PTT radio). Mirrors Apple's Mail/Messages icon
/// badge convention — brand identity is constant, state cue rides on
/// a small affordance.
///
/// Why bake symbols into a bitmap rather than reach for native
/// `.symbolEffect`/`Image(systemName:)`? Two render paths means two
/// places `(status, amplitude, t) → pixels` can diverge. Keeping a
/// single sprite path preserves Phase 4 foundation invariants intact.
///
/// `tintPolicy` is set to `.none` so `PoseRenderer` skips the muted
/// desaturation (no-op on monochrome icons) and the programmatic
/// `EffectOverlay` (`zzz`, PTT glow) — the badge in the composite
/// already conveys the same affordances, baked into the sheet at the
/// correct anchor.
struct SymbolPackSource: PackSource {
  static let packId = "com.chaninlaw.mewt.symbol"

  /// Optimal frame side per engine spec §4.6 ({16, 32, 64, 128}).
  /// 64 matches `PoseRenderer`'s default display size, so
  /// `SpriteFrameView.integerSnapScale` resolves to 1× with no
  /// resampling.
  private static let frameSide: CGFloat = 64

  private let symbolPack: CharacterPack

  init() {
    let order = PoseTag.allCases
    var frames: [SpriteFrame] = []
    var poses: [PoseTag: PoseAnimation] = [:]
    for (i, tag) in order.enumerated() {
      frames.append(
        SpriteFrame(
          rect: CGRect(
            x: CGFloat(i) * Self.frameSide,
            y: 0,
            width: Self.frameSide,
            height: Self.frameSide
          ),
          duration: 0
        )
      )
      poses[tag] = PoseAnimation(
        frameRange: i..<(i + 1),
        loopMode: .freeze,
        fpsMultiplier: 1.0
      )
    }

    var overrides = PackOverrides.default
    overrides.tintPolicy = .none

    self.symbolPack = CharacterPack(
      id: SymbolPackSource.packId,
      name: "Mewt (symbols)",
      author: "Mewt",
      version: "1.0.0",
      tier: .free,
      frames: frames,
      poses: poses,
      overrides: overrides,
      extras: [:]
    )
  }

  func packs() -> [CharacterPack] { [symbolPack] }

  @MainActor
  func resources(for packId: String) -> PackResources? {
    guard packId == SymbolPackSource.packId else { return nil }
    return PackResources(
      packId: packId,
      spriteImage: SymbolPackSource.synthesizeSheet(
        order: PoseTag.allCases,
        frameSide: Self.frameSide
      )
    )
  }

  // MARK: - Sheet synthesis

  @MainActor
  private static func synthesizeSheet(order: [PoseTag], frameSide: CGFloat) -> NSImage {
    let count = max(order.count, 1)
    let sheetSize = NSSize(width: frameSide * CGFloat(count), height: frameSide)

    return NSImage(size: sheetSize, flipped: false) { _ in
      NSColor.clear.set()
      NSRect(origin: .zero, size: sheetSize).fill()
      for (i, tag) in order.enumerated() {
        let cell = NSRect(
          x: CGFloat(i) * frameSide,
          y: 0,
          width: frameSide,
          height: frameSide
        )
        drawCellComposite(for: tag, in: cell)
      }
      return true
    }
  }

  /// Composites `cat.fill` (large) + state badge (small, bottom-right)
  /// inside `cell`. Tinting uses Apple's native palette configuration
  /// (`SymbolConfiguration(paletteColors:)`) so colour resolution is
  /// driven by the symbol renderer itself — earlier versions used a
  /// `.destinationIn` masking trick which produced fully-transparent
  /// cells for some symbol/colour combinations on macOS 26.
  @MainActor
  private static func drawCellComposite(for tag: PoseTag, in cell: NSRect) {
    let descriptor = symbolDescriptor(for: tag)
    drawTintedSymbol(
      name: descriptor.main,
      pointSize: cell.width * 0.62,
      weight: .semibold,
      color: descriptor.mainColor,
      anchor: .center(in: cell)
    )
    if let badge = descriptor.badge {
      drawTintedSymbol(
        name: badge,
        pointSize: cell.width * 0.34,
        weight: .bold,
        color: descriptor.badgeColor,
        anchor: .bottomRight(in: cell, inset: cell.width * 0.06)
      )
    }
  }

  @MainActor
  private static func drawTintedSymbol(
    name: String,
    pointSize: CGFloat,
    weight: NSFont.Weight,
    color: NSColor,
    anchor: SymbolAnchor
  ) {
    let cfg = NSImage.SymbolConfiguration(pointSize: pointSize, weight: weight)
      .applying(NSImage.SymbolConfiguration(paletteColors: [color]))
    guard
      let tinted = NSImage(systemSymbolName: name, accessibilityDescription: nil)?
        .withSymbolConfiguration(cfg)
    else { return }

    tinted.draw(
      in: anchor.rect(for: tinted.size),
      from: .zero,
      operation: .sourceOver,
      fraction: 1.0
    )
  }

  private enum SymbolAnchor {
    case center(in: NSRect)
    case bottomRight(in: NSRect, inset: CGFloat)

    func rect(for size: NSSize) -> NSRect {
      switch self {
      case .center(let cell):
        return NSRect(
          x: cell.midX - size.width / 2,
          y: cell.midY - size.height / 2,
          width: size.width,
          height: size.height
        )
      case .bottomRight(let cell, let inset):
        return NSRect(
          x: cell.maxX - size.width - inset,
          y: cell.minY + inset,
          width: size.width,
          height: size.height
        )
      }
    }
  }

  private struct SymbolDescriptor {
    let main: String
    let mainColor: NSColor
    let badge: String?
    let badgeColor: NSColor
  }

  private static func symbolDescriptor(for tag: PoseTag) -> SymbolDescriptor {
    switch tag {
    case .idle, .unmuted:
      return .init(
        main: "cat.fill", mainColor: .labelColor,
        badge: nil, badgeColor: .clear
      )
    case .muted:
      return .init(
        main: "cat.fill", mainColor: .secondaryLabelColor,
        badge: "zzz", badgeColor: .secondaryLabelColor
      )
    case .talking:
      return .init(
        main: "cat.fill", mainColor: .labelColor,
        badge: "waveform", badgeColor: .controlAccentColor
      )
    case .pushToTalk:
      return .init(
        main: "cat.fill", mainColor: .controlAccentColor,
        badge: "dot.radiowaves.left.and.right", badgeColor: .controlAccentColor
      )
    }
  }
}
