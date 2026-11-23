import AppKit
import DryfitAPI
import SwiftUI

// MARK: Welcome

/// What the window shows before there is anything to show: the four steps to a first sync.
struct WelcomePage: View {
  let model: MenuModel
  let navigation: AppNavigation

  var body: some View {
    Page {
      PlainTop(title: "Welcome to dryfit")
    } content: {
      Text("dryfit publishes each change to a private registry on this Mac and installs it into your apps the way a release would. When you're done, it puts every app back exactly as it was.")
        .font(.system(size: 14))
        .foregroundStyle(Theme.muted)
        .lineSpacing(2.9)
        .lh(14)
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: 620, alignment: .leading)
        .padding(.top, -4)
      if let error = model.actionError { ActionError(message: error) { model.dismissActionError() } }
      steps
    }
  }

  /// The first step not done yet is the one to do: it takes the primary button and a tint.
  private var steps: some View {
    let foldersDone = !(model.roots ?? []).isEmpty
    let libraryDone = !model.libraries.isEmpty
    let linkedDone = !(model.status?.links.isEmpty ?? true)
    let loginDone = model.startsAtLogin ?? true
    let current = [foldersDone, libraryDone, linkedDone, loginDone].firstIndex(of: false)
    return Tbl {
      Step(number: 1, title: "Tell dryfit where your apps live", detail: rootsDetail, done: foldersDone, current: current == 0) {
        Button(foldersDone ? "Change…" : "Add folders…") { Task { await model.chooseProjectFolders() } }
          .buttonStyle(.flat(current == 0 ? .primary : .normal, small: foldersDone))
      }
      Step(
        number: 2, title: "Add a library you're working on",
        detail: "Choose its folder. dryfit works out how to build it.", done: libraryDone, current: current == 1
      ) {
        if !libraryDone {
          Button("Add library…") { Task { await model.chooseLibraryFolder(navigation: navigation) } }
            .buttonStyle(.flat(current == 1 ? .primary : .normal))
        }
      }
      Step(
        number: 3, title: "Link it to an app",
        detail: "dryfit lists the apps that use your library. Link one, then sync, or turn on Auto-sync.",
        done: linkedDone, current: current == 2
      ) {}
      if let startsAtLogin = model.startsAtLogin {
        Step(
          number: 4, title: "Keep it running",
          detail: "Start dryfit when you log in, so auto-sync is on again after a restart.",
          done: startsAtLogin, current: current == 3
        ) {
          if !startsAtLogin {
            Button("Start at login") { Task { await model.setStartAtLogin(true) } }
              .buttonStyle(.flat(small: true, busy: model.isBusy(.startAtLogin)))
          }
        }
      }
    }
  }

  private var rootsDetail: String {
    guard let roots = model.roots, !roots.isEmpty else {
      return "Choose the folders that hold your apps, so dryfit can find the ones that use your library."
    }
    return "Looking in " + roots.map(abbreviatedPath).joined(separator: ", ")
  }
}

private struct Step<Actions: View>: View {
  let number: Int
  let title: String
  let detail: String
  let done: Bool
  let current: Bool
  @ViewBuilder let actions: Actions

  var body: some View {
    HStack(alignment: .top, spacing: 14) {
      ZStack {
        if done {
          Circle().fill(Theme.ok)
          Text("✓").font(.system(size: 12, weight: .semibold)).foregroundStyle(.white)
        } else {
          Circle().strokeBorder(Theme.cardBorder, lineWidth: 1)
          Text("\(number)").font(.system(size: 12, weight: .semibold)).foregroundStyle(Theme.muted)
        }
      }
      .frame(width: 24, height: 24)
      .accessibilityLabel(done ? "Done" : "Step \(number)")
      VStack(alignment: .leading, spacing: 0) {
        Text(title).font(.system(size: 13.5, weight: .semibold)).lh(13.5)
        Text(detail).font(.system(size: 12.5)).foregroundStyle(Theme.muted).lh(12.5).fixedSize(horizontal: false, vertical: true)
      }
      .frame(maxWidth: .infinity, alignment: .leading)
      actions
    }
    .padding(.horizontal, 16)
    .padding(.vertical, 14)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(current ? Theme.accentTint : .clear)
  }
}

// MARK: Library

struct LibraryPage: View {
  let name: String
  let model: MenuModel
  let navigation: AppNavigation
  let actions: MenuActions
  @State private var confirmingRemoval = false
  @Environment(\.timeZone) private var timeZone

  var body: some View {
    if let row = model.libraries.first(where: { $0.id == name }) { content(row) }
  }

