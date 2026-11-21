import DryfitAPI
import SwiftUI

/// What the menu asks of the app around it: the log, login, updates, quitting.
public struct MenuActions {
  public var openLog: () -> Void
  public var showFailures: (Failure.ID?) -> Void
  public var quit: () -> Void
  /// Nil when the app cannot be a login item (run outside its bundle).
  public var openAtLogin: Binding<Bool>?
  /// Nil when the app does not update itself (run outside its bundle, or built without an update key).
  public var checkForUpdates: (() -> Void)?
  /// Whether updates install by themselves; nil when the app does not update itself.
  public var installUpdatesAutomatically: Binding<Bool>?

  public init(
    openLog: @escaping () -> Void = {}, showFailures: @escaping (Failure.ID?) -> Void = { _ in },
    quit: @escaping () -> Void = {}, openAtLogin: Binding<Bool>? = nil,
    checkForUpdates: (() -> Void)? = nil, installUpdatesAutomatically: Binding<Bool>? = nil
  ) {
    self.openLog = openLog
    self.showFailures = showFailures
    self.quit = quit
    self.openAtLogin = openAtLogin
    self.checkForUpdates = checkForUpdates
    self.installUpdatesAutomatically = installUpdatesAutomatically
  }
}

/// "dev 14:32" for "1.4.1 · dev 14:32": the menu is narrow, and the window has the rest.
func shortVersion(_ described: String) -> String {
  guard let range = described.range(of: " · dev ") else { return described }
  return "dev " + described[range.upperBound...]
}


/// Lays its views out in rows, wrapping to a new row when the next one does not fit.
struct FlowLayout: Layout {
  var spacing: CGFloat = 4

  func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
    let rows = rows(width: proposal.width ?? .infinity, subviews: subviews)
    let height = rows.map(\.height).reduce(0, +) + spacing * CGFloat(max(rows.count - 1, 0))
    return CGSize(width: proposal.width ?? rows.map(\.width).max() ?? 0, height: height)
  }

  func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
    var y = bounds.minY
    for row in rows(width: bounds.width, subviews: subviews) {
      var x = bounds.minX
      for index in row.indices {
        let proposal = Self.proposal(for: subviews[index], width: bounds.width)
        let size = subviews[index].sizeThatFits(proposal)
        subviews[index].place(at: CGPoint(x: x, y: y + (row.height - size.height) / 2), proposal: proposal)
        x += size.width + spacing
      }
      y += row.height + spacing
    }
  }

  private func rows(width: CGFloat, subviews: Subviews) -> [(indices: [Int], width: CGFloat, height: CGFloat)] {
    var rows: [(indices: [Int], width: CGFloat, height: CGFloat)] = []
    var current: (indices: [Int], width: CGFloat, height: CGFloat) = ([], 0, 0)
    for index in subviews.indices {
      let size = subviews[index].sizeThatFits(Self.proposal(for: subviews[index], width: width))
      let needed = current.indices.isEmpty ? size.width : current.width + spacing + size.width
      if needed > width, !current.indices.isEmpty {
        rows.append(current)
        current = ([index], size.width, size.height)
      } else {
        current = (current.indices + [index], needed, max(current.height, size.height))
      }
    }
    if !current.indices.isEmpty { rows.append(current) }
    return rows
  }

  /// Its ideal size, or the row's width when that is less, so a long name truncates instead of
  /// running out of the card.
  private static func proposal(for subview: LayoutSubview, width: CGFloat) -> ProposedViewSize {
    subview.sizeThatFits(.unspecified).width > width ? ProposedViewSize(width: width, height: nil) : .unspecified
  }
}
