import DryfitAPI
import SwiftUI

/// A failed install, first among what a page shows: what failed, the first line of why, and the two
/// ways on: read the output, or put the app back.
struct InstallFailedCallout: View {
  let link: DryfitAPI.Link
  let model: MenuModel
  let actions: MenuActions

  var body: some View {
    let failure = model.installFailure(in: link.consumer)
    let busy = model.isBusy(.restore(link.consumer, link.library))
    Callout(
      condition: .failed, title: "Install into \(projectName(link.consumer)) failed",
      message: failure?.detail.split(whereSeparator: \.isNewline).first.map(String.init), output: true
    ) {
      if let failure { Button("Show output") { actions.showFailures(failure.id) }.buttonStyle(.pill) }
      Button("Restore \(projectName(link.consumer))") {
        Task { await model.restore(link.consumer, library: link.library) }
      }
      .buttonStyle(.pill(busy: busy))
      .disabled(!busy && model.isRestoring(link.consumer))
      .help("Put \(projectName(link.consumer)) back on the release of \(link.library)")
    }
  }
}

/// An app linked to a library: how it is doing, what it runs, and the way back to the release. The
/// status and version sit in columns so a long list reads down.
struct LinkedAppRow: View {
  let link: DryfitAPI.Link
  let model: MenuModel
  @Environment(\.timeZone) private var timeZone

  var body: some View {
    GroupRow {
      StatusIcon(condition: link.condition)
      TwoLine(title: projectName(link.consumer), caption: caption)
        .frame(maxWidth: .infinity, alignment: .leading)
        .layoutPriority(1)
      statusChip.frame(width: 124, alignment: .leading)
      Text(version).font(DS.mono).foregroundStyle(link.status == .installed ? Color.primary : DS.muted)
        .lineLimit(1).frame(width: 104, alignment: .leading)
      Button("Restore") { Task { await model.restore(link.consumer, library: link.library) } }
        .buttonStyle(.pill(busy: busy))
        .disabled(!busy && model.isRestoring(link.consumer))
        .help("Put \(projectName(link.consumer)) back on the release of \(link.library)")
    }
    .contentShape(.rect)
    .help(abbreviatedPath(link.consumer))
    .contextMenu { Button("Show in Finder") { revealInFinder(link.consumer) } }
  }

  private var busy: Bool { model.isBusy(.restore(link.consumer, link.library)) }

  @ViewBuilder private var statusChip: some View {
    switch link.status {
    case .failed: Chip(text: "Install failed", kind: .failed)
    case .pending: Chip(text: "Waiting for a sync")
    case .installed: Chip(text: "Dev build", kind: .dev)
    }
  }

  /// "1.4.1 · 14:32" for an installed dev build.
  private var version: String {
    guard link.status == .installed, let installed = link.installedVersion else { return "—" }
    return DevVersion.describe(installed, timeZone: timeZone).replacingOccurrences(of: " · dev ", with: " · ")
  }

  private var caption: String {
    let manager = model.consumers.first { $0.root == link.consumer }?.packageManager.name
    let guarded = link.status == .installed && link.guarded == true
    return ([manager, abbreviatedPath(link.consumer)].compactMap { $0 }).joined(separator: " · ")
      + (guarded ? " · commit guard on" : "")
  }
}

/// How an app's package.json asks for a library, as a chip: "Release ^1.3.0" for a version range from
/// the registry, otherwise what it says plainly ("Local folder ui").
func dependencyChip(_ range: String?) -> Chip {
  guard let range else { return Chip(text: "Release", kind: .release) }
  let described = describeDependency(range)
  return described.hasSuffix("from the registry")
    ? Chip(text: "Release \(range)", kind: .release) : Chip(text: described)
}

/// The apps that use a library and are not linked to it: five to start with, a search once there are
/// more, and "Show N more" for the rest. Thirty apps stay a short list.
struct AvailableAppsSection: View {
  let library: String
  let candidates: [DiscoveredConsumer]
  let model: MenuModel
  @State private var query = ""
  @State private var showAll = false

  private static let initiallyShown = 5

