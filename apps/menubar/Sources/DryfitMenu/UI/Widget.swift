import AppKit
import DryfitAPI
import SwiftUI

/// The menu bar window (ADR 0013): what dryfit is doing at a glance, with the everyday controls —
/// watch, sync, link, restore. Adding and changing things happens in the dryfit window, one click away.
/// Drawn from the mockup's `.panel`: a header, one card per library, the groups, and a foot.
public struct MenuContent: View {
  let model: MenuModel
  let navigation: AppNavigation
  let actions: MenuActions
  @Environment(\.openWindow) private var openWindow

  public init(model: MenuModel, navigation: AppNavigation = AppNavigation(), actions: MenuActions) {
    self.model = model
    self.navigation = navigation
    self.actions = actions
  }

  public var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      if model.connection == .online, let outdated = model.outdatedVersion {
        OutdatedBar(model: model, version: outdated)
      }
      PanelHeader(model: model) { show(nil) }
      switch model.connection {
      case .online:
        OnlineContent(model: model, actions: actions, show: show, addLibrary: addLibrary)
      case .offline, .starting:
        Unavailable(model: model, actions: actions)
      case .connecting:
        Spin().frame(maxWidth: .infinity).padding(.vertical, 34)
      case .incompatible(let daemonVersion):
        Incompatible(model: model, actions: actions, daemonVersion: daemonVersion)
      }
      PanelFoot(model: model, actions: actions) {
        navigation.showSettings { openWindow(id: mainWindowID) }
      }
    }
    .font(Theme.body)
    .foregroundStyle(Theme.text)
    .frame(width: 372)
    // The mockup's `.panel`, not the system's Liquid Glass: a near-opaque surface over a plain blur.
    .background(PanelSurface())
    .onAppear { model.menuOpened() }
    // The rest of what the old footer menu held is on the menu bar icon's right-click menu. These keep
    // its shortcuts working while the window is open.
    .background {
      Group {
        Button("Settings…") { navigation.showSettings { openWindow(id: mainWindowID) } }
          .keyboardShortcut(",")
        Button("Quit", action: actions.quit).keyboardShortcut("q")
      }
      .opacity(0)
      .accessibilityHidden(true)
    }
  }

  /// Opens the dryfit window, at `item` when given.
  private func show(_ item: SidebarItem?) {
    if let item { navigation.selection = item }
    openWindow(id: mainWindowID)
    NSApp.activate()
  }

  private func addLibrary() {
    navigation.wantsNewLibrary = true
    show(nil)
  }
}

// MARK: Surface

/// The mockup's `.panel` background: `Theme.glass` (82% white or charcoal) over a blur of what is behind
/// the window, so the panel reads as one solid surface in light and dark rather than as Liquid Glass.
private struct PanelSurface: View {
  var body: some View {
    ZStack {
      BehindWindowBlur()
      Theme.glass
    }
  }
}

private struct BehindWindowBlur: NSViewRepresentable {
  func makeNSView(context: Context) -> NSVisualEffectView {
    let view = NSVisualEffectView()
    view.material = .popover
    view.blendingMode = .behindWindow
    view.state = .active
    return view
  }

  func updateNSView(_ view: NSVisualEffectView, context: Context) {}
}

// MARK: Header, foot

private struct PanelHeader: View {
  let model: MenuModel
  let openWindow: () -> Void

  var body: some View {
    HStack(spacing: 10) {
      VStack(alignment: .leading, spacing: 2) {
        Text("dryfit").font(.system(size: 15, weight: .semibold)).lh(15, 1.2)
        HStack(spacing: 6) {
          Dot(color: dot)
          Text(subtitle).lineLimit(1)
        }
        .muted()
      }
      Spacer(minLength: 0)
      if model.connection == .online {
        Button("Open dryfit", action: openWindow)
          .buttonStyle(.flat)
          .help("Open the dryfit window to add libraries, link apps and manage groups")
      }
    }
    .padding(.horizontal, 16)
    .padding(.top, 14)
    .padding(.bottom, 12)
  }

  private var dot: Color {
    switch model.connection {
    case .online: model.failures.isEmpty ? Theme.ok : Theme.bad
    case .connecting, .starting: Theme.warn
    case .offline: Theme.faint
    case .incompatible: Theme.warn
    }
  }

