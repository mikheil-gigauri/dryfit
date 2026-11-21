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

/// The menu bar window (ADR 0013): what dryfit is doing at a glance, with the everyday controls —
/// watch, sync, link, restore. Adding and changing things happens in the dryfit window, one click away.
/// The window itself is system glass; what it lists is content, drawn with hairlines rather than glass.
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
      Header(model: model) { show(nil) }
      Hairline()
      if model.connection == .online, let outdated = model.outdatedVersion {
        OutdatedBanner(model: model, version: outdated)
        Hairline()
      }
      switch model.connection {
      case .online:
        OnlineContent(model: model, actions: actions, show: show, addLibrary: addLibrary)
      case .offline, .starting:
        ServiceUnavailableView(model: model, actions: actions, compact: true)
      case .connecting:
        ProgressView().controlSize(.small).frame(maxWidth: .infinity).padding(28)
      case .incompatible(let daemonVersion):
        IncompatibleView(model: model, actions: actions, daemonVersion: daemonVersion)
      }
      Hairline()
      Footer(model: model, actions: actions, addLibrary: addLibrary) {
        navigation.showSettings { openWindow(id: mainWindowID) }
      }
    }
    .font(DS.body)
    .frame(width: 372)
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

// MARK: Header and footer

private struct Header: View {
  let model: MenuModel
  let openWindow: () -> Void

  var body: some View {
    HStack(spacing: 10) {
      VStack(alignment: .leading, spacing: 2) {
        Text("dryfit").font(DS.sheetTitle)
        HStack(spacing: 6) {
          StatusDot(color: dot)
          Text(subtitle).font(DS.caption).foregroundStyle(DS.muted).lineLimit(1)
        }
      }
      Spacer(minLength: 8)
      Button("Open dryfit", action: openWindow)
        .buttonStyle(.pill)
        .help("Open the dryfit window to add libraries, link apps and manage groups")
    }
    .padding(.horizontal, 16)
    .padding(.top, 14)
    .padding(.bottom, 12)
  }

  private var dot: Color {
    switch model.connection {
    case .online: model.failures.isEmpty ? .green : .red
    case .connecting, .starting: .yellow
    case .offline: Color.primary.opacity(0.25)
    case .incompatible: .orange
    }
  }

  /// What is wrong comes first: a failure is a count in words, not just a colour.
  private var subtitle: String {
    switch model.connection {
    case .online:
      let failures = model.failures.count
      if failures > 0 { return failures == 1 ? "Running · 1 needs attention" : "Running · \(failures) need attention" }
      if model.activity != nil { return "Running · syncing" }
      return model.status.map { "Running, version \($0.daemon.version)" } ?? "Running"
    case .connecting: return "Looking for dryfit…"
    case .starting: return "Starting…"
    case .offline: return "Not running"
    case .incompatible: return "Needs an update"
    }
  }
}

/// Always there, the same height whatever it shows: what dryfit is doing while it works, otherwise
/// the way to add a library (or, while dryfit is not running, its log), and Settings.
private struct Footer: View {
  let model: MenuModel
  let actions: MenuActions
  let addLibrary: () -> Void
  let showSettings: () -> Void

  var body: some View {
    HStack(spacing: 8) {
      if let activity = model.activity {
        ProgressView().controlSize(.mini)
        Text(activity).lineLimit(1).truncationMode(.middle)
      } else if model.connection == .online {
        // With no library yet, the page above already offers the same button.
        if !model.libraries.isEmpty {
          Button(action: addLibrary) {
            Label("Add library…", systemImage: "plus").labelStyle(PillLabelStyle()).contentShape(.rect)
          }
          .buttonStyle(.plain)
        }
      } else {
        Button("Open log", action: actions.openLog).buttonStyle(.plain)
      }
      Spacer(minLength: 8)
      Button(action: showSettings) {
        Image(systemName: "gearshape").font(.system(size: 14)).frame(width: 22, height: 22).hitTarget(CGSize(width: 22, height: 22))
      }
      .buttonStyle(.plain)
      .help("Settings (⌘,)")
      .accessibilityLabel("Settings")
    }
    .font(DS.caption)
    .foregroundStyle(DS.muted)
    .frame(minHeight: 22)
    .padding(.horizontal, 16)
    .padding(.vertical, 8)
  }
}

// MARK: Online

private struct OnlineContent: View {
  let model: MenuModel
  let actions: MenuActions
  let show: (SidebarItem?) -> Void
  let addLibrary: () -> Void