  private func content(_ row: LibraryRow) -> some View {
    let library = row.library
    let candidates = model.linkCandidates(for: name)
    // What needs attention first: failed installs, above the list they belong to.
    let links = row.links.enumerated().sorted {
      ($0.element.status == .failed ? 0 : 1, $0.offset) < ($1.element.status == .failed ? 0 : 1, $1.offset)
    }.map(\.element)
    let failed = links.filter { $0.status == .failed }
    let syncing = model.isBusy(.sync(name)) || model.status?.jobs.running?.label == "sync \(name)"
    let published = publishedParts(library, timeZone: timeZone)
    return Page {
      PageTop(
        tile: (.library, Theme.releaseTint, Theme.release), title: library.name
      ) {
        if published.built != nil { Tag(text: "DEV BUILD", kind: .dev) }
      } sub: {
        if library.lastPublishedVersion != nil {
          Text(published.built == nil ? published.version : library.lastPublishedVersion ?? "").font(.system(size: 13, design: .monospaced))
          if let built = published.built {
            Text("·")
            Text("built \(built)")
          }
        } else {
          Text("not published yet")
        }
        if syncing {
          Text("·")
          Spin()
          Text("Syncing…")
        }
      } actions: {
        Text("Auto-sync").muted()
        DrySwitch(
          isOn: Binding(
            get: { library.isWatched },
            set: { enabled in Task { await model.setWatch(name, enabled: enabled) } }),
          label: "Auto-sync"
        )
        .disabled(model.isBusy(.watch(name)))
        .help(library.isWatched
          ? "Auto-sync is on: every change you save to \(name) is synced to its apps"
          : "Turn on to sync every change you save to \(name)")
        Button(syncing ? "Syncing…" : "Sync now") { Task { await model.sync(name) } }
          .buttonStyle(.flat(.primary, busy: syncing))
          .disabled(row.links.isEmpty)
          .help(row.links.isEmpty ? "Link an app first" : "Build, publish and install into every linked app")
      }
    } content: {
      if let error = model.actionError { ActionError(message: error) { model.dismissActionError() } }
      ForEach(failed) { link in InstallFailed(link: link, model: model, actions: actions) }

      VStack(alignment: .leading, spacing: 0) {
        SectionTitle("Linked apps", count: row.links.count)
        Tbl {
          if links.isEmpty {
            Tr(tracks: [.fr(1)]) { Text("No app is linked yet. Link one below to install the dev build.").foregroundStyle(Theme.muted) }
          } else {
            LinkedHeader()
          }
          ForEach(links) { link in LinkedRow(link: link, model: model) }
        }
      }

      AvailableToLink(library: name, candidates: candidates, model: model)

      // Set once, rarely changed: a card of its own, but below what is used every day.
      VStack(alignment: .leading, spacing: 0) {
        SectionTitle("Build")
        Tbl {
          VStack(alignment: .leading, spacing: 8) {
            Columns(tracks: [.fixed(130), .fr(1), .auto]) {
              Text("Command").foregroundStyle(Theme.muted).lh(13)
              Group {
                if let build = library.build.map({ BuildCommand(command: $0.command, args: $0.args).line }) {
                  Text(build).font(Theme.mono).lineLimit(1).truncationMode(.middle).textSelection(.enabled).help(build)
                } else {
                  Text("No build step")
                }
              }
              .frame(maxWidth: .infinity, alignment: .leading)
              Button("Change…") { navigation.libraryEditor = LibraryEditorRequest(root: library.root) }
                .buttonStyle(.flat(small: true))
            }
            Columns(tracks: [.fixed(130), .fr(1)]) {
              Text("Publishes").foregroundStyle(Theme.muted).lh(13)
              Text(publishFolder(library)).font(Theme.mono).lineLimit(1).truncationMode(.head).textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
          }
          .padding(.horizontal, 14)
          .padding(.vertical, 12)
          .frame(maxWidth: .infinity, alignment: .leading)
        }
      }

      Danger(
        title: "Remove from dryfit",
        detail: row.links.isEmpty ? "Your library's files are not touched." : "Restore its linked apps first.",
        button: "Remove…", enabled: row.links.isEmpty && !model.isBusy(.unregister(name))
      ) { confirmingRemoval = true }
    }
    .confirmationDialog("Remove \(name) from dryfit?", isPresented: $confirmingRemoval) {
      Button("Remove", role: .destructive) {
        Task {
          await model.unregister(name)
          if model.actionError == nil { navigation.selection = nil }
        }
      }
    } message: {
      Text("Its dev builds stay in dryfit's registry until they are replaced. Your library's files are not touched.")
    }
  }

  /// "dist/ui" when the publish folder is inside the library, the full path otherwise.
  private func publishFolder(_ library: Library) -> String {
    let root = library.root.hasSuffix("/") ? library.root : library.root + "/"
    if library.publishDir == library.root { return "The library's folder" }
    return library.publishDir.hasPrefix(root) ? String(library.publishDir.dropFirst(root.count)) : abbreviatedPath(library.publishDir)
  }
}

/// "1.4.1" and "14:32" for a published "1.4.1 · dev 14:32"; the time is nil for a release or nothing yet.
func publishedParts(_ library: Library, timeZone: TimeZone) -> (version: String, built: String?) {
  let described = library.published(timeZone: timeZone)
  guard let range = described.range(of: " · dev ") else { return (described, nil) }
  return (String(described[..<range.lowerBound]), String(described[range.upperBound...]))
}

/// A failed install, first among what a page shows: what failed and when, the output that says why, and
/// the two ways on: copy the output, or put the app back.
private struct InstallFailed: View {
  let link: DryfitAPI.Link
  let model: MenuModel
  let actions: MenuActions