  /// What is wrong comes first: a failure is a count in words, not just a colour.
  private var subtitle: String {
    switch model.connection {
    case .online:
      let failures = model.failures.count
      if failures > 0 { return failures == 1 ? "Running · 1 needs attention" : "Running · \(failures) need attention" }
      if model.activity != nil { return "Running · syncing" }
      return "Running"
    case .connecting: return "Looking for dryfit…"
    case .starting: return "Starting…"
    case .offline:
      if model.isBusy(.installCLI) { return "Installing…" }
      return model.cliMissing ? "Not installed" : "Not running"
    case .incompatible: return "Needs an update"
    }
  }
}

/// Always there: what dryfit is doing while it works, otherwise the log while it is not running, and
/// Settings at the far end.
private struct PanelFoot: View {
  let model: MenuModel
  let actions: MenuActions
  let showSettings: () -> Void

  var body: some View {
    VStack(spacing: 0) {
      Hair()
      HStack(spacing: 8) {
        if let activity = model.activity {
          Spin()
          Text(activity).lineLimit(1).truncationMode(.middle)
        } else if model.connection == .offline || model.connection == .starting {
          Button("Open log", action: actions.openLog).buttonStyle(.plain).foregroundStyle(Theme.accent)
        }
        Spacer(minLength: 8)
        Button(action: showSettings) {
          Icon(kind: .gear, size: 15, color: Theme.faint)
            .padding(2)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .help("Settings (⌘,)")
        .accessibilityLabel("Settings")
      }
      .font(Theme.small)
      .foregroundStyle(Theme.muted)
      .padding(.horizontal, 16)
      .padding(.vertical, 10)
    }
  }
}

// MARK: Online

private struct OnlineContent: View {
  let model: MenuModel
  let actions: MenuActions
  let show: (SidebarItem?) -> Void
  let addLibrary: () -> Void

  var body: some View {
    if model.libraries.isEmpty && model.groups.isEmpty && banners.isEmpty && model.driftedRestore == nil
      && model.actionError == nil
    {
      Message(icon: AnyView(Icon(kind: .library, size: 30, color: Theme.release)), title: "Test your library in your apps",
        text: "Add a library you're working on, and dryfit installs each change into the apps that use it."
      ) {
        Button("Add library", action: addLibrary).buttonStyle(FlatButtonStyle(kind: .primary, roomy: true)).padding(.top, 10)
      }
    } else {
      // As tall as its content, scrolling past what fits under the menu bar.
      ScrollView { sections }
        .scrollBounceBehavior(.basedOnSize)
        .frame(maxHeight: 520)
        .fixedSize(horizontal: false, vertical: true)
        .task {
          // The link chips offer projects that use each library; finding them reads the disk once.
          if model.consumers.isEmpty { await model.discoverConsumers() }
        }
    }
  }

  /// Failures a link row does not already show as "Install failed · Show output".
  private var banners: [Failure] {
    let shown = Set(
      model.libraries.flatMap(\.links).filter { $0.status == .failed }.compactMap {
        model.installFailure(in: $0.consumer)?.id
      })
    return model.failures.filter { !shown.contains($0.id) }
  }

  private var sections: some View {
    VStack(alignment: .leading, spacing: 10) {
      if let failure = banners.first {
        let more = banners.count - 1
        Banner(
          kind: .bad, title: failure.title,
          text: failure.detail.split(whereSeparator: \.isNewline).first.map(String.init), mono: true
        ) {
          Button(more > 0 ? "Show \(more + 1) failures" : "Show output") { actions.showFailures(failure.id) }
            .buttonStyle(.flat(small: true))
          // Clears every failure, so with more than one it says so.
          Button(more > 0 ? "Dismiss all" : "Dismiss") { model.clearFailures() }.buttonStyle(.flat(small: true))
        }
      }
      if let request = model.driftedRestore {
        Banner(
          kind: .warn, title: "\(projectName(request.consumer))'s package.json changed",
          text: "Restoring puts back the version from before linking, and drops those changes.", trailingActions: true
        ) {
          Button("Cancel") { model.driftedRestore = nil }.buttonStyle(.flat(small: true))
          Button("Restore anyway") {
            Task { await model.restore(request.consumer, library: request.library, force: true) }
          }
          .buttonStyle(.flat(.bad, small: true))
        }
      }
      if let error = model.actionError {
        Banner(kind: .bad, title: nil, text: error) {
          Button("Dismiss") { model.dismissActionError() }.buttonStyle(.flat(small: true))
        }
      }
      ForEach(model.libraries) { row in
        LibraryCard(row: row, model: model, actions: actions) { show(.library(row.library.name)) }
      }
      if !model.groups.isEmpty {
        WidgetSection("Groups")
        ForEach(model.groups) { group in
          GroupCard(group: group, model: model) { show(.group(group.name)) }
        }
      }
    }
    .padding(.horizontal, 12)
    .padding(.bottom, 2)
  }
}

/// The mockup's `.sec`: a small uppercase label over a group of cards.
private struct WidgetSection: View {
  let title: String
  init(_ title: String) { self.title = title }

