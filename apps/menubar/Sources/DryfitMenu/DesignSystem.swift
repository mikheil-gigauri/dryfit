import SwiftUI

/// The measurements the app is drawn to: 13 pt text with 12 pt captions, 0.5 pt hairlines, 10 pt
/// corners on groups and cards, 8 pt on buttons. The system draws the glass (the menu bar panel, the
/// sidebar, the toolbar, sheets); everything inside is content, drawn flat. Status is never colour
/// alone: a symbol or a word always goes with it.
enum DS {
  static let body = Font.system(size: 13)
  static let medium = Font.system(size: 13, weight: .medium)
  static let caption = Font.system(size: 12)
  static let small = Font.system(size: 11)
  static let mono = Font.system(size: 12, design: .monospaced)
  static let headline = Font.system(size: 14, weight: .semibold)
  static let sheetTitle = Font.system(size: 15, weight: .semibold)
  static let title = Font.system(size: 21, weight: .semibold)

  /// The default hairline, between rows.
  static let hairline = Color.primary.opacity(0.1)
  /// Around buttons.
  static let strongBorder = Color.primary.opacity(0.2)
  /// A grey wash that shows on any background: badges, output.
  static let neutralFill = Color.primary.opacity(0.06)
  static let accentTint = Color.accentColor.opacity(0.14)
  /// Behind a group of rows or a card, so it reads as a surface on the window or the menu's glass.
  static let groupFill = Color(
    nsColor: NSColor(name: "dryfitCard") { appearance in
      appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? NSColor(white: 1, alpha: 0.07) : NSColor(white: 1, alpha: 0.85)
    })
  /// The edge of a card: a fill alone disappears on a light window.
  static let cardBorder = Color.primary.opacity(0.08)
  /// Behind a button, a step brighter than the group it sits on.
  static let buttonFill = Color.primary.opacity(0.1)
  static let radius: CGFloat = 10
  static let buttonRadius: CGFloat = 8
  /// Muted text and symbols: captions, paths, values beside a label. The system's secondary grey
  /// measures 3.8:1 on a group in light mode, under the 4.5:1 that 11 pt text needs; this one is
  /// about 4.8:1 there and the system's own 55% in dark mode, and stronger with Increase Contrast.
  static let muted = Color(
    nsColor: NSColor(name: "dryfitMuted") { appearance in
      switch appearance.bestMatch(from: [.aqua, .darkAqua, .accessibilityHighContrastAqua, .accessibilityHighContrastDarkAqua]) {
      case .darkAqua: NSColor(white: 1, alpha: 0.55)
      case .accessibilityHighContrastDarkAqua: NSColor(white: 1, alpha: 0.75)
      case .accessibilityHighContrastAqua: NSColor(white: 0, alpha: 0.75)
      default: NSColor(white: 0, alpha: 0.56)
      }
    })
}

/// A one-pixel line across the full width, snapped to the pixel grid so it never fades out.
struct Hairline: View {
  @Environment(\.displayScale) private var scale
  var body: some View { Rectangle().fill(DS.hairline).frame(height: 1 / scale) }
}

/// Rows on a filled rounded rectangle, with a hairline between each.
struct HairlineGroup<Content: View>: View {
  var border: Color? = nil
  @ViewBuilder var content: Content