  var body: some View {
    let failure = model.installFailure(in: link.consumer)
    let busy = model.isBusy(.restore(link.consumer, link.library))
    let manager = model.consumers.first { $0.root == link.consumer }?.packageManager.name
    Notice(
      kind: .bad, title: "Install into \(projectName(link.consumer)) failed",
      subtitle: subtitle(manager: manager, failure: failure),
      output: failure.map { $0.detail.split(whereSeparator: \.isNewline).prefix(6).joined(separator: "\n") }
    ) {
      if let failure {
        Button("Copy output") {
          NSPasteboard.general.clearContents()
          NSPasteboard.general.setString(failure.detail, forType: .string)
        }
        .buttonStyle(.flat(small: true))
      }
      Button("Restore \(projectName(link.consumer))") {
        Task { await model.restore(link.consumer, library: link.library) }
      }
      .buttonStyle(.flat(small: true, busy: busy))
      .disabled(!busy && model.isRestoring(link.consumer))
      .help("Put \(projectName(link.consumer)) back on the release of \(link.library)")
    }
  }

  /// "pnpm · 2 minutes ago".
  private func subtitle(manager: String?, failure: Failure?) -> String? {
    let when = failure.map { RelativeDateTimeFormatter().localizedString(for: $0.date, relativeTo: Date()) }
    let parts = [manager, when].compactMap { $0 }
    return parts.isEmpty ? nil : parts.joined(separator: " · ")
  }
}

/// The column names of a card (`.tr.hd`).
private struct TableHead: View {
  let tracks: [Columns.Track]
  let names: [String]

  var body: some View {
    Tr(tracks: tracks, vertical: 7) {
      ForEach(Array(names.enumerated()), id: \.offset) { _, name in
        Text(name).textCase(.uppercase).tracking(0.55).lh(11).frame(maxWidth: .infinity, alignment: .leading)
      }
    }
    .font(.system(size: 11, weight: .semibold))
    .foregroundStyle(Theme.muted)
    .background(Color.gray.opacity(0.06))
    .accessibilityHidden(true)
  }
}

private let linkedTracks: [Columns.Track] = [.fixed(20), .fr(1.4), .fr(1), .fr(1), .auto]

private struct LinkedHeader: View {
  var body: some View {
    TableHead(tracks: linkedTracks, names: ["", "App", "Status", "Version", ""])
  }
}

/// An app linked to a library: how it is doing, what it runs, and the way back to the release.
private struct LinkedRow: View {
  let link: DryfitAPI.Link
  let model: MenuModel
  @Environment(\.timeZone) private var timeZone

  var body: some View {
    Tr(tracks: linkedTracks) {
      StatusGlyph(kind: glyph, size: 16)
      RowTitle(title: projectName(link.consumer), caption: caption)
      Cell { statusTag }
      Text(version).font(Theme.mono).foregroundStyle(link.status == .installed ? Theme.text : Theme.muted).lineLimit(1)
        .frame(maxWidth: .infinity, alignment: .leading)
      Button("Restore") { Task { await model.restore(link.consumer, library: link.library) } }
        .buttonStyle(.flat(small: true, busy: busy))
        .disabled(!busy && model.isRestoring(link.consumer))
        .help("Put \(projectName(link.consumer)) back on the release of \(link.library)")
    }
    .contentShape(.rect)
    .help(abbreviatedPath(link.consumer))
    .contextMenu { Button("Show in Finder") { revealInFinder(link.consumer) } }
  }

  private var busy: Bool { model.isBusy(.restore(link.consumer, link.library)) }

  private var glyph: StatusGlyph.Kind {
    switch link.status {
    case .installed: .ok
    case .pending: .waiting
    case .failed: .failed
    }
  }

  @ViewBuilder private var statusTag: some View {
    switch link.status {
    case .failed: Tag(text: "Install failed", kind: .bad)
    case .pending: Tag(text: "Waiting for sync")
    case .installed: Tag(text: "Dev build", kind: .dev)
    }
  }

  /// "1.4.1 · 14:32" for an installed dev build.
  private var version: String {
    guard link.status == .installed, let installed = link.installedVersion else { return "–" }
    return DevVersion.describe(installed, timeZone: timeZone).replacingOccurrences(of: " · dev ", with: " · ")
  }