  var body: some View {
    Text(title)
      .font(.system(size: 11, weight: .semibold))
      .textCase(.uppercase)
      .tracking(0.55)
      .lh(11)
      .foregroundStyle(Theme.muted)
      .padding(.horizontal, 4)
      .padding(.top, 4)
  }
}

/// The mockup's `.banner`: a failure or a warning above the cards, with its actions.
private struct Banner<Actions: View>: View {
  enum Kind { case bad, warn }

  let kind: Kind
  let title: String?
  var text: String? = nil
  var mono = false
  /// The actions sit at the right under the text, not at the left.
  var trailingActions = false
  @ViewBuilder var actions: Actions

  var body: some View {
    VStack(alignment: .leading, spacing: 9) {
      HStack(alignment: .top, spacing: 8) {
        StatusGlyph(kind: kind == .bad ? .failed : .warning, size: kind == .bad ? 14 : 15).padding(.top, 1)
        VStack(alignment: .leading, spacing: 0) {
          if let title { Text(title).font(Theme.bodySemibold).lh(13) }
          if let text {
            Text(text)
              .font(mono ? Theme.mono : title == nil ? Theme.body : Theme.small)
              .foregroundStyle(title == nil ? Theme.text : Theme.muted)
              .lineLimit(mono ? 2 : nil)
              .lineSpacing(mono ? 4 : 2.5)
              .fixedSize(horizontal: false, vertical: true)
              .textSelection(.enabled)
          }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
      }
      HStack(spacing: 6) {
        if trailingActions { Spacer(minLength: 0) }
        actions
      }
      .padding(.leading, trailingActions ? 0 : 22)
    }
    .padding(.horizontal, 12)
    .padding(.vertical, 10)
    .background(kind == .bad ? Theme.badTint : Theme.warnTint, in: .rect(cornerRadius: Theme.cardRadius))
    .overlay {
      RoundedRectangle(cornerRadius: Theme.cardRadius)
        .strokeBorder(kind == .bad ? Theme.badBorder : Theme.warnBorder, lineWidth: 1)
    }
  }
}

/// The mockup's `.ob`: dryfit is older than this app, across the top of the panel.
private struct OutdatedBar: View {
  let model: MenuModel
  let version: String

  var body: some View {
    VStack(spacing: 0) {
      HStack(spacing: 10) {
        StatusGlyph(kind: .update, size: 16)
        VStack(alignment: .leading, spacing: 0) {
          Text("dryfit \(version) is older than this app").font(Theme.bodySemibold)
          Text(model.isBusy(.updateCLI) ? "Updating with npm…" : "Update it to \(model.appVersion ?? "the newest version") to get what is new.")
            .muted()
        }
        Spacer(minLength: 8)
        if model.isBusy(.updateCLI) {
          Spin()
        } else {
          Button("Update") { Task { await model.updateCLI() } }
            .buttonStyle(.flat(small: true))
            .help("Runs npm install --global @dryfit/cli@latest, then restarts dryfit")
        }
      }
      .padding(.horizontal, 16)
      .padding(.vertical, 10)
      if let error = model.updateError {
        Hair().overlay(Theme.warnBorder)
        HStack {
          Text(error).font(Theme.small).foregroundStyle(Theme.bad).textSelection(.enabled)
            .fixedSize(horizontal: false, vertical: true)
          Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
      }
    }
    .background(Theme.warnTint)
    .overlay(alignment: .bottom) { Rectangle().fill(Theme.warnBorder).frame(height: 1) }
  }
}

// MARK: Library card

/// A library as a card: its name and Auto-sync on top, what it is, then, unless folded, the apps it
/// is linked into (the ones that need you first) and a way to link more.
private struct LibraryCard: View {
  let row: LibraryRow
  let model: MenuModel
  let actions: MenuActions
  let open: () -> Void
  /// Folded libraries, by name, one per line; kept between launches.
  @AppStorage("foldedLibraries") private var folded = ""
  @State private var picking = false
  @Environment(\.timeZone) private var timeZone

