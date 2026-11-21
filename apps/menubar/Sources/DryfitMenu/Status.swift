import DryfitAPI
import SwiftUI

extension DS {
  /// A colour that differs by appearance. The system's own red, orange and green are fills; as 12 pt
  /// text on a light card they measure under 4.5:1, so text uses these.
  static func dynamic(_ name: String, light: NSColor, dark: NSColor) -> Color {
    Color(
      nsColor: NSColor(name: NSColor.Name(name)) { appearance in
        switch appearance.bestMatch(from: [.aqua, .darkAqua]) {
        case .darkAqua: dark
        default: light
        }
      })
  }

  static let okText = dynamic("dryfitOkText", light: NSColor(red: 0.12, green: 0.54, blue: 0.25, alpha: 1), dark: NSColor(red: 0.36, green: 0.86, blue: 0.52, alpha: 1))
  static let badText = dynamic("dryfitBadText", light: NSColor(red: 0.78, green: 0.16, blue: 0.12, alpha: 1), dark: NSColor(red: 1, green: 0.42, blue: 0.38, alpha: 1))
  static let warnText = dynamic("dryfitWarnText", light: NSColor(red: 0.66, green: 0.36, blue: 0, alpha: 1), dark: NSColor(red: 1, green: 0.70, blue: 0.25, alpha: 1))
  /// The brand's magenta (a dev build) and teal (a release), darkened on light backgrounds to read as text.
  static let devText = dynamic("dryfitDevText", light: NSColor(red: 0.84, green: 0.19, blue: 0.50, alpha: 1), dark: NSColor(red: 1, green: 0.42, blue: 0.66, alpha: 1))
  static let releaseText = dynamic("dryfitReleaseText", light: NSColor(red: 0.07, green: 0.50, blue: 0.44, alpha: 1), dark: NSColor(red: 0.25, green: 0.82, blue: 0.71, alpha: 1))
  /// 13 pt semibold, for the title of a section of a page.
  static let section = Font.system(size: 13, weight: .semibold)
  /// The name in a row: the same size as the row's other text, a weight heavier.
  static let rowTitle = Font.system(size: 13, weight: .semibold)
}

/// How something is doing (named apart from the API's `Status` and `Health`). Each state has a symbol, a colour and a word, so colour is never the only cue.
enum Condition: CaseIterable, Equatable {
  case ok, failed, pending, warning, update

  var symbol: String {
    switch self {
    case .ok: "checkmark.circle.fill"
    case .failed: "xmark.circle.fill"
    case .pending: "clock"
    case .warning: "exclamationmark.triangle.fill"
    case .update: "arrow.up.circle.fill"
    }
  }

  var tint: Color {
    switch self {
    case .ok: .green
    case .failed: .red
    case .pending: DS.muted
    case .warning, .update: .orange
    }
  }

  /// What assistive technology says for the symbol.
  var label: String {
    switch self {
    case .ok: "Installed"
    case .failed: "Failed"
    case .pending: "Waiting"
    case .warning: "Needs attention"
    case .update: "Update available"
    }
  }
}

extension DryfitAPI.Link {
  var condition: Condition {
    switch status {
    case .installed: .ok
    case .pending: .pending
    case .failed: .failed
    }
  }
}

/// A status as a symbol in a fixed square. The symbol is drawn at the size it is given and never
/// scales down with its neighbours, so a row of them lines up and none is smaller than the rest.
struct StatusIcon: View {
  let condition: Condition
  var size: CGFloat = 16

  var body: some View {
    Image(systemName: condition.symbol)
      .font(.system(size: size, weight: .regular))
      .symbolRenderingMode(.monochrome)
      .foregroundStyle(condition.tint)
      .frame(width: size + 2, height: size + 2)
      .accessibilityLabel(condition.label)
  }
}

/// A small filled circle for a state shown in running text ("Running · 1 needs attention"); the words
/// beside it say what it means, so it is hidden from assistive technology.
struct StatusDot: View {
  let color: Color
  var size: CGFloat = 8

  var body: some View {
    Circle().fill(color).frame(width: size, height: size).accessibilityHidden(true)
  }
}

