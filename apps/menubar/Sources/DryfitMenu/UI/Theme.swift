import AppKit
import SwiftUI

/// The design, taken one for one from the approved mockup (`dryfit-states.html`): its colours for light
/// and dark, its type sizes and its radii. Nothing here asks the system for a colour, so a window looks
/// the same on every Mac.
enum Theme {
  /// A colour with a light and a dark value, each `0xRRGGBB` with an alpha.
  static func color(_ light: UInt32, _ dark: UInt32, light lightAlpha: Double = 1, dark darkAlpha: Double = 1) -> Color {
    func ns(_ hex: UInt32, _ alpha: Double) -> NSColor {
      NSColor(
        srgbRed: CGFloat((hex >> 16) & 0xff) / 255, green: CGFloat((hex >> 8) & 0xff) / 255,
        blue: CGFloat(hex & 0xff) / 255, alpha: alpha)
    }
    return Color(
      nsColor: NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? ns(dark, darkAlpha) : ns(light, lightAlpha)
      })
  }

  // Surfaces
  static let window = color(0xfbfbfc, 0x1e1e21)
  static let sidebar = color(0xeeeef1, 0x26262a)
  static let card = color(0xffffff, 0x2a2a2e)
  static let cardBorder = color(0x000000, 0xffffff, light: 0.08, dark: 0.08)
  static let hairline = color(0x000000, 0xffffff, light: 0.08, dark: 0.09)
  static let code = color(0xf3f3f5, 0x19191b)
  /// The panel of the menu bar window, drawn over the system's Liquid Glass so it reads as the mockup's.
  static let glass = color(0xffffff, 0x28282c, light: 0.82, dark: 0.82)
  /// A card on that panel. The window's dark card grey is too close to the dark panel to stand apart,
  /// so the widget's cards are a step lighter there; in light they stay white.
  static let widgetCard = color(0xffffff, 0x37373c)

  // Text
  static let text = color(0x1c1c1e, 0xf4f4f6)
  static let muted = color(0x5f6068, 0xb0b1b9)
  static let faint = color(0x8a8b93, 0x8b8c95)

  // Controls
  static let button = color(0x000000, 0xffffff, light: 0.06, dark: 0.09)
  static let buttonHover = color(0x000000, 0xffffff, light: 0.10, dark: 0.15)
  static let selection = color(0x0a6cff, 0x4c9bff, light: 0.14, dark: 0.22)

  // Colour with a meaning
  static let accent = color(0x0a6cff, 0x4c9bff)
  static let accentTint = color(0x0a6cff, 0x4c9bff, light: 0.12, dark: 0.18)
  static let dev = color(0xd6307f, 0xff6aa9)
  static let devTint = color(0xd6307f, 0xff6aa9, light: 0.12, dark: 0.16)
  static let release = color(0x12806f, 0x3fd0b6)
  static let releaseTint = color(0x12806f, 0x3fd0b6, light: 0.12, dark: 0.15)
  static let bad = color(0xc8281e, 0xff6b61)
  static let badTint = color(0xc8281e, 0xff6b61, light: 0.09, dark: 0.12)
  static let badBorder = color(0xc8281e, 0xff6b61, light: 0.28, dark: 0.35)
  static let warn = color(0xa85d00, 0xffb340)
  static let warnTint = color(0xe68c00, 0xffb340, light: 0.14, dark: 0.15)
  static let warnBorder = color(0xc87800, 0xffb340, light: 0.35, dark: 0.40)
  static let ok = color(0x2fb457, 0x2fb457)
  static let okTint = color(0x2fb457, 0x2fb457, light: 0.14, dark: 0.14)
  static let okText = color(0x1f8a40, 0x5ddb85)
  static let purple = color(0x8250dc, 0xb58cff)
  static let purpleTint = color(0x8250dc, 0x8250dc, light: 0.14, dark: 0.14)

  // Type
  static let body = Font.system(size: 13)
  static let bodyMedium = Font.system(size: 13, weight: .medium)
  static let bodySemibold = Font.system(size: 13, weight: .semibold)
  static let small = Font.system(size: 12)
  static let smallMedium = Font.system(size: 12, weight: .medium)
  static let caption = Font.system(size: 11)
  static let mono = Font.system(size: 12, design: .monospaced)

  // Shape
  static let buttonRadius: CGFloat = 7
  static let cardRadius: CGFloat = 12
  static let widgetCardRadius: CGFloat = 14
}

extension View {
  /// The text style of a caption line: 12 pt in the muted grey, on the 1.4 line the mockup sets.
  func muted(_ size: CGFloat = 12) -> some View {
    font(.system(size: size)).foregroundStyle(Theme.muted).lh(size)
  }

  /// The mockup's `line-height`: a line is `factor` times its font size tall, whatever the font's own
  /// metrics say, with the text centred in it as a browser does.
  func lh(_ size: CGFloat, _ factor: CGFloat = 1.4) -> some View {
    frame(minHeight: size * factor)
  }
}