  /// More linked apps than this are left to the window, which has room for them.
  private static let visibleLinks = 3

  var body: some View {
    let candidates = model.linkCandidates(for: name)
    VStack(alignment: .leading, spacing: 0) {
      HStack(alignment: .top, spacing: 0) {
        foldButton
        VStack(alignment: .leading, spacing: 0) {
          header
          summary(candidates: candidates.count)
        }
      }
      // So the fold column is as tall as the name and summary beside it.
      .fixedSize(horizontal: false, vertical: true)
      if !isFolded {
        ForEach(shownLinks) { link in
          Hair()
          LinkRow(link: link, model: model, actions: actions)
        }
        if hiddenLinks > 0 {
          Hair()
          Button(action: open) {
            Text("Show \(hiddenLinks) more linked app\(hiddenLinks == 1 ? "" : "s") in window ›")
              .font(.system(size: 12.5, weight: .medium))
              .foregroundStyle(Theme.accent)
              .frame(maxWidth: .infinity)
              .padding(.vertical, 8)
              .contentShape(.rect)
          }
          .buttonStyle(.plain)
        }
        Hair()
        linkFooter(candidates)
      }
    }
    .card(radius: Theme.widgetCardRadius, fill: Theme.widgetCard)
  }

  private var name: String { row.library.name }

  /// The triangle, and with it the whole left gutter of the card beside the name and summary: the
  /// triangle alone is too small to hit.
  private var foldButton: some View {
    Button {
      withAnimation(.snappy) { isFolded.toggle() }
    } label: {
      Text(isFolded ? "▸" : "▾").font(.system(size: 10)).foregroundStyle(Theme.faint)
        .frame(width: 10, height: 19.6)
        .padding(.top, 11)
        .padding(.leading, 12)
        .padding(.trailing, 6)
        .frame(maxHeight: .infinity, alignment: .top)
        .contentShape(.rect)
    }
    .buttonStyle(.plain)
    .accessibilityLabel(isFolded ? "Show \(name)'s apps" : "Hide \(name)'s apps")
  }

  private var header: some View {
    HStack(spacing: 8) {
      Button(action: open) {
        Text(name).font(.system(size: 14, weight: .semibold)).lineLimit(1).truncationMode(.middle).lh(14)
          .frame(maxWidth: .infinity, alignment: .leading)
          .contentShape(.rect)
      }
      .buttonStyle(.plain)
      .pointerStyle(.link)
      .help("Show \(name) in the dryfit window")
      Text("Auto-sync").muted().accessibilityHidden(true)
      DrySwitch(isOn: watch, label: "Auto-sync \(name)")
        .disabled(model.isBusy(.watch(name)))
        .help(row.library.isWatched ? "Auto-sync is on: every change you save is synced" : "Auto-sync: sync every change you save")
    }
    .padding(.leading, 2)
    .padding(.trailing, 12)
    .padding(.top, 11)
    .padding(.bottom, 4)
  }

  private var syncing: Bool {
    model.isBusy(.sync(name)) || model.status?.jobs.running?.label == "sync \(name)"
  }

  private func summary(candidates: Int) -> some View {
    HStack(spacing: 6) {
      if row.links.isEmpty {
        Tag(text: "Not linked")
        if candidates > 0 { Text(candidates == 1 ? "1 app uses it" : "\(candidates) apps use it").lh(12) }
      } else {
        let published = published
        if published.built != nil { Tag(text: "DEV", kind: .dev) }
        Text(row.library.lastPublishedVersion ?? published.version).font(Theme.mono).lh(12)
        Text("· \(row.links.count) app\(row.links.count == 1 ? "" : "s")").lh(12)
        if syncing {
          Text("·").lh(12)
          Spin()
          Text("Syncing…").lh(12)
        }
      }
    }
    .font(Theme.small)
    .foregroundStyle(Theme.muted)
    .lineLimit(1)
    .padding(.trailing, 12)
    .padding(.bottom, 9)
  }

