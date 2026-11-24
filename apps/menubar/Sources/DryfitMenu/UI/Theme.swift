import AppKit
import SwiftUI

/// The design, taken one for one from the approved mockup (`docs/design/dryfit-states.html`): its colours
/// for light and dark, its type sizes and its radii. Nothing here asks the system for a colour, so a window
/// looks the same on every Mac.
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

  // Colours and radii are in Tokens.swift, generated from apps/menubar/tokens.json.

  // Type
  static let body = Font.system(size: 13)
  static let bodyMedium = Font.system(size: 13, weight: .medium)
  static let bodySemibold = Font.system(size: 13, weight: .semibold)
  static let small = Font.system(size: 12)
  static let smallMedium = Font.system(size: 12, weight: .medium)
  static let caption = Font.system(size: 11)
  static let mono = Font.system(size: 12, design: .monospaced)
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