  var body: some View {
    VStack(spacing: 0) {
      Group(subviews: content) { subviews in
        ForEach(Array(subviews.enumerated()), id: \.offset) { index, subview in
          if index > 0 { Hairline() }
          subview
        }
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(DS.groupFill, in: .rect(cornerRadius: DS.radius))
    .overlay {
      // A warning group is outlined in its colour; the others in a hairline, so a light card still has an edge.
      if let border {
        RoundedRectangle(cornerRadius: DS.radius).strokeBorder(border, lineWidth: 1)
      } else {
        RoundedRectangle(cornerRadius: DS.radius).strokeBorder(DS.cardBorder, lineWidth: 0.5)
      }
    }
  }
}

/// One row of a `HairlineGroup`: 7 by 10 pt of padding, 8 pt between its parts.
struct GroupRow<Content: View>: View {
  @ViewBuilder var content: Content

  var body: some View {
    HStack(spacing: 8) { content }
      .font(DS.body)
      .padding(.horizontal, 14)
      .padding(.vertical, 9)
      .frame(maxWidth: .infinity, alignment: .leading)
  }
}

/// The small grey label above a group.
struct SectionLabel: View {
  let text: String
  init(_ text: String) { self.text = text }

  var body: some View {
    Text(text).font(DS.caption).foregroundStyle(DS.muted).padding(.top, 14).padding(.bottom, 4)
  }
}

/// The muted note under a group.
struct Footnote: View {
  let text: String
  init(_ text: String) { self.text = text }

  var body: some View {
    Text(text).font(DS.caption).foregroundStyle(DS.muted).padding(.top, 4)
      .fixedSize(horizontal: false, vertical: true)
  }
}

/// Two lines: a name and a muted caption under it.
struct TwoLine: View {
  let title: String
  let caption: String?
  var titleFont = DS.body
  /// Whether the caption wraps onto more lines instead of being cut short.
  var wraps = false

  var body: some View {
    VStack(alignment: .leading, spacing: 1) {
      Text(title).font(titleFont).lineLimit(1)
      if let caption {
        Text(caption).font(DS.caption).foregroundStyle(DS.muted)
          .lineLimit(wraps ? nil : 1)
          .fixedSize(horizontal: false, vertical: wraps)
      }
    }
  }
}

/// Two lines whose first is any view, such as a name with a badge.
struct TwoLineView<Title: View>: View {
  let title: Title
  let caption: String

  var body: some View {
    VStack(alignment: .leading, spacing: 1) {
      title
      Text(caption).font(DS.caption).foregroundStyle(DS.muted).lineLimit(1)
    }
  }
}

// MARK: Buttons

/// The app's buttons are the system's: bordered at small size, the one primary action of a screen
/// prominent in the accent colour, and removal destructive. This style only adds a spinner that
/// stands in for the title while the button's job runs, at full strength and the same width.
struct PillButtonStyle: PrimitiveButtonStyle {
  enum Kind { case normal, primary, accent, danger }
  var kind = Kind.normal
  var busy = false

  func makeBody(configuration: Configuration) -> some View {
    let button = Button(role: kind == .danger ? .destructive : nil, action: configuration.trigger) {
      configuration.label
        .labelStyle(PillLabelStyle())
        .foregroundStyle(kind == .accent ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(.primary))
        .opacity(busy ? 0 : 1)
        .overlay { if busy { ProgressView().controlSize(.mini) } }
    }
    return Group {
      if kind == .primary { button.buttonStyle(.borderedProminent) } else { button.buttonStyle(.bordered) }
    }
    .controlSize(.small)
    .allowsHitTesting(!busy)
    .accessibilityValue(busy ? Text("In progress") : Text(""))
  }
}

extension PrimitiveButtonStyle where Self == PillButtonStyle {
  static var pill: PillButtonStyle { PillButtonStyle() }
  static var primaryPill: PillButtonStyle { PillButtonStyle(kind: .primary) }
  static var accentPill: PillButtonStyle { PillButtonStyle(kind: .accent) }
  static var dangerPill: PillButtonStyle { PillButtonStyle(kind: .danger) }
  static func pill(busy: Bool) -> PillButtonStyle { PillButtonStyle(busy: busy) }
  static func accentPill(busy: Bool) -> PillButtonStyle { PillButtonStyle(kind: .accent, busy: busy) }
  static func dangerPill(busy: Bool) -> PillButtonStyle { PillButtonStyle(kind: .danger, busy: busy) }
}

/// Icon and title 4 pt apart, the icon at the text's size.
struct PillLabelStyle: LabelStyle {
  func makeBody(configuration: Configuration) -> some View {
    HStack(spacing: 4) {
      configuration.icon
      configuration.title
    }
  }
}

/// A small bordered button that opens a menu, with the system's indicator.
struct PillMenu<Items: View, Label: View>: View {
  var kind = PillButtonStyle.Kind.normal
  var busy = false
  @ViewBuilder var items: Items
  @ViewBuilder var label: Label

  var body: some View {
    Menu { items } label: {
      label.opacity(busy ? 0 : 1).overlay { if busy { ProgressView().controlSize(.mini) } }
    }
    .menuStyle(.button)
    .buttonStyle(.bordered)
    .controlSize(.small)
    .fixedSize()
    .allowsHitTesting(!busy)
  }
}

/// An app that uses the library, linked with one click: a small bordered button with a link symbol.
struct ChipButtonStyle: PrimitiveButtonStyle {
  var quiet = false

  func makeBody(configuration: Configuration) -> some View {
    Button(action: configuration.trigger) {
      configuration.label.labelStyle(PillLabelStyle()).foregroundStyle(Color.accentColor)
    }
    .buttonStyle(.bordered)
    .controlSize(.small)
  }
}

/// A borderless symbol at caption size, muted, that shows a spinner while its action runs.
struct IconButton: View {
  let symbol: String
  let label: String
  let busy: Bool
  let action: () -> Void

  var body: some View {
    Button(action: action) {
      ZStack {
        Image(systemName: symbol).font(.system(size: 13, weight: .medium)).opacity(busy ? 0 : 1)
        if busy { ProgressView().controlSize(.mini) }
      }
      .frame(width: 22, height: 22)
    }
    .buttonStyle(.borderless)
    .disabled(busy)
    .help(label)
    .accessibilityLabel(label)
  }
}

// MARK: Switch and checkbox

/// The system switch at mini size, its label hidden: rows say what it does.
struct MiniSwitchStyle: ToggleStyle {
  func makeBody(configuration: Configuration) -> some View {
    Toggle(configuration).toggleStyle(.switch).controlSize(.mini).labelsHidden()
  }
}

extension View {
  /// Clicks land anywhere within 24 by 24 pt of a smaller control, without moving anything.
  func hitTarget(_ size: CGSize = CGSize(width: 18, height: 18)) -> some View {
    let x = max(0, (24 - size.width) / 2)
    let y = max(0, (24 - size.height) / 2)
    return padding(.horizontal, x).padding(.vertical, y).contentShape(.rect)
      .padding(.horizontal, -x).padding(.vertical, -y)
  }
}

extension ToggleStyle where Self == MiniSwitchStyle {
  static var mini: MiniSwitchStyle { MiniSwitchStyle() }
}

/// The system checkbox.
struct Checkbox13Style: ToggleStyle {
  func makeBody(configuration: Configuration) -> some View {
    Toggle(configuration).toggleStyle(.checkbox)
  }
}

extension ToggleStyle where Self == Checkbox13Style {
  static var checkbox13: Checkbox13Style { Checkbox13Style() }
}

extension View {
  /// The system's rounded text field, in the app's body or monospaced font.
  func field(monospaced: Bool = false) -> some View {
    textFieldStyle(.roundedBorder).font(monospaced ? DS.mono : DS.body)
  }
}

// MARK: Tiles, badges and cards

/// The square that stands for a library, an app or a group: a tinted wash with the symbol in the tint.
struct Tile: View {
  let symbol: String
  let tint: Color
  var size: CGFloat = 36

  var body: some View {
    Image(systemName: symbol)
      .font(.system(size: size * 0.55))
      .foregroundStyle(tint)
      .frame(width: size, height: size)
      .background(tint.opacity(0.15), in: .rect(cornerRadius: size / 4))
      .accessibilityHidden(true)
  }
}

/// A small grey tag for a fact such as the package manager.
struct Badge: View {
  let text: String
  var kind = Chip.Kind.neutral

  var body: some View { Chip(text: text, kind: kind) }
}

/// Says whether an app runs a library's dev build or its released version.
struct BuildChip: View {
  let dev: Bool
  var body: some View { Chip(text: dev ? "Dev build" : "Release", kind: dev ? .dev : .release) }
}

extension View {
  /// A card in the menu: 10 pt corners and a hairline, 6 by 8 pt inside.
  func card() -> some View {
    padding(.horizontal, 8)
      .padding(.vertical, 6)
      .background(DS.groupFill, in: .rect(cornerRadius: DS.radius))
      .overlay { RoundedRectangle(cornerRadius: DS.radius).strokeBorder(DS.cardBorder, lineWidth: 0.5) }
  }
}

// MARK: Pages

/// A page of the dryfit window: the page, 18 pt in from the sides, scrolling under the window's
/// toolbar, which holds the page's actions.
struct Page<Bar: View, Content: View>: View {
  @ViewBuilder var bar: Bar
  @ViewBuilder var content: Content

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 0) { content }
        .font(DS.body)
        .padding(.horizontal, 18)
        .padding(.top, 8)
        .padding(.bottom, 16)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
    .toolbar {
      ToolbarSpacer(.flexible)
      ToolbarItemGroup { bar }
    }
    // The page's name is in the page, not repeated in the bar.
    .toolbar(removing: .title)
  }
}