  var body: some View {
    if model.libraries.isEmpty && model.groups.isEmpty && banners.isEmpty {
      GetStarted(addLibrary: addLibrary)
    } else {
      // As tall as its content, scrolling past what fits under the menu bar.
      ScrollView { sections }
        .scrollBounceBehavior(.basedOnSize)
        .frame(maxHeight: 540)
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
        FailureBanner(failure: failure, more: banners.count - 1, model: model, actions: actions)
      }
      if let request = model.driftedRestore {
        DriftedRestoreBanner(request: request, model: model)
      }
      if let error = model.actionError {
        ErrorBanner(message: error) { model.dismissActionError() }
      }
      if model.libraries.isEmpty {
        GetStarted(addLibrary: addLibrary)
      }
      ForEach(model.libraries) { row in
        LibraryCard(row: row, model: model, actions: actions) { show(.library(row.library.name)) }
      }
      if !model.groups.isEmpty {
        Text("Groups")
          .font(DS.small.weight(.semibold))
          .textCase(.uppercase)
          .tracking(0.5)
          .foregroundStyle(DS.muted)
          .padding(.horizontal, 4)
          .padding(.top, 6)
        ForEach(model.groups) { group in
          GroupRowView(group: group, model: model) { show(.group(group.name)) }
        }
      }
    }
    .padding(.horizontal, 12)
    .padding(.vertical, 4)
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

private struct GetStarted: View {
  let addLibrary: () -> Void

  var body: some View {
    Centered(
      symbol: "shippingbox", tint: .release, title: "Test your library in your apps",
      text: "Add a library you're working on, and dryfit installs each change into the apps that use it."
    ) {
      Button("Add library", action: addLibrary).buttonStyle(.primaryPill).controlSize(.regular).padding(.top, 12)
    }
  }
}

/// A failure no link row shows: a build, or an auto-sync that stopped.
private struct FailureBanner: View {
  let failure: Failure
  let more: Int
  let model: MenuModel
  let actions: MenuActions

  var body: some View {
    Callout(condition: .failed, title: failure.title, message: firstLine, output: true) {
      Button(more > 0 ? "Show \(more + 1) failures" : "Show output") { actions.showFailures(failure.id) }
        .buttonStyle(.pill)
      // Clears every failure, so with more than one it says so.
      Button(more > 0 ? "Dismiss all" : "Dismiss") { model.clearFailures() }.buttonStyle(.pill)
    }
  }

  private var firstLine: String {
    failure.detail.split(whereSeparator: \.isNewline).first.map(String.init) ?? ""
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

/// A card's surface: lighter than the glass behind it, with a hairline edge.
extension View {
  fileprivate func cardSurface() -> some View {
    background(DS.groupFill, in: .rect(cornerRadius: 14))
      .overlay { RoundedRectangle(cornerRadius: 14).strokeBorder(DS.cardBorder, lineWidth: 0.5) }
  }
}

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
      header
      summary(candidates: candidates.count)
      if !isFolded {
        ForEach(shownLinks) { link in
          Hairline()
          LinkRowView(link: link, model: model, actions: actions)
        }
        if hiddenLinks > 0 {
          Hairline()
          Button(action: open) {
            HStack(spacing: 4) {
              Text("Show \(hiddenLinks) more linked app\(hiddenLinks == 1 ? "" : "s") in the window")
              Image(systemName: "chevron.right").font(.system(size: 10, weight: .semibold)).accessibilityHidden(true)
            }
            .font(DS.caption.weight(.medium))
            .foregroundStyle(Color.accentColor)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .contentShape(.rect)
          }
          .buttonStyle(.plain)
        }
        Hairline()
        linkFooter(candidates)
      }
    }
    .cardSurface()
  }

  private var name: String { row.library.name }