  var body: some View {
    let matches = filterLinkCandidates(candidates, matching: query)
    let searching = !query.trimmingCharacters(in: .whitespaces).isEmpty
    let shown = searching || showAll ? matches : Array(matches.prefix(Self.initiallyShown))
    VStack(alignment: .leading, spacing: 0) {
      SectionHeader(title: "Available to link", count: candidates.count) {
        HStack(spacing: 10) {
          if candidates.count > Self.initiallyShown {
            HStack(spacing: 5) {
              Image(systemName: "magnifyingglass").foregroundStyle(DS.muted).accessibilityHidden(true)
              TextField("Search \(candidates.count) apps", text: $query).textFieldStyle(.plain).frame(width: 150)
                .accessibilityLabel("Search apps that use \(library)")
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(DS.neutralFill, in: .rect(cornerRadius: DS.buttonRadius))
          }
          Button("Look again") { Task { await model.discoverConsumers() } }
            .buttonStyle(.borderless).disabled(model.isBusy(.discover))
        }
      }
      HairlineGroup {
        if candidates.isEmpty {
          GroupRow {
            Text(model.isBusy(.discover) ? "Looking for apps…" : "No other app in your project folders uses \(library).")
              .foregroundStyle(DS.muted)
          }
        }
        ForEach(shown) { consumer in
          GroupRow {
            Image(systemName: "macwindow").foregroundStyle(DS.muted).frame(width: 18).accessibilityHidden(true)
            TwoLine(
              title: projectName(consumer.root),
              caption: [consumer.packageManager.name, abbreviatedPath(consumer.root)].compactMap { $0 }
                .joined(separator: " · "), titleFont: DS.rowTitle
            )
            .frame(maxWidth: .infinity, alignment: .leading)
            .layoutPriority(1)
            dependencyChip(consumer.libraries.first { $0.name == library }?.range)
            Button("Link") { Task { await model.link(library, into: consumer.root) } }
              .buttonStyle(.accentPill(busy: model.isBusy(.link(library, consumer.root))))
              .help("Install the dev build of \(library) into \(projectName(consumer.root))")
          }
          .help(abbreviatedPath(consumer.root))
          .contextMenu { Button("Show in Finder") { revealInFinder(consumer.root) } }
        }
        if searching && matches.isEmpty {
          GroupRow { Text("No app matches “\(query)”").foregroundStyle(DS.muted) }
        }
        if !searching && !showAll && matches.count > Self.initiallyShown {
          Button("Show \(matches.count - Self.initiallyShown) more") { withAnimation(.snappy) { showAll = true } }
            .buttonStyle(.plain)
            .foregroundStyle(Color.accentColor)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 9)
        }
        GroupRow {
          Text("Not in the list?").foregroundStyle(DS.muted)
          Spacer()
          Button("Choose app…") { Task { await model.chooseAppAndLink(library) } }.buttonStyle(.pill)
        }
      }
      if !candidates.isEmpty {
        Footnote("\(candidates.count) app\(candidates.count == 1 ? "" : "s") in your project folders depend on \(library) and are still on a release.")
      }
    }
  }
}

/// A rarely used action that cannot be undone, kept apart at the foot of a page: what it does, and
/// either the button or the reason it is off.
struct DangerCard: View {
  let title: String
  let detail: String
  let button: String
  var enabled = true
  let action: () -> Void

  var body: some View {
    HStack(spacing: 12) {
      VStack(alignment: .leading, spacing: 1) {
        Text(title).font(DS.rowTitle)
        Text(detail).font(DS.caption).foregroundStyle(DS.muted).fixedSize(horizontal: false, vertical: true)
      }
      Spacer(minLength: 8)
      Button(button, role: .destructive, action: action).buttonStyle(.pill).disabled(!enabled)
    }
    .padding(.horizontal, 14)
    .padding(.vertical, 10)
    .background { RoundedRectangle(cornerRadius: DS.radius).strokeBorder(DS.cardBorder, lineWidth: 1) }
  }
}

/// A label and its value in a card: "Command   No build step".
struct ValueRow<Value: View, Trailing: View>: View {
  let label: String
  @ViewBuilder var value: Value
  @ViewBuilder var trailing: Trailing

  var body: some View {
    GroupRow {
      Text(label).foregroundStyle(DS.muted).frame(width: 90, alignment: .leading)
      value.frame(maxWidth: .infinity, alignment: .leading)
      trailing
    }
  }
}