/// The page's tile, name and one line about it.
struct PageHeader<Accessory: View>: View {
  let symbol: String
  let tint: Color
  let title: String
  let subtitle: String
  @ViewBuilder var accessory: Accessory

  var body: some View {
    HStack(spacing: 12) {
      Tile(symbol: symbol, tint: tint)
      VStack(alignment: .leading, spacing: 1) {
        HStack(spacing: 6) {
          Text(title).font(DS.title).textSelection(.enabled).lineLimit(1)
          accessory
        }
        Text(subtitle).font(DS.body).foregroundStyle(DS.muted).fixedSize(horizontal: false, vertical: true)
      }
    }
  }
}

extension PageHeader where Accessory == EmptyView {
  init(symbol: String, tint: Color, title: String, subtitle: String) {
    self.init(symbol: symbol, tint: tint, title: title, subtitle: subtitle) { EmptyView() }
  }
}

/// A page whose header stays where it is while the rest scrolls under it: the dryfit window's pages,
/// which can be long (a library used by thirty apps). A hairline appears under the header once content
/// has moved beneath it, so the edge reads as an edge only when something is there.
struct PinnedPage<Header: View, Content: View>: View {
  @ViewBuilder var header: Header
  @ViewBuilder var content: Content
  @State private var scrolled = false