  /// "1.4.1" and "14:32" for "1.4.1 · dev 14:32"; the time is nil for a release.
  private var published: (version: String, built: String?) {
    let described = row.library.published(timeZone: timeZone)
    guard let range = described.range(of: " · dev ") else { return (described, nil) }
    return (String(described[..<range.lowerBound]), String(described[range.upperBound...]))
  }

  /// What needs you first: a failed install, then one waiting on a dev server restart, then the rest.
  private var sortedLinks: [DryfitAPI.Link] {
    func rank(_ link: DryfitAPI.Link) -> Int {
      if link.status == .failed { return 0 }
      if link.status == .installed, model.restartNeeded.contains(link.consumer) { return 1 }
      return 2
    }
    return row.links.enumerated().sorted { (rank($0.element), $0.offset) < (rank($1.element), $1.offset) }.map(\.element)
  }

  private var shownLinks: [DryfitAPI.Link] { Array(sortedLinks.prefix(Self.visibleLinks)) }
  private var hiddenLinks: Int { max(0, row.links.count - Self.visibleLinks) }

  /// A few apps are one click each; more than that is a search, so thirty never fill the menu.
  @ViewBuilder private func linkFooter(_ candidates: [DiscoveredConsumer]) -> some View {
    if picking {
      LinkPicker(library: name, candidates: candidates, model: model) { picking = false }
    } else if candidates.count > Self.visibleLinks {
      HStack {
        Button { picking = true } label: {
          HStack(spacing: 5) {
            Text("＋ Link an app…")
            Tag(text: "\(candidates.count)")
          }
        }
        .buttonStyle(.flat(.accent, small: true))
        .help("Search the \(candidates.count) apps that use \(name) and link one")
        Spacer()
      }
      .padding(.horizontal, 12)
      .padding(.vertical, 8)
    } else {
      LinkChips(library: name, candidates: candidates, model: model)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }
  }

  private var isFolded: Bool {
    get { folded.split(separator: "\n").contains { $0 == name } }
    nonmutating set {
      var names = folded.split(separator: "\n").map(String.init).filter { $0 != name }
      if newValue { names.append(name) }
      folded = names.joined(separator: "\n")
    }
  }

  private var watch: Binding<Bool> {
    Binding(get: { row.library.isWatched }, set: { enabled in Task { await model.setWatch(name, enabled: enabled) } })
  }
}

/// The mockup's `.app`: one app linked to a library.
private struct LinkRow: View {
  let link: DryfitAPI.Link
  let model: MenuModel
  let actions: MenuActions
  @Environment(\.timeZone) private var timeZone

  var body: some View {
    HStack(spacing: 8) {
      StatusGlyph(kind: glyph, size: 16)
      VStack(alignment: .leading, spacing: 0) {
        Text(projectName(link.consumer)).font(Theme.bodySemibold).lineLimit(1).lh(13)
        caption
      }
      Spacer(minLength: 8)
      if link.status == .failed {
        if let failure = model.installFailure(in: link.consumer) {
          Button("Show output") { actions.showFailures(failure.id) }.buttonStyle(.flat(small: true))
        }
        Button("Restore") { Task { await model.restore(link.consumer, library: link.library) } }
          .buttonStyle(.flat(small: true))
          .disabled(model.isRestoring(link.consumer))
          .help("Put \(projectName(link.consumer)) back on the release of \(link.library)")
      } else if needsRestart {
        // The words say it; the amber is only a mark. Done clears the hint once the server is restarted.
        Button("Done") { model.restarted(link.consumer) }.buttonStyle(.flat(small: true)).help(restartHelp)
      }
      MoreMenu(label: "More for \(projectName(link.consumer))") {
        Button("Put back on the release") { Task { await model.restore(link.consumer, library: link.library) } }
          .disabled(model.isRestoring(link.consumer))
        Button("Show in Finder") { revealInFinder(link.consumer) }
      }
    }
    .padding(.horizontal, 12)
    .padding(.vertical, 8)
    .contentShape(.rect)
    .help(abbreviatedPath(link.consumer))
  }

  private var glyph: StatusGlyph.Kind {
    switch link.status {
    case .installed: .ok
    case .pending: .waiting
    case .failed: .failed
    }
  }

  private var needsRestart: Bool { link.status == .installed && model.restartNeeded.contains(link.consumer) }