  private var caption: String {
    let manager = model.consumers.first { $0.root == link.consumer }?.packageManager.name
    let guarded = link.status == .installed && link.guarded == true
    return ([manager, abbreviatedPath(link.consumer)].compactMap { $0 }).joined(separator: " · ")
      + (guarded ? " · commit guard on" : "")
  }
}

/// How an app's package.json asks for a library, as a tag: "Release ^1.3.0" for a version range from
/// the registry, otherwise what it says plainly ("Local folder ui").
private func dependencyTag(_ range: String?) -> Tag {
  guard let range else { return Tag(text: "Release", kind: .release) }
  let described = describeDependency(range)
  return described.hasSuffix("from the registry")
    ? Tag(text: "Release \(range)", kind: .release) : Tag(text: described)
}

/// The apps that use a library and are not linked to it: five to start with, a search once there are
/// more, and "Show N more" for the rest. Thirty apps stay a short list.
private struct AvailableToLink: View {
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
      SectionTitle(title: "Available to link", count: candidates.count) {
        HStack(spacing: 10) {
          if candidates.count > Self.initiallyShown {
            Well {
              Icon(kind: .search, size: 12)
              TextField("", text: $query, prompt: Text("Search \(candidates.count) apps").foregroundStyle(Theme.muted))
                .textFieldStyle(.plain).frame(width: 130).foregroundStyle(Theme.text).focusEffectDisabled()
                .accessibilityLabel("Search apps that use \(library)")
            }
          }
          Button("Look again") { Task { await model.discoverConsumers() } }
            .buttonStyle(.plain).disabled(model.isBusy(.discover))
        }
      }
      Tbl {
        if candidates.isEmpty {
          Tr(tracks: [.fr(1)]) {
            Text(model.isBusy(.discover) ? "Looking for apps…" : "No other app in your project folders uses \(library).")
              .foregroundStyle(Theme.muted)
          }
        }
        ForEach(shown) { consumer in
          Tr(tracks: [.fixed(20), .fr(1.4), .fr(1), .auto]) {
            Icon(kind: .app, size: 15)
            RowTitle(
              title: projectName(consumer.root),
              caption: [consumer.packageManager.name, abbreviatedPath(consumer.root)].compactMap { $0 }.joined(separator: " · "))
            Cell { dependencyTag(consumer.libraries.first { $0.name == library }?.range) }
            Button("Link") { Task { await model.link(library, into: consumer.root) } }
              .buttonStyle(.flat(.accent, small: true, busy: model.isBusy(.link(library, consumer.root))))
              .help("Install the dev build of \(library) into \(projectName(consumer.root))")
          }
          .help(abbreviatedPath(consumer.root))
          .contextMenu { Button("Show in Finder") { revealInFinder(consumer.root) } }
        }
        if searching && matches.isEmpty {
          Tr(tracks: [.fr(1)]) { Text("No app matches “\(query)”").foregroundStyle(Theme.muted) }
        }
        if !searching && !showAll && matches.count > Self.initiallyShown {
          Button("Show \(matches.count - Self.initiallyShown) more") { withAnimation(.snappy) { showAll = true } }
            .buttonStyle(.plain)
            .font(.system(size: 12.5, weight: .medium))
            .foregroundStyle(Theme.accent)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 9)
        }
        Tr(tracks: [.fr(1), .auto]) {
          Text("Not in the list?").foregroundStyle(Theme.muted)
          Button("Choose app…") { Task { await model.chooseAppAndLink(library) } }.buttonStyle(.flat(small: true))
        }
      }
      if !candidates.isEmpty {
        Hint("\(candidates.count) app\(candidates.count == 1 ? "" : "s") in your project folders depend on \(library) and are still on a release.")
      }
    }
  }
}

// MARK: App

struct AppPage: View {
  let root: String
  let model: MenuModel
  let navigation: AppNavigation
  let actions: MenuActions
  @Environment(\.timeZone) private var timeZone

  var body: some View {
    if let app = model.apps.first(where: { $0.root == root }) { content(app) }
  }

