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

/// A centred message: a symbol, a title, a line of text and the one thing to do.
private struct Centered<Actions: View>: View {
  let symbol: String
  var tint: Color? = nil
  let title: String
  let text: String
  @ViewBuilder var actions: Actions

  var body: some View {
    VStack(spacing: 0) {
      Image(systemName: symbol)
        .font(.system(size: 30))
        .foregroundStyle(tint.map(AnyShapeStyle.init) ?? AnyShapeStyle(DS.muted))
        .accessibilityHidden(true)
      Text(title).font(DS.headline).multilineTextAlignment(.center).padding(.top, 8).padding(.bottom, 4)
      Text(text).font(DS.body).foregroundStyle(DS.muted).multilineTextAlignment(.center)
        .fixedSize(horizontal: false, vertical: true)
      actions
    }
    .frame(maxWidth: .infinity)
    .padding(.horizontal, 24)
    .padding(.vertical, 24)
  }
}

/// Restoring was refused because the app's package.json changed since it was linked.
struct DriftedRestoreBanner: View {
  let request: RestoreRequest
  let model: MenuModel

  var body: some View {
    Callout(
      condition: .warning, title: "\(projectName(request.consumer))'s package.json changed",
      message: "Restoring puts back the version from before linking, and drops those changes."
    ) {
      Button("Cancel") { model.driftedRestore = nil }.buttonStyle(.pill)
      Button("Restore anyway") {
        Task { await model.restore(request.consumer, library: request.library, force: true) }
      }
      .buttonStyle(.dangerPill)
    }
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

/// dryfit's service is not running: start it, or install the CLI it runs from.
struct ServiceUnavailableView: View {
  let model: MenuModel
  let actions: MenuActions
  var compact = false

  var body: some View {
    Centered(
      symbol: model.cliMissing ? "arrow.down.circle" : "power",
      title: model.cliMissing ? "Install dryfit" : "dryfit is not running", text: explanation
    ) {
      VStack(spacing: 0) {
        if model.connection == .starting {
          ProgressView().controlSize(.small).padding(.top, 12)
          Text("Starting…").font(DS.caption).foregroundStyle(DS.muted).padding(.top, 6)
        } else if model.isBusy(.installCLI) {
          ProgressView().controlSize(.small).padding(.top, 12)
          Text("Installing with npm…").font(DS.caption).foregroundStyle(DS.muted).padding(.top, 6)
        } else if model.cliMissing {
          Button("Install dryfit") { Task { await model.installCLI() } }
            .buttonStyle(.primaryPill)
            .padding(.top, 12)
          Text("Runs \(DaemonLauncher.installCommand)").font(DS.caption).foregroundStyle(DS.muted).padding(.top, 6)
        } else {
          Button("Start dryfit") { Task { await model.startDaemon() } }
            .buttonStyle(.primaryPill)
            .padding(.top, 12)
        }
        // Shown while the CLI is missing too: a failed install would otherwise just offer the button
        // again, with no word of why.
        if let error = model.startError, !model.isBusy(.installCLI) {
          Text(error)
            .font(DS.caption)
            .foregroundStyle(.red)
            .multilineTextAlignment(.center)
            .textSelection(.enabled)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.top, 8)
          Group {
            if model.cliMissing {
              Button("Copy install command") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(DaemonLauncher.installCommand, forType: .string)
              }
            } else {
              Button("Open log", action: actions.openLog)
            }
          }
          .buttonStyle(.plain)
          .font(DS.caption)
          .foregroundStyle(Color.accentColor)
          .padding(.top, 4)
        }
      }
    }
    .frame(maxWidth: compact ? .infinity : 380)
  }

  private var explanation: String {
    if model.cliMissing {
      return "The app runs dryfit's command-line tool in the background. It needs Node.js and npm."
    }
    return "Start it to publish your libraries and install them into your apps."
  }
}

struct IncompatibleView: View {
  let model: MenuModel
  let actions: MenuActions
  let daemonVersion: String

  var body: some View {
    Centered(
      symbol: "exclamationmark.triangle", tint: .orange,
      title: "This app and dryfit \(daemonVersion) don't match", text: explanation
    ) {
      if model.outdatedVersion != nil {
        UpdateDryfitControl(model: model, prominent: true).padding(.top, 12)
      } else if model.appIsOlder, let checkForUpdates = actions.checkForUpdates {
        Button("Check for updates…", action: checkForUpdates)
          .buttonStyle(.primaryPill)
          .padding(.top, 12)
      }
    }
  }

  private var explanation: String {
    if model.outdatedVersion != nil { return "dryfit is the older one." }
    if model.appIsOlder { return "This app is the older one." }
    return "They speak different versions of dryfit's API. Update the one that is older."
  }
}

/// Updates dryfit with npm and restarts it, showing progress and, when it fails, why.
struct UpdateDryfitControl: View {
  let model: MenuModel
  let prominent: Bool

  var body: some View {
    VStack(alignment: prominent ? .center : .trailing, spacing: 0) {
      if model.isBusy(.updateCLI) {
        ProgressView().controlSize(.small)
        if prominent {
          Text("Updating with npm…").font(DS.caption).foregroundStyle(DS.muted).padding(.top, 6)
        }
      } else if prominent {
        Button("Update dryfit") { Task { await model.updateCLI() } }
          .buttonStyle(.primaryPill)
        Text("Runs npm install --global @dryfit/cli@latest")
          .font(DS.caption)
          .foregroundStyle(DS.muted)
          .multilineTextAlignment(.center)
          .padding(.top, 6)
      } else {
        Button("Update") { Task { await model.updateCLI() } }
          .buttonStyle(.pill)
          .help("Runs npm install --global @dryfit/cli@latest, then restarts dryfit")
      }
      if let error = model.updateError {
        Text(error)
          .font(DS.caption)
          .foregroundStyle(.red)
          .multilineTextAlignment(prominent ? .center : .trailing)
          .textSelection(.enabled)
          .fixedSize(horizontal: false, vertical: true)
          .padding(.top, 6)
      }
    }
  }
}