  private var header: some View {
    HStack(spacing: 8) {
      Button {
        withAnimation(.snappy) { isFolded.toggle() }
      } label: {
        Image(systemName: isFolded ? "chevron.right" : "chevron.down")
          .font(.system(size: 11, weight: .semibold))
          .foregroundStyle(DS.muted)
          .frame(width: 14, height: 22)
          .hitTarget(CGSize(width: 14, height: 22))
      }
      .buttonStyle(.plain)
      .accessibilityLabel(isFolded ? "Show \(name)'s apps" : "Hide \(name)'s apps")
      Button(action: open) {
        Text(name).font(DS.headline).lineLimit(1).truncationMode(.middle)
          .frame(maxWidth: .infinity, alignment: .leading)
          .contentShape(.rect)
      }
      .buttonStyle(.plain)
      .pointerStyle(.link)
      .help("Show \(name) in the dryfit window")
      Text("Auto-sync").font(DS.caption).foregroundStyle(DS.muted).accessibilityHidden(true)
      Toggle("Auto-sync \(name)", isOn: watch)
        .toggleStyle(.switch)
        .controlSize(.small)
        .labelsHidden()
        .disabled(model.isBusy(.watch(name)))
        .help(row.library.isWatched ? "Auto-sync is on: every change you save is synced" : "Auto-sync: sync every change you save")
      IconButton(symbol: "arrow.clockwise", label: "Sync \(name) now", busy: syncing) { Task { await model.sync(name) } }
    }
    .padding(.horizontal, 12)
    .padding(.top, 10)
    .padding(.bottom, 2)
  }

  private var syncing: Bool {
    model.isBusy(.sync(name)) || model.status?.jobs.running?.label == "sync \(name)"
  }

  private func summary(candidates: Int) -> some View {
    HStack(spacing: 6) {
      if row.links.isEmpty {
        Chip(text: "Not linked")
        if candidates > 0 { Text(candidates == 1 ? "1 app uses it" : "\(candidates) apps use it") }
      } else {
        let published = published
        if published.built != nil { Chip(text: "DEV", kind: .dev) }
        Text(published.version).font(DS.mono)
        if let built = published.built { Text("· built \(built)") }
        Text("· \(row.links.count) app\(row.links.count == 1 ? "" : "s")")
        if syncing {
          ProgressView().controlSize(.mini)
          Text("Syncing…")
        }
      }
    }
    .font(DS.caption)
    .foregroundStyle(DS.muted)
    .lineLimit(1)
    .padding(.leading, 34)
    .padding(.trailing, 12)
    .padding(.bottom, 10)
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
            Image(systemName: "plus").accessibilityHidden(true)
            Text("Link an app…")
            Chip(text: "\(candidates.count)")
          }
        }
        .buttonStyle(ChipButtonStyle())
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

/// "dev 14:32" for "1.4.1 · dev 14:32": the menu is narrow, and the window has the rest.
func shortVersion(_ described: String) -> String {
  guard let range = described.range(of: " · dev ") else { return described }
  return "dev " + described[range.upperBound...]
}

private struct LinkRowView: View {
  let link: DryfitAPI.Link
  let model: MenuModel
  let actions: MenuActions
  @Environment(\.timeZone) private var timeZone

  var body: some View {
    HStack(spacing: 8) {
      StatusIcon(condition: link.condition)
      VStack(alignment: .leading, spacing: 1) {
        Text(projectName(link.consumer)).font(DS.rowTitle).lineLimit(1)
        caption
      }
      Spacer(minLength: 8)
      if link.status == .failed {
        if let failure = model.installFailure(in: link.consumer) {
          Button("Show output") { actions.showFailures(failure.id) }.buttonStyle(.pill)
        }
        Button("Restore") { Task { await model.restore(link.consumer, library: link.library) } }
          .buttonStyle(.pill(busy: busy))
          .disabled(!busy && model.isRestoring(link.consumer))
          .help("Put \(projectName(link.consumer)) back on the release of \(link.library)")
      } else if needsRestart {
        // The words say it; the amber is only a mark. Done clears the hint once the server is restarted.
        Button("Done") { model.restarted(link.consumer) }.buttonStyle(.pill).help(restartHelp)
      }
      moreMenu
    }
    .padding(.horizontal, 12)
    .padding(.vertical, 8)
    .contentShape(.rect)
    .help(abbreviatedPath(link.consumer))
  }

  private var needsRestart: Bool { link.status == .installed && model.restartNeeded.contains(link.consumer) }

  @ViewBuilder private var caption: some View {
    if link.status == .failed {
      Text("Install failed").font(DS.caption).foregroundStyle(DS.badText)
    } else if needsRestart {
      Text("Restart its dev server to load this build").font(DS.caption).foregroundStyle(DS.warnText).lineLimit(2)
    } else if link.status == .installed {
      let described = link.detail(timeZone: timeZone)
      Text(described.contains(" · dev ") ? "Dev build · " + shortVersion(described).dropFirst(4) : described)
        .font(DS.caption).foregroundStyle(DS.muted).lineLimit(1)
    } else {
      Text(link.detail(timeZone: timeZone)).font(DS.caption).foregroundStyle(DS.muted).lineLimit(1)
    }
  }