  private func content(_ app: AppSummary) -> some View {
    let failed = app.linked.filter { $0.status == .failed }
    let tracks: [Columns.Track] = [.fr(1.4), .fr(1), .fr(1), .auto]
    return Page {
      PageTop(tile: (.app, Theme.purpleTint, Theme.purple), title: app.name) {
        if let manager = app.packageManager { Tag(text: manager) }
      } sub: {
        Text(summary(app, failed: !failed.isEmpty))
      } actions: {
        Button { revealInFinder(app.root) } label: {
          HStack(spacing: 6) { Icon(kind: .folder, size: 14, color: Theme.text); Text("Show in Finder") }
        }
        .buttonStyle(.flat)
        .help("Show \(app.name) in Finder")
        if !app.linked.isEmpty {
          Button("Restore all") { Task { await model.restore(app.root) } }
            .buttonStyle(.flat)
            .disabled(model.isBusy(.restore(app.root, nil)) || app.libraries.contains { model.isBusy(.restore(app.root, $0.library)) })
            .help("Put every library in \(app.name) back on its release")
        }
      }
    } content: {
      if let error = model.actionError { ActionError(message: error) { model.dismissActionError() } }
      ForEach(failed) { link in InstallFailed(link: link, model: model, actions: actions) }
      VStack(alignment: .leading, spacing: 0) {
        SectionTitle("Libraries", count: app.libraries.count)
        Tbl {
          TableHead(tracks: tracks, names: ["Library", "Build", "Version", ""])
          ForEach(app.libraries) { entry in
            Tr(tracks: tracks) {
              entryTitle(app, entry)
              Cell {
                if entry.link?.status == .failed {
                  Tag(text: "Install failed", kind: .bad)
                } else if entry.link != nil {
                  Tag(text: "Dev build", kind: .dev)
                } else {
                  Tag(text: "Release", kind: .release)
                }
              }
              Text(version(entry)).font(Theme.mono)
                .foregroundStyle(entry.link?.status == .installed ? Theme.text : Theme.muted)
                .lineLimit(1).frame(maxWidth: .infinity, alignment: .leading)
              if entry.link == nil {
                Button("Link") { Task { await model.link(entry.library, into: app.root) } }
                  .buttonStyle(.flat(.accent, small: true, busy: model.isBusy(.link(entry.library, app.root))))
                  .help("Install the dev build of \(entry.library) into \(app.name)")
              } else {
                Button("Restore") { Task { await model.restore(app.root, library: entry.library) } }
                  .buttonStyle(.flat(small: true, busy: model.isBusy(.restore(app.root, entry.library))))
                  .disabled(model.isBusy(.restore(app.root, nil)))
                  .help("Put \(app.name) back on the release of \(entry.library)")
              }
            }
            .contextMenu {
              Button("Show Installed Copy in Finder") { revealInFinder(app.root + "/node_modules/" + entry.library) }
            }
          }
        }
        Hint("Libraries from dryfit that \(app.name) depends on. Restore puts that library's release back and keeps the others linked.")
      }
      Danger(
        title: "Hide \(app.name)",
        detail: app.linked.isEmpty
          ? "dryfit stops listing it. Settings can show it again."
          : "Restore it first: dryfit only hides apps on released versions.",
        button: "Hide", enabled: app.linked.isEmpty && !model.isBusy(.hide(app.root))
      ) { Task { await model.hideApp(app.root, navigation: navigation) } }
    }
  }

  @ViewBuilder private func entryTitle(_ app: AppSummary, _ entry: AppSummary.Entry) -> some View {
    VStack(alignment: .leading, spacing: 0) {
      Text(entry.library).font(Theme.bodySemibold).lineLimit(1).lh(13)
      HStack(spacing: 0) {
        Text(detail(entry)).lineLimit(1).truncationMode(.middle)
        if entry.link?.status == .failed, let failure = model.installFailure(in: app.root) {
          Text(" · ")
          Button("Show output") { actions.showFailures(failure.id) }.buttonStyle(.plain).foregroundStyle(Theme.accent)
        }
      }
      .muted()
    }
  }

  private func summary(_ app: AppSummary, failed: Bool) -> String {
    let linked = app.linked.map(\.library)
    if linked.isEmpty { return "Uses released versions" }
    if app.linked.count == 1 && !failed { return "Uses the dev build of \(linked[0])" }
    return "Dev build of " + linked.joined(separator: ", ") + (failed ? " · install failed" : "")
  }

  /// "1.4.1 · 14:32" for a dev build, the range for a release.
  private func version(_ entry: AppSummary.Entry) -> String {
    if let link = entry.link {
      guard link.status == .installed, let installed = link.installedVersion else { return "–" }
      return DevVersion.describe(installed, timeZone: timeZone).replacingOccurrences(of: " · dev ", with: " · ")
    }
    // A registry range reads as a version; a local file or folder is named in the line above.
    guard let range = entry.range, describeDependency(range).hasSuffix("from the registry") else { return "–" }
    return range
  }

  private func detail(_ entry: AppSummary.Entry) -> String {
    guard let link = entry.link else { return entry.range.map(describeDependency) ?? "Released version" }
    switch link.status {
    case .failed: return "Install failed"
    case .pending: return "Waiting for a sync"
    case .installed:
      var parts: [String] = []
      if let installed = link.installedVersion, let time = DevVersion.describe(installed, timeZone: timeZone).split(separator: "dev ").last,
        DevVersion.parse(installed) != nil
      {
        parts.append("Linked \(time)")
      } else {
        parts.append("Installed")
      }
      if link.guarded == true { parts.append("commit guard on") }
      return parts.joined(separator: " · ")
    }
  }
}

// MARK: Group

struct GroupPage: View {
  let name: String
  let model: MenuModel
  let navigation: AppNavigation
  @State private var confirmingDeletion = false
  @Environment(\.timeZone) private var timeZone

  var body: some View {
    if let group = model.status?.groups.first(where: { $0.name == name }) { content(group) }
  }

