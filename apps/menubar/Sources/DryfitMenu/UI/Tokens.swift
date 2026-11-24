// Generated from apps/menubar/tokens.json by `npm run menubar:tokens`. Don’t edit: change tokens.json.
import SwiftUI

extension Theme {
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
  static let text = color(0x1c1c1e, 0xf4f4f6)
  static let muted = color(0x5f6068, 0xb0b1b9)
  static let faint = color(0x8a8b93, 0x8b8c95)
  static let button = color(0x000000, 0xffffff, light: 0.06, dark: 0.09)
  static let buttonHover = color(0x000000, 0xffffff, light: 0.10, dark: 0.15)
  static let selection = color(0x0a6cff, 0x4c9bff, light: 0.14, dark: 0.22)
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

  static let buttonRadius: CGFloat = 7
  static let cardRadius: CGFloat = 12
  static let widgetCardRadius: CGFloat = 14
}
