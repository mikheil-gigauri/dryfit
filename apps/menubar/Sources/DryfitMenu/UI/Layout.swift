import SwiftUI

/// A CSS grid row: columns that are fixed, `auto` (the view's own width) or `fr` (a share of what is
/// left), with a gap between. Every child is one column, so a column that may be empty holds a clear
/// view rather than nothing.
struct Columns: Layout {
  enum Track { case fixed(CGFloat), auto, fr(CGFloat) }

  var tracks: [Track]
  var gap: CGFloat = 12

  private func widths(for width: CGFloat?, _ subviews: Subviews) -> [CGFloat] {
    let count = min(tracks.count, subviews.count)
    var result = [CGFloat](repeating: 0, count: count)
    var used = gap * CGFloat(max(count - 1, 0))
    var shares: CGFloat = 0
    for index in 0..<count {
      switch tracks[index] {
      case .fixed(let w): result[index] = w; used += w
      case .auto:
        let w = subviews[index].sizeThatFits(.unspecified).width
        result[index] = w
        used += w
      case .fr(let f): shares += f
      }
    }
    for index in 0..<count {
      if case .fr(let f) = tracks[index] {
        if let width {
          result[index] = max(0, width - used) * f / max(shares, 0.0001)
        } else {
          result[index] = subviews[index].sizeThatFits(.unspecified).width
        }
      }
    }
    return result
  }

  func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
    let w = widths(for: proposal.width, subviews)
    var height: CGFloat = 0
    for index in w.indices {
      height = max(height, subviews[index].sizeThatFits(ProposedViewSize(width: w[index], height: nil)).height)
    }
    let total = w.reduce(0, +) + gap * CGFloat(max(w.count - 1, 0))
    return CGSize(width: proposal.width ?? total, height: height)
  }

  func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
    let w = widths(for: bounds.width, subviews)
    var x = bounds.minX
    for index in w.indices {
      let size = subviews[index].sizeThatFits(ProposedViewSize(width: w[index], height: nil))
      subviews[index].place(
        at: CGPoint(x: x, y: bounds.midY - size.height / 2), anchor: .topLeading,
        proposal: ProposedViewSize(width: w[index], height: size.height))
      x += w[index] + gap
    }
  }
}

/// A row of a card (`.tr`): its columns, with the mockup's padding.
struct Tr<Content: View>: View {
  let tracks: [Columns.Track]
  var vertical: CGFloat = 9
  var horizontal: CGFloat = 14
  @ViewBuilder var content: Content

  var body: some View {
    Columns(tracks: tracks) { content }
      .padding(.horizontal, horizontal)
      .padding(.vertical, vertical)
      .frame(maxWidth: .infinity, alignment: .leading)
  }
}

/// A cell that is always one column: its content leading, or nothing at all.
struct Cell<Content: View>: View {
  var alignment = Alignment.leading
  @ViewBuilder var content: Content
  var body: some View { ZStack(alignment: alignment) { content }.frame(maxWidth: .infinity, alignment: alignment) }
}

/// A card of rows (`.tbl`), a hairline between them.
struct Tbl<Content: View>: View {
  var fill: Color = Theme.card
  @ViewBuilder var content: Content

  var body: some View {
    VStack(spacing: 0) {
      Group(subviews: content) { subviews in
        ForEach(subviews) { sub in
          if sub.id != subviews.first?.id { Hair() }
          sub
        }
      }
    }
    .frame(maxWidth: .infinity)
    .background(fill)
    .clipShape(.rect(cornerRadius: Theme.cardRadius))
    .overlay { RoundedRectangle(cornerRadius: Theme.cardRadius).strokeBorder(Theme.cardBorder, lineWidth: 0.5) }
  }
}

/// The name of a row over its grey second line.
struct RowTitle: View {
  let title: String
  var caption: String? = nil
  var weight = Font.Weight.semibold
  var lineLimit = 1

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      Text(title).font(.system(size: 13, weight: weight)).lineLimit(lineLimit).truncationMode(.middle).lh(13)
      if let caption { Text(caption).muted().lineLimit(1).truncationMode(.middle) }
    }
  }
}