  private func content(_ group: DryfitAPI.Group) -> some View {
    let warnings = model.status?.warnings.filter { $0.group == name } ?? []
    return Page {
      PageTop(tile: (.group, Theme.purpleTint, Theme.purple), title: group.name) {
      } sub: {
        Text("Link a library into all of these apps at once, and restore them together.")
      } actions: {
        MenuButton(title: "Link library") {
          ForEach(model.status?.libraries ?? []) { library in
            Button(library.name) { Task { await model.linkGroup(name, library: library.name) } }
          }
        }
        .disabled(model.status?.libraries.isEmpty ?? true)
        .help("Link a library into every app in \(name)")
        Button("Restore all") { Task { await model.restoreGroup(name) } }
          .buttonStyle(.flat(busy: model.isBusy(.restoreGroup(name))))
          .help("Put every app in \(name) back on released versions")
      }
    } content: {
      if let error = model.actionError { ActionError(message: error) { model.dismissActionError() } }
      VStack(alignment: .leading, spacing: 0) {
        SectionTitle(title: "Apps", count: group.consumers.count) {
          Button("Edit…") { navigation.groupEditor = .edit(group) }.buttonStyle(.plain)
        }
        Tbl {
          ForEach(group.consumers, id: \.self) { consumer in
            Tr(tracks: [.fr(1), .auto]) {
              RowTitle(title: projectName(consumer), caption: abbreviatedPath(consumer))
              let libraries = linkedLibraries(consumer)
              if libraries.isEmpty {
                Tag(text: "Released versions", kind: .release)
              } else {
                Tag(text: "Dev build of " + libraries.joined(separator: ", "), kind: .dev)
              }
            }
          }
        }
      }
      ForEach(Array(warnings.enumerated()), id: \.offset) { _, warning in
        Notice(
          kind: .warn, title: "\(warning.library) differs between these apps",
          subtitle: warning.versions
            .map { "\(projectName($0.consumer)) is on \(DevVersion.describe($0.version, timeZone: timeZone))" }
            .joined(separator: " · ")
        ) {
          Button("Link \(warning.library) into both") { Task { await model.linkGroup(name, library: warning.library) } }
            .buttonStyle(.flat(small: true, busy: model.isBusy(.linkGroup(name))))
        }
      }
      Danger(
        title: "Delete group", detail: "Its apps stay as they are.", button: "Delete…",
        enabled: !model.isBusy(.deleteGroup(name))
      ) { confirmingDeletion = true }
    }
    .confirmationDialog("Delete the group \(name)?", isPresented: $confirmingDeletion) {
      Button("Delete", role: .destructive) {
        Task {
          await model.deleteGroup(name)
          // Stay on the page when it failed, so its banner says why, as Remove does.
          if model.actionError == nil { navigation.selection = nil }
        }
      }
    } message: {
      Text("Its apps stay linked or restored as they are now.")
    }
  }

  private func linkedLibraries(_ consumer: String) -> [String] {
    (model.status?.links.filter { $0.consumer == consumer } ?? []).map(\.library)
  }
}

// MARK: Settings

/// dryfit's settings, a page of the window: where to look for apps, the background service, opening at
/// login, and updates.
struct SettingsPage: View {
  let model: MenuModel
  let actions: MenuActions

