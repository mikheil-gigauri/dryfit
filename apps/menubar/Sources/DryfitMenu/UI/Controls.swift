import SwiftUI

/// The mockup's `.btn`: a flat 7 pt-radius button with a grey wash, one text weight, no border. Small
/// is the 12 pt one used inside rows; regular is 13 pt.
struct FlatButtonStyle: ButtonStyle {
  enum Kind { case normal, primary, accent, bad, muted, plain }

  var kind = Kind.normal
  var small = false
  /// The button of a centred message: a little more room around its label.
  var roomy = false
  /// Working on it: a spinner before the label, and no more clicks.
  var busy = false
  /// A button in the bar of a sheet: a little wider than the rest.
  var bar = false

  func makeBody(configuration: Configuration) -> some View {
    FlatLabel(configuration: configuration, kind: kind, small: small, roomy: roomy, busy: busy, bar: bar)
  }

  struct FlatLabel: View {
    let configuration: Configuration
    let kind: Kind
    let small: Bool
    let roomy: Bool
    let busy: Bool
    let bar: Bool
    @State private var hovering = false
    @Environment(\.isEnabled) private var enabled

    var body: some View {
      HStack(spacing: 6) {
        if busy {
          Spin(size: 11, tint: kind == .primary ? .white : Theme.accent, track: kind == .primary ? .white.opacity(0.35) : Theme.buttonHover)
        }
        configuration.label
      }
        .font(.system(size: small ? 12 : 13, weight: .medium))
        .lineLimit(1)
        .frame(minHeight: (small ? 12 : 13) * 1.4)
        .foregroundStyle(foreground)
        .padding(.horizontal, roomy ? 16 : bar ? 14 : small ? 9 : 11)
        .padding(.vertical, roomy ? 6 : bar ? 5 : small ? 3 : 4)
        .background(background, in: .rect(cornerRadius: Theme.buttonRadius))
        .fixedSize()
        .opacity(enabled ? (busy ? 0.8 : 1) : 0.45)
        .allowsHitTesting(!busy)
        .contentShape(.rect(cornerRadius: Theme.buttonRadius))
        .onHover { hovering = $0 }
    }

    private var lit: Bool { hovering || configuration.isPressed }

    private var foreground: Color {
      switch kind {
      case .normal, .plain: Theme.text
      case .primary: .white
      case .accent: Theme.accent
      case .bad: Theme.bad
      case .muted: Theme.muted
      }
    }

    private var background: Color {
      switch kind {
      case .primary: Theme.accent.opacity(lit ? 0.85 : 1)
      case .plain: lit ? Theme.button : .clear
      default: lit ? Theme.buttonHover : Theme.button
      }
    }
  }
}

extension ButtonStyle where Self == FlatButtonStyle {
  static var flat: FlatButtonStyle { FlatButtonStyle() }
  static func flat(_ kind: FlatButtonStyle.Kind = .normal, small: Bool = false, busy: Bool = false, bar: Bool = false) -> FlatButtonStyle {
    FlatButtonStyle(kind: kind, small: small, busy: busy, bar: bar)
  }
}

/// The mockup's `.sw`: a 30 × 18 capsule with a white knob, green when on.
struct DrySwitch: View {
  @Binding var isOn: Bool
  let label: String

  var body: some View {
    Button { isOn.toggle() } label: {
      ZStack(alignment: isOn ? .trailing : .leading) {
        Capsule().fill(isOn ? Theme.ok : Theme.buttonHover)
        Circle().fill(.white).frame(width: 14, height: 14).shadow(color: .black.opacity(0.3), radius: 1, y: 1).padding(2)
      }
      .frame(width: 30, height: 18)
      .animation(.easeOut(duration: 0.15), value: isOn)
      .contentShape(.capsule)
    }
    .buttonStyle(.plain)
    .accessibilityRepresentation { Toggle(label, isOn: $isOn) }
  }
}

/// The mockup's `.chip`: an 18 pt pill with 11 pt semibold text.
struct Tag: View {
  enum Kind { case neutral, dev, release, bad, warn, ok }

  let text: String
  var kind = Kind.neutral
  var size: CGFloat = 11
  var inset: CGFloat = 8

  var body: some View {
    Text(text)
      .font(.system(size: size, weight: .semibold))
      .lineLimit(1)
      .foregroundStyle(foreground)
      .padding(.horizontal, inset)
      .frame(height: 18)
      .background(background, in: .capsule)
      .fixedSize()
  }

  private var foreground: Color {
    switch kind {
    case .neutral: Theme.muted
    case .dev: Theme.dev
    case .release: Theme.release
    case .bad: Theme.bad
    case .warn: Theme.warn
    case .ok: Theme.okText
    }
  }

  private var background: Color {
    switch kind {
    case .neutral: Theme.button
    case .dev: Theme.devTint
    case .release: Theme.releaseTint
    case .bad: Theme.badTint
    case .warn: Theme.warnTint
    case .ok: Theme.okTint
    }
  }
}