/// A small pill for a fact: "DEV", "Release", "pnpm", a count.
struct Chip: View {
  enum Kind { case neutral, dev, release, ok, warning, failed }

  let text: String
  var kind = Kind.neutral
  var symbol: String? = nil

  var body: some View {
    HStack(spacing: 3) {
      if let symbol { Image(systemName: symbol).font(.system(size: 9, weight: .bold)).accessibilityHidden(true) }
      Text(text).lineLimit(1)
    }
    .font(.system(size: 11, weight: .semibold))
    .padding(.horizontal, 8)
    .padding(.vertical, 1.5)
    .foregroundStyle(foreground)
    .background(background, in: .capsule)
    .fixedSize()
  }

  private var foreground: Color {
    switch kind {
    case .neutral: DS.muted
    case .dev: DS.devText
    case .release: DS.releaseText
    case .ok: DS.okText
    case .warning: DS.warnText
    case .failed: DS.badText
    }
  }

  private var background: Color {
    kind == .neutral ? DS.neutralFill : foreground.opacity(0.14)
  }
}

/// The title of a section of a page, with a count and, at the far end, something to do with it.
struct SectionHeader<Trailing: View>: View {
  let title: String
  var count: Int? = nil
  @ViewBuilder var trailing: Trailing

  var body: some View {
    HStack(spacing: 8) {
      Text(title).font(DS.section)
      if let count { Chip(text: "\(count)") }
      Spacer(minLength: 8)
      trailing.font(DS.caption)
    }
    .padding(.bottom, 8)
  }
}

extension SectionHeader where Trailing == EmptyView {
  init(_ title: String, count: Int? = nil) {
    self.init(title: title, count: count) { EmptyView() }
  }
}

/// A message that sits above what it is about: a failure, or a warning that needs an answer. It has a
/// symbol and a title as well as its colour, an optional line under the title, and its actions.
struct Callout<Actions: View>: View {
  var condition = Condition.failed
  var title: String? = nil
  var message: String? = nil
  /// The line under the title is output, such as a build error: monospaced and cut to two lines.
  var output = false
  let hasActions: Bool
  /// The actions sit at the end of the title's row, not under the text.
  var actionsAtEnd = false
  @ViewBuilder var actions: Actions

  init(
    condition: Condition = .failed, title: String? = nil, message: String? = nil, output: Bool = false,
    actionsAtEnd: Bool = false, @ViewBuilder actions: () -> Actions
  ) {
    self.actionsAtEnd = actionsAtEnd
    self.condition = condition
    self.title = title
    self.message = message
    self.output = output
    self.hasActions = true
    self.actions = actions()
  }

  private var tint: Color { condition == .failed ? .red : condition == .ok ? .green : .orange }

  var body: some View {
    HStack(alignment: .top, spacing: 10) {
      StatusIcon(condition: condition, size: 15).padding(.top, 1)
      VStack(alignment: .leading, spacing: 3) {
        if let title { Text(title).font(DS.rowTitle).fixedSize(horizontal: false, vertical: true) }
        if let message {
          Text(message)
            .font(output ? DS.mono : (title == nil ? DS.body : DS.caption))
            .foregroundStyle(title == nil ? AnyShapeStyle(.primary) : AnyShapeStyle(DS.muted))
            .lineLimit(output ? 2 : nil)
            .fixedSize(horizontal: false, vertical: true)
            .textSelection(.enabled)
        }
        if hasActions && !actionsAtEnd { HStack(spacing: 6) { actions }.padding(.top, 6) }
      }
      .frame(maxWidth: .infinity, alignment: .leading)
      if hasActions && actionsAtEnd { HStack(spacing: 6) { actions } }
    }
    .padding(.horizontal, 12)
    .padding(.vertical, 10)
    .background(tint.opacity(0.09), in: .rect(cornerRadius: 12))
    .overlay { RoundedRectangle(cornerRadius: 12).strokeBorder(tint.opacity(0.28), lineWidth: 1) }
  }
}

extension Callout where Actions == EmptyView {
  init(condition: Condition = .failed, title: String? = nil, message: String? = nil, output: Bool = false) {
    self.condition = condition
    self.title = title
    self.message = message
    self.output = output
    self.hasActions = false
    self.actions = EmptyView()
  }
}