  private var moreMenu: some View {
    Menu {
      Button("Put back on the release", systemImage: "arrow.uturn.backward") {
        Task { await model.restore(link.consumer, library: link.library) }
      }
      .disabled(model.isRestoring(link.consumer))
      Button("Show in Finder", systemImage: "folder") { revealInFinder(link.consumer) }
    } label: {
      Image(systemName: "ellipsis").font(.system(size: 13, weight: .semibold)).frame(width: 22, height: 22)
    }
    .menuStyle(.button)
    .buttonStyle(.borderless)
    .menuIndicator(.hidden)
    .fixedSize()
    .help("More for \(projectName(link.consumer))")
    .accessibilityLabel("More for \(projectName(link.consumer))")
  }

  private var busy: Bool { model.isBusy(.restore(link.consumer, link.library)) }

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
        Text("Link to").font(DS.caption).foregroundStyle(DS.muted)
      }
      ForEach(candidates) { consumer in
        let busy = model.isBusy(.link(library, consumer.root))
        Button {
          Task { await model.link(library, into: consumer.root) }
        } label: {
          HStack(spacing: 4) {
            if busy { ProgressView().controlSize(.mini) } else { Image(systemName: "plus").accessibilityHidden(true) }
            Text(projectName(consumer.root))
          }
        }
        .buttonStyle(ChipButtonStyle())
        .disabled(busy)
        .help("Install the dev build of \(library) into \(projectName(consumer.root))")
      }
      Menu {
        LinkMenuItems(library: library, model: model)
      } label: {
        Text(candidates.isEmpty ? "Link an app…" : "Other…")
          .font(DS.caption)
          .foregroundStyle(candidates.isEmpty ? Color.accentColor : DS.muted)
          .padding(.horizontal, 7)
          .padding(.vertical, 2)
          .contentShape(.rect)
      }
      .menuStyle(.button)
      .buttonStyle(.plain)
      .menuIndicator(.hidden)
      .fixedSize()
    }
  }
}

private struct GroupRowView: View {
  let group: DryfitAPI.Group
  let model: MenuModel
  let open: () -> Void

  var body: some View {
    HStack(spacing: 8) {
      Image(systemName: "square.stack.3d.up").font(.system(size: 15)).foregroundStyle(DS.muted)
        .frame(width: 22).accessibilityHidden(true)
      Button(action: open) {
        TwoLine(title: group.name, caption: apps, titleFont: DS.rowTitle)
          .frame(maxWidth: .infinity, alignment: .leading)
          .contentShape(.rect)
      }
      .buttonStyle(.plain)
      if differs { Chip(text: "Versions differ", kind: .warning) }
      PillMenu(busy: model.isBusy(.linkGroup(group.name))) {
        Section("Link into every app in \(group.name)") {
          ForEach(model.libraries) { row in
            Button(row.library.name) { Task { await model.linkGroup(group.name, library: row.library.name) } }
          }
        }
      } label: {
        Text("Link…")
      }
      .disabled(model.libraries.isEmpty)
      .help("Link a library into every app in \(group.name)")
      IconButton(
        symbol: "arrow.uturn.backward", label: "Put every app in \(group.name) back on released versions",
        busy: model.isBusy(.restoreGroup(group.name))
      ) { Task { await model.restoreGroup(group.name) } }
    }
    .font(DS.body)
    .padding(.horizontal, 12)
    .padding(.vertical, 8)
    .cardSurface()
  }

  private var apps: String { group.consumers.map(projectName).joined(separator: ", ") }

  private var differs: Bool { model.status?.warnings.contains { $0.group == group.name } == true }
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

// MARK: Not running

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

/// Above the menu while dryfit runs an older version than this app: the app updated itself, but the
/// CLI it runs comes from npm.
private struct OutdatedBanner: View {
  let model: MenuModel
  let version: String

  var body: some View {
    HStack(alignment: .center, spacing: 8) {
      StatusIcon(condition: .update)
      TwoLine(
        title: "dryfit \(version) is older than this app",
        caption: "Update it to \(model.appVersion ?? "the newest version") to get what is new.", titleFont: DS.medium,
        wraps: true)
      Spacer(minLength: 8)
      UpdateDryfitControl(model: model, prominent: false)
    }
    .padding(.horizontal, 16)
    .padding(.vertical, 10)
    .background(Color.orange.opacity(0.12))
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