/// The mockup's `.dot`: an 8 pt circle in a state colour, with the state in words beside it.
struct Dot: View {
  let color: Color
  var body: some View { Circle().fill(color).frame(width: 8, height: 8).accessibilityHidden(true) }
}

/// The mockup's `.spin`: a 12 pt ring with an accent arc that turns.
struct Spin: View {
  var size: CGFloat = 12
  var tint: Color = Theme.accent
  var track: Color = Theme.buttonHover

  var body: some View {
    TimelineView(.animation) { context in
      let turn = context.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 0.8) / 0.8
      ZStack {
        Circle().stroke(track, lineWidth: 2)
        Circle().trim(from: 0, to: 0.25).stroke(tint, style: StrokeStyle(lineWidth: 2, lineCap: .butt))
          .rotationEffect(.degrees(turn * 360 - 90))
      }
    }
    .frame(width: size, height: size)
    .accessibilityHidden(true)
  }
}

/// A one-point rule in the hairline colour.
struct Hair: View {
  var body: some View { Rectangle().fill(Theme.hairline).frame(height: 1) }
}

/// The mockup's `.more`: three faint dots that open a menu.
struct MoreMenu<Content: View>: View {
  var label = "More"
  @ViewBuilder var content: Content
  @State private var hovering = false

  var body: some View {
    Menu {
      content
    } label: {
      Text("···")
        .font(.system(size: 13, weight: .bold))
        .tracking(1)
        .foregroundStyle(Theme.faint)
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(hovering ? Theme.button : .clear, in: .rect(cornerRadius: 6))
    }
    .menuStyle(.button)
    .buttonStyle(.plain)
    .menuIndicator(.hidden)
    .fixedSize()
    .onHover { hovering = $0 }
    .accessibilityLabel(label)
  }
}

/// The mockup's `.field`: a rounded well for text, with an optional leading icon.
struct Well<Content: View>: View {
  enum Style { case plain, input, error }

  var style = Style.plain
  @ViewBuilder var content: Content

  var body: some View {
    HStack(spacing: 6) { content }
      .font(.system(size: 12.5))
      .padding(.horizontal, 9)
      .padding(.vertical, 5)
      .background(style == .plain ? Theme.button : Theme.card, in: .rect(cornerRadius: 8))
      .overlay {
        switch style {
        case .plain: EmptyView()
        case .input: RoundedRectangle(cornerRadius: 8).strokeBorder(Theme.cardBorder, lineWidth: 1)
        case .error: RoundedRectangle(cornerRadius: 8).strokeBorder(Theme.bad, lineWidth: 1.5)
        }
      }
  }
}

extension View {
  /// A card as the mockup draws it: white (or the dark card grey), a half-point edge.
  func card(radius: CGFloat = Theme.cardRadius, fill: Color = Theme.card) -> some View {
    background(fill, in: .rect(cornerRadius: radius))
      .overlay { RoundedRectangle(cornerRadius: radius).strokeBorder(Theme.cardBorder, lineWidth: 0.5) }
  }
}

/// A button that opens a menu, drawn as the flat button with a small triangle after its name (`Link library ▾`).
struct MenuButton<Content: View>: View {
  let title: String
  var small = false
  @ViewBuilder var content: Content

  var body: some View {
    Menu {
      content
    } label: {
      Text("\(title) ▾")
    }
    .menuStyle(.button)
    .buttonStyle(FlatButtonStyle(small: small))
    .menuIndicator(.hidden)
    .fixedSize()
  }
}

/// A failure to act on, with a way to dismiss it: the message in a red card.
struct ActionError: View {
  let message: String
  let dismiss: () -> Void

  var body: some View {
    HStack(alignment: .top, spacing: 10) {
      StatusGlyph(kind: .failed, size: 16).padding(.top, 1)
      Text(message).textSelection(.enabled).fixedSize(horizontal: false, vertical: true).frame(maxWidth: .infinity, alignment: .leading)
      Button("Dismiss", action: dismiss).buttonStyle(.flat(small: true))
    }
    .padding(.horizontal, 14)
    .padding(.vertical, 10)
    .background(Theme.badTint, in: .rect(cornerRadius: Theme.cardRadius))
    .overlay { RoundedRectangle(cornerRadius: Theme.cardRadius).strokeBorder(Theme.badBorder, lineWidth: 1) }
  }
}

/// The mockup's `.cb`: a 15 pt checkbox, an accent square with a tick when on.
struct Check: View {
  @Binding var isOn: Bool
  let label: String

  var body: some View {
    Button { isOn.toggle() } label: {
      ZStack {
        if isOn {
          RoundedRectangle(cornerRadius: 4).fill(Theme.accent)
          Text("✓").font(.system(size: 10, weight: .bold)).foregroundStyle(.white)
        } else {
          RoundedRectangle(cornerRadius: 4).strokeBorder(Theme.faint, lineWidth: 1)
        }
      }
      .frame(width: 15, height: 15)
      .contentShape(.rect)
    }
    .buttonStyle(.plain)
    .accessibilityRepresentation { Toggle(label, isOn: $isOn) }
  }
}