  @ViewBuilder private var caption: some View {
    if link.status == .failed {
      Text("Install failed").font(Theme.small).foregroundStyle(Theme.bad).lh(12)
    } else if needsRestart {
      Text("Restart its dev server to load \(shortInstalled)").font(Theme.small).foregroundStyle(Theme.warn).lineLimit(2).lh(12)
    } else if link.status == .installed {
      let described = link.detail(timeZone: timeZone)
      Text(described.contains(" · dev ") ? "Dev build · " + shortVersion(described).dropFirst(4) : described)
        .muted().lineLimit(1)
    } else {
      Text(link.detail(timeZone: timeZone)).muted().lineLimit(1)
    }
  }

  /// "1.4.1" for what is installed.
  private var shortInstalled: String {
    let described = link.detail(timeZone: timeZone)
    return described.components(separatedBy: " · ").first ?? described
  }

  private var restartHelp: String {
    "\(shortVersion(link.detail(timeZone: timeZone))) is installed, and dryfit cleared \(projectName(link.consumer))’s caches. A running dev server shows it only after a restart. Click once you have."
  }
}

/// A few apps that use the library and are not linked to it, each linked with one click, then a menu
/// for any other folder. With more than a few the card offers a search instead (see `LinkPicker`).
private struct LinkChips: View {
  let library: String
  let candidates: [DiscoveredConsumer]
  let model: MenuModel

  var body: some View {
    FlowLayout(spacing: 6) {
      if !candidates.isEmpty {
        Text("Link to").muted()
      }
      ForEach(candidates) { consumer in
        let busy = model.isBusy(.link(library, consumer.root))
        Button {
          Task { await model.link(library, into: consumer.root) }
        } label: {
          HStack(spacing: 4) {
            if busy { Spin(size: 10) } else { Text("＋") }
            Text(projectName(consumer.root))
          }
        }
        .buttonStyle(.flat(.accent, small: true))
        .disabled(busy)
        .help("Install the dev build of \(library) into \(projectName(consumer.root))")
      }
      Menu {
        LinkMenuItems(library: library, model: model)
      } label: {
        Text(candidates.isEmpty ? "＋ Link an app…" : "Other…")
          .font(Theme.smallMedium)
          .foregroundStyle(candidates.isEmpty ? Theme.accent : Theme.muted)
          .padding(.horizontal, 9)
          .padding(.vertical, 3)
          .background(candidates.isEmpty ? Color.clear : Theme.button, in: .rect(cornerRadius: Theme.buttonRadius))
          .contentShape(.rect)
      }
      .menuStyle(.button)
      .buttonStyle(.plain)
      .menuIndicator(.hidden)
      .fixedSize()
    }
  }
}

private struct GroupCard: View {
  let group: DryfitAPI.Group
  let model: MenuModel
  let open: () -> Void

  var body: some View {
    HStack(spacing: 8) {
      Icon(kind: .group, size: 18, color: Theme.muted)
      Button(action: open) {
        VStack(alignment: .leading, spacing: 0) {
          Text(group.name).font(Theme.bodySemibold).lineLimit(1).lh(13)
          Text(apps).muted().lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(.rect)
      }
      .buttonStyle(.plain)
      if differs { Tag(text: "Versions differ", kind: .warn) }
      Menu {
        Section("Link into every app in \(group.name)") {
          ForEach(model.libraries) { row in
            Button(row.library.name) { Task { await model.linkGroup(group.name, library: row.library.name) } }
          }
        }
      } label: {
        HStack(spacing: 5) {
          if model.isBusy(.linkGroup(group.name)) { Spin(size: 10) }
          Text("Link…")
        }
        .font(Theme.smallMedium)
        .foregroundStyle(Theme.text)
        .padding(.horizontal, 9)
        .padding(.vertical, 3)
        .background(Theme.button, in: .rect(cornerRadius: Theme.buttonRadius))
        .contentShape(.rect)
      }
      .menuStyle(.button)
      .buttonStyle(.plain)
      .menuIndicator(.hidden)
      .fixedSize()
      .disabled(model.libraries.isEmpty)
      .help("Link a library into every app in \(group.name)")
    }
    .padding(.horizontal, 12)
    .padding(.vertical, 8)
    .card(radius: Theme.widgetCardRadius, fill: Theme.widgetCard)
  }

  private var apps: String { group.consumers.map(projectName).joined(separator: ", ") }

  private var differs: Bool { model.status?.warnings.contains { $0.group == group.name } == true }
}

// MARK: Messages when dryfit is not there

/// The mockup's `.center`: a glyph, a title, a line of text and the one thing to do.
private struct Message<Actions: View>: View {
  let icon: AnyView
  let title: String
  let text: String
  @ViewBuilder var actions: Actions