  var body: some View {
    Page {
      PlainTop(title: "Settings")
    } content: {
      if let error = model.actionError { ActionError(message: error) { model.dismissActionError() } }

      section("Project folders") {
        if model.connection != .online {
          Tr(tracks: [.fr(1), .auto]) { name("Start dryfit to change these."); Color.clear }
        } else if let roots = model.roots, !roots.isEmpty {
          ForEach(roots, id: \.self) { root in
            Tr(tracks: [.fr(1), .auto]) {
              HStack(spacing: 10) {
                Icon(kind: .folder, size: 15)
                Text(abbreviatedPath(root)).font(Theme.mono).lh(12).lineLimit(1).truncationMode(.head)
              }
              Button {
                Task {
                  do {
                    try await model.setRoots(roots.filter { $0 != root })
                  } catch {
                    model.actionError = error.localizedDescription
                  }
                }
              } label: {
                Text("−").font(.system(size: 13, weight: .bold)).foregroundStyle(Theme.faint).lh(13)
                  .padding(.horizontal, 6).padding(.vertical, 2)
              }
              .buttonStyle(.plain)
              .disabled(model.isBusy(.roots))
              .help("Stop looking in \(abbreviatedPath(root))")
              .accessibilityLabel("Remove \(abbreviatedPath(root))")
            }
          }
        } else {
          Tr(tracks: [.fr(1), .auto]) { name("No folders yet. Add the folders that hold your apps."); Color.clear }
        }
        Tr(tracks: [.fr(1), .auto]) {
          Text("dryfit looks in these folders for apps that use your libraries.").muted()
          Button("Add folders…") { Task { await model.chooseProjectFolders() } }
            .buttonStyle(.flat(small: true, busy: model.isBusy(.roots)))
            .disabled(model.connection != .online)
        }
      }

      if let hidden = model.hiddenApps, !hidden.isEmpty, model.connection == .online {
        section("Hidden apps", count: hidden.count) {
          ForEach(hidden, id: \.self) { root in
            Tr(tracks: [.fr(1), .auto]) {
              RowTitle(title: projectName(root), caption: abbreviatedPath(root), weight: .medium)
              Button("Show") { Task { await model.showApp(root) } }
                .buttonStyle(.flat(small: true, busy: model.isBusy(.hide(root))))
                .help("List \(projectName(root)) again")
            }
            .help(abbreviatedPath(root))
          }
        }
      }

      section("dryfit service") {
        Tr(tracks: [.fr(1), .auto]) {
          name("Status")
          HStack(spacing: 8) {
            Dot(color: statusColor)
            Text(status).foregroundStyle(Theme.muted)
          }
        }
        if let outdated = model.outdatedVersion {
          Tr(tracks: [.fr(1), .auto]) {
            HStack(spacing: 10) {
              StatusGlyph(kind: .update, size: 16)
              RowTitle(title: "dryfit \(outdated) is older than this app", caption: "Runs npm install --global @dryfit/cli@latest", weight: .medium)
            }
            VStack(alignment: .trailing, spacing: 4) {
              Button("Update") { Task { await model.updateCLI() } }
                .buttonStyle(.flat(.primary, small: true, busy: model.isBusy(.updateCLI)))
                .help("Runs npm install --global @dryfit/cli@latest, then restarts dryfit")
              if let error = model.updateError {
                Text(error).font(Theme.small).foregroundStyle(Theme.bad).textSelection(.enabled)
              }
            }
          }
          .background(Theme.warnTint)
        }
        if let registry = model.status?.daemon.registryUrl, model.connection == .online {
          Tr(tracks: [.fr(1), .auto]) {
            name("Registry")
            Text(registry).font(Theme.mono).lh(12).foregroundStyle(Theme.muted).lineLimit(1).truncationMode(.middle).textSelection(.enabled)
          }
        }
        if let startsAtLogin = model.startsAtLogin {
          Tr(tracks: [.fr(1), .auto]) {
            RowTitle(title: "Start dryfit at login", caption: "Auto-sync is on again after a restart.", weight: .medium)
            HStack(spacing: 8) {
              if model.isBusy(.startAtLogin) { Spin() }
              DrySwitch(
                isOn: Binding(get: { startsAtLogin }, set: { on in Task { await model.setStartAtLogin(on) } }),
                label: "Start dryfit at login"
              )
              .disabled(model.isBusy(.startAtLogin))
            }
          }
          .help("Start dryfit when you log in, so auto-sync is on again after a restart")
        }
        Tr(tracks: [.fr(1), .auto]) {
          HStack { Button("Open log", action: actions.openLog).buttonStyle(.flat(small: true)) }
          Group {
            switch model.connection {
            case .online:
              Button("Stop") { Task { await model.stopDaemon() } }.buttonStyle(.flat(small: true, busy: model.isBusy(.stop)))
            case .offline:
              Button("Start") { Task { await model.startDaemon() } }.buttonStyle(.flat(.primary, small: true))
            case .starting:
              Button("Start") {}.buttonStyle(.flat(.primary, small: true, busy: true))
            default:
              Color.clear.frame(width: 1, height: 1)
            }
          }
        }
      }

      if let openAtLogin = actions.openAtLogin {
        section("General") {
          Tr(tracks: [.fr(1), .auto]) {
            name("Open this app at login")
            LiveSwitch(title: "Open at login", source: openAtLogin)
          }
        }
      }

      if let checkForUpdates = actions.checkForUpdates {
        section("Updates") {
          if let installAutomatically = actions.installUpdatesAutomatically {
            Tr(tracks: [.fr(1), .auto]) {
              RowTitle(
                title: "Install updates automatically",
                caption: "Checked once a day, installed while you are not using the app.", weight: .medium)
              LiveSwitch(title: "Install updates automatically", source: installAutomatically)
            }
          }
          Tr(tracks: [.fr(1), .auto]) {
            Text(model.appVersion.map { "dryfit \($0)" } ?? "dryfit").muted()
            Button("Check now", action: checkForUpdates).buttonStyle(.flat(small: true))
          }
        }
      }
    }
  }

  private func name(_ text: String) -> some View {
    Text(text).font(.system(size: 13, weight: .medium)).lh(13)
  }

  /// A titled card of settings.
  private func section<Body: View>(_ title: String, count: Int? = nil, @ViewBuilder content: () -> Body) -> some View {
    VStack(alignment: .leading, spacing: 0) {
      SectionTitle(title, count: count)
      Tbl { content() }
    }
  }

  private var statusColor: Color {
    switch model.connection {
    case .online: Theme.ok
    case .connecting, .starting, .incompatible: Theme.warn
    case .offline: Theme.faint
    }
  }

  private var status: String {
    switch model.connection {
    case .online: model.status.map { "Running · version \($0.daemon.version)" } ?? "Running"
    case .connecting: "Looking for dryfit…"
    case .starting: "Starting…"
    case .offline: "Not running"
    case .incompatible(let version): "dryfit \(version) does not match this app"
    }
  }
}