  var body: some View {
    VStack(spacing: 0) {
      header
        .padding(.horizontal, 24)
        .padding(.top, 8)
        .padding(.bottom, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.background)
        .overlay(alignment: .bottom) { Hairline().opacity(scrolled ? 1 : 0) }
        .zIndex(1)
      ScrollView {
        VStack(alignment: .leading, spacing: 22) { content }
          .font(DS.body)
          .padding(.horizontal, 24)
          .padding(.top, 18)
          .padding(.bottom, 28)
          // Rows stay close to the name they belong to, however wide the window.
          .frame(maxWidth: 760, alignment: .leading)
          .frame(maxWidth: .infinity, alignment: .leading)
      }
      .onScrollGeometryChange(for: Bool.self) { $0.contentOffset.y + $0.contentInsets.top > 1 } action: { _, now in
        withAnimation(.easeOut(duration: 0.15)) { scrolled = now }
      }
    }
    // The page's name is in its header, not repeated in the toolbar.
    .toolbar(removing: .title)
  }
}

/// The pinned header of a page: its tile, name and chips, a line about it, and its actions at the far end.
struct PinnedHeader<Chips: View, Actions: View>: View {
  let symbol: String
  let tint: Color
  let title: String
  let subtitle: String
  /// A version, set in the monospaced face before the subtitle.
  var mono: String? = nil
  @ViewBuilder var chips: Chips
  @ViewBuilder var actions: Actions

  var body: some View {
    HStack(spacing: 14) {
      Tile(symbol: symbol, tint: tint, size: 44)
      VStack(alignment: .leading, spacing: 3) {
        HStack(spacing: 8) {
          Text(title).font(DS.title).textSelection(.enabled).lineLimit(1)
          chips
        }
        HStack(spacing: 6) {
          if let mono { Text(mono).font(DS.mono) }
          if mono != nil && !subtitle.isEmpty { Text("·") }
          Text(subtitle).font(DS.body).fixedSize(horizontal: false, vertical: true)
        }
        .foregroundStyle(DS.muted)
        .lineLimit(2)
      }
      Spacer(minLength: 12)
      HStack(spacing: 10) { actions }
    }
  }
}

/// A row's two lines with a badge after the name: "admin  pnpm".
struct NameAndBadge: View {
  let name: String
  let badge: String?

  var body: some View {
    HStack(spacing: 4) {
      Text(name).lineLimit(1)
      if let badge { Badge(text: badge) }
    }
  }
}