  var body: some View {
    VStack(spacing: 6) {
      icon.padding(.bottom, 4)
      Text(title).font(.system(size: 14.5, weight: .semibold)).multilineTextAlignment(.center).lh(14.5)
      Text(text).font(.system(size: 12.5)).foregroundStyle(Theme.muted).multilineTextAlignment(.center)
        .lineSpacing(2.6)
        .frame(maxWidth: 280).fixedSize(horizontal: false, vertical: true)
      actions
    }
    .frame(maxWidth: .infinity)
    .padding(.top, 28)
    .padding(.horizontal, 24)
    .padding(.bottom, 24)
  }
}

private func glyph(_ symbol: String) -> AnyView {
  AnyView(Text(symbol).font(.system(size: 30)).foregroundStyle(Theme.muted).frame(height: 30))
}

/// dryfit's service is not running: start it, or install the CLI it runs from.
private struct Unavailable: View {
  let model: MenuModel
  let actions: MenuActions

  var body: some View {
    Message(
      icon: glyph(model.cliMissing ? "⬇︎" : "⏻"), title: model.cliMissing ? "Install dryfit" : "dryfit is not running",
      text: model.cliMissing
        ? "The app runs dryfit's command-line tool in the background. It needs Node.js and npm."
        : "Start it to publish your libraries and install them into your apps."
    ) {
      VStack(spacing: 6) {
        if model.connection == .starting {
          progress("Starting…")
        } else if model.isBusy(.installCLI) {
          progress("Installing with npm…")
        } else if model.cliMissing {
          Button("Install dryfit") { Task { await model.installCLI() } }
            .buttonStyle(FlatButtonStyle(kind: .primary, roomy: true)).padding(.top, 10)
          Text("Runs \(DaemonLauncher.installCommand)").font(.system(size: 11.5, design: .monospaced)).foregroundStyle(Theme.muted)
        } else {
          Button("Start dryfit") { Task { await model.startDaemon() } }
            .buttonStyle(FlatButtonStyle(kind: .primary, roomy: true)).padding(.top, 10)
        }
        // Shown while the CLI is missing too: a failed install would otherwise just offer the button
        // again, with no word of why.
        if let error = model.startError, !model.isBusy(.installCLI) {
          Text(error).font(Theme.small).foregroundStyle(Theme.bad).multilineTextAlignment(.center)
            .textSelection(.enabled).frame(maxWidth: 290).fixedSize(horizontal: false, vertical: true).padding(.top, 2)
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

private struct Incompatible: View {
  let model: MenuModel
  let actions: MenuActions
  let daemonVersion: String

  var body: some View {
    Message(
      icon: AnyView(StatusGlyph(kind: .warning, size: 34)), title: "This app and dryfit \(daemonVersion) don't match",
      text: explanation
    ) {
      if model.outdatedVersion != nil {
        VStack(spacing: 6) {
          if model.isBusy(.updateCLI) {
            Spin()
            Text("Updating with npm…").font(.system(size: 11.5)).foregroundStyle(Theme.muted)
          } else {
            Button("Update dryfit") { Task { await model.updateCLI() } }
              .buttonStyle(FlatButtonStyle(kind: .primary, roomy: true)).padding(.top, 10)
            Text("Runs npm install --global @dryfit/cli@latest")
              .font(.system(size: 11.5, design: .monospaced)).foregroundStyle(Theme.muted)
          }
          if let error = model.updateError {
            Text(error).font(Theme.small).foregroundStyle(Theme.bad).multilineTextAlignment(.center)
              .textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
          }
        }
      } else if model.appIsOlder, let checkForUpdates = actions.checkForUpdates {
        Button("Check for updates…", action: checkForUpdates)
          .buttonStyle(FlatButtonStyle(kind: .primary, roomy: true)).padding(.top, 10)
      }
    }
  }

  private var explanation: String {
    if model.outdatedVersion != nil { return "dryfit is the older one." }
    if model.appIsOlder { return "This app is the older one." }
    return "They speak different versions of dryfit's API. Update the one that is older."
  }
}