/// A switch over a setting SwiftUI cannot observe (a login item, the updater's preference). It keeps
/// its own copy, and reads the setting back after each change, so it moves when clicked and shows
/// what really happened: a login item macOS refused, for one, turns it off again.
private struct LiveSwitch: View {
  let title: String
  let source: Binding<Bool>
  @State private var isOn: Bool

  init(title: String, source: Binding<Bool>) {
    self.title = title
    self.source = source
    _isOn = State(initialValue: source.wrappedValue)
  }

  var body: some View {
    DrySwitch(
      isOn: Binding(
        get: { isOn },
        set: { wanted in
          source.wrappedValue = wanted
          isOn = source.wrappedValue
        }),
      label: title
    )
    .onAppear { isOn = source.wrappedValue }
  }
}

// MARK: Not running

/// dryfit's service is not running: start it, or install the CLI it runs from.
struct ServiceUnavailable: View {
  let model: MenuModel
  let actions: MenuActions

  var body: some View {
    Center(
      glyph: glyph(model.cliMissing ? "⬇︎" : "⏻"), title: model.cliMissing ? "Install dryfit" : "dryfit is not running",
      text: model.cliMissing
        ? "The app runs dryfit’s command-line tool in the background. It needs Node.js and npm."
        : "Start it to publish your libraries and install them into your apps."
    ) {
      VStack(spacing: 6) {
        if model.connection == .starting {
          progress("Starting…")
        } else if model.isBusy(.installCLI) {
          progress("Installing with npm…")
        } else if model.cliMissing {
          Button("Install dryfit") { Task { await model.installCLI() } }.buttonStyle(FlatButtonStyle(kind: .primary, roomy: true)).padding(.top, 10)
          Text("Runs \(DaemonLauncher.installCommand)").font(.system(size: 11.5, design: .monospaced)).foregroundStyle(Theme.muted)
        } else {
          Button("Start dryfit") { Task { await model.startDaemon() } }.buttonStyle(FlatButtonStyle(kind: .primary, roomy: true)).padding(.top, 10)
        }
        // Shown while the CLI is missing too: a failed install would otherwise just offer the button
        // again, with no word of why.
        if let error = model.startError, !model.isBusy(.installCLI) {
          Text(error).font(Theme.small).foregroundStyle(Theme.bad).multilineTextAlignment(.center)
            .textSelection(.enabled).frame(maxWidth: 320).fixedSize(horizontal: false, vertical: true).padding(.top, 2)
          if model.cliMissing {
            Button("Copy install command") {
              NSPasteboard.general.clearContents()
              NSPasteboard.general.setString(DaemonLauncher.installCommand, forType: .string)
            }
            .buttonStyle(.plain).font(Theme.small).foregroundStyle(Theme.accent)
          } else {
            Button("Open log", action: actions.openLog).buttonStyle(.plain).font(Theme.small).foregroundStyle(Theme.accent)
          }
        }
      }
    }
  }

  private func progress(_ text: String) -> some View {
    VStack(spacing: 6) {
      Spin()
      Text(text).font(.system(size: 11.5)).foregroundStyle(Theme.muted)
    }
    .padding(.top, 4)
  }
}

struct IncompatibleState: View {
  let model: MenuModel
  let actions: MenuActions
  let daemonVersion: String

  var body: some View {
    Center(
      glyph: AnyView(StatusGlyph(kind: .warning, size: 34)), title: "This app and dryfit \(daemonVersion) don't match",
      text: explanation
    ) {
      if model.outdatedVersion != nil {
        VStack(spacing: 6) {
          if model.isBusy(.updateCLI) {
            Spin()
            Text("Updating with npm…").font(.system(size: 11.5)).foregroundStyle(Theme.muted)
          } else {
            Button("Update dryfit") { Task { await model.updateCLI() } }.buttonStyle(FlatButtonStyle(kind: .primary, roomy: true)).padding(.top, 10)
            Text("Runs npm install --global @dryfit/cli@latest")
              .font(.system(size: 11.5, design: .monospaced)).foregroundStyle(Theme.muted)
          }
          if let error = model.updateError {
            Text(error).font(Theme.small).foregroundStyle(Theme.bad).multilineTextAlignment(.center)
              .textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
          }
        }
      } else if model.appIsOlder, let checkForUpdates = actions.checkForUpdates {
        Button("Check for updates…", action: checkForUpdates).buttonStyle(FlatButtonStyle(kind: .primary, roomy: true)).padding(.top, 10)
      }
    }
  }

  private var explanation: String {
    if model.outdatedVersion != nil { return "dryfit is the older one." }
    if model.appIsOlder { return "This app is the older one." }
    return "They speak different versions of dryfit's API. Update the one that is older."
  }
}

private func glyph(_ symbol: String) -> AnyView {
  AnyView(Text(symbol).font(.system(size: 30)).foregroundStyle(Theme.muted).frame(height: 30))
}