/// A section's title (`h3`): its name, a count, and at the far end something to do with it.
struct SectionTitle<Trailing: View>: View {
  let title: String
  var count: Int? = nil
  @ViewBuilder var trailing: Trailing

  var body: some View {
    HStack(spacing: 8) {
      Text(title).font(.system(size: 13, weight: .semibold)).lh(13)
      if let count { Tag(text: "\(count)") }
      Spacer(minLength: 8)
      trailing.font(.system(size: 12, weight: .medium)).foregroundStyle(Theme.accent)
    }
    .padding(.bottom, 8)
  }
}

extension SectionTitle where Trailing == EmptyView {
  init(_ title: String, count: Int? = nil) { self.init(title: title, count: count) { EmptyView() } }
}

/// The grey note under a card (`.hint`).
struct Hint: View {
  let text: String
  init(_ text: String) { self.text = text }
  var body: some View { Text(text).muted().fixedSize(horizontal: false, vertical: true).padding(.top, 6) }
}

/// A rarely used action at the foot of a page (`.danger`).
struct Danger: View {
  let title: String
  let detail: String
  let button: String
  var enabled = true
  let action: () -> Void

  var body: some View {
    HStack(spacing: 12) {
      VStack(alignment: .leading, spacing: 0) {
        Text(title).font(Theme.bodySemibold).lh(13)
        Text(detail).muted().fixedSize(horizontal: false, vertical: true)
      }
      Spacer(minLength: 8)
      Button(button, action: action).buttonStyle(.flat(.bad)).disabled(!enabled)
    }
    .padding(.horizontal, 14)
    .padding(.vertical, 12)
    .overlay { RoundedRectangle(cornerRadius: Theme.cardRadius).strokeBorder(Theme.cardBorder, lineWidth: 1) }
  }
}

/// A failure or a warning at the top of a page (`.err`): a title, a line under it, the output that
/// says why, and the buttons for it.
struct Notice<Actions: View>: View {
  enum Kind { case bad, warn }

  let kind: Kind
  let title: String
  var subtitle: String? = nil
  var output: String? = nil
  @ViewBuilder var actions: Actions

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      HStack(spacing: 10) {
        StatusGlyph(kind: kind == .bad ? .failed : .warning, size: 18)
        VStack(alignment: .leading, spacing: 2) {
          Text(title).font(.system(size: 14, weight: .semibold)).lh(14)
          if let subtitle { Text(subtitle).muted() }
        }
        Spacer(minLength: 8)
        HStack(spacing: 8) { actions }
      }
      .padding(.horizontal, 14)
      .padding(.vertical, 12)
      if let output, !output.isEmpty {
        Text(output)
          .font(Theme.mono)
          .lineSpacing(3)
          .foregroundStyle(Theme.muted)
          .textSelection(.enabled)
          .frame(maxWidth: .infinity, alignment: .leading)
          .padding(.horizontal, 11)
          .padding(.vertical, 9)
          .background(Theme.code, in: .rect(cornerRadius: 8))
          .padding(.horizontal, 14)
          .padding(.bottom, 12)
      }
    }
    .background(kind == .bad ? Theme.badTint : Theme.warnTint, in: .rect(cornerRadius: Theme.cardRadius))
    .overlay {
      RoundedRectangle(cornerRadius: Theme.cardRadius)
        .strokeBorder(kind == .bad ? Theme.badBorder : Theme.warnBorder, lineWidth: 1)
    }
  }
}

/// A one-line title for a centred state of the window (`.center`).
struct Center<Actions: View>: View {
  let glyph: AnyView
  let title: String
  var text: String? = nil
  @ViewBuilder var actions: Actions

  var body: some View {
    VStack(spacing: 6) {
      glyph.padding(.bottom, 4)
      Text(title).font(.system(size: 16, weight: .semibold)).lh(16)
      if let text {
        Text(text).foregroundStyle(Theme.muted).multilineTextAlignment(.center).frame(maxWidth: 290)
          .fixedSize(horizontal: false, vertical: true).lh(13)
      }
      actions
    }
    .frame(maxWidth: .infinity, minHeight: 420)
  }
}
