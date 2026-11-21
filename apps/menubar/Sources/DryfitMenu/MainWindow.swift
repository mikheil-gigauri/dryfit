import DryfitAPI
import SwiftUI
import UniformTypeIdentifiers

/// The dryfit window: every library and group, with everything the CLI can do, no terminal needed.
public struct MainWindow: View {
  let model: MenuModel
  @Bindable var navigation: AppNavigation
  let actions: MenuActions

  public init(model: MenuModel, navigation: AppNavigation, actions: MenuActions) {
    self.model = model
    self.navigation = navigation
    self.actions = actions
  }

  public var body: some View {
    NavigationSplitView {
      Sidebar(model: model, navigation: navigation)
        .navigationSplitViewColumnWidth(min: 180, ideal: 200, max: 300)
    } detail: {
      // The minimum size goes on the detail column, not the split view: on the split view it makes
      // the toolbar lag behind the sidebar while it opens, pushing the sidebar button into overflow.
      // Up into the title bar: a page's own controls sit level with the window's buttons.
      detail.frame(minWidth: 480, minHeight: 460)
    }
    .sheet(item: $navigation.libraryEditor) { request in
      LibraryEditor(root: request.root, model: model, navigation: navigation)
    }
    .sheet(item: $navigation.groupEditor) { request in
      GroupEditor(request: request, model: model, navigation: navigation)
    }
    .alert(
      "Restore \(model.driftedRestore.map { projectName($0.consumer) } ?? "the app") anyway?",
      isPresented: Binding(get: { model.driftedRestore != nil }, set: { if !$0 { model.driftedRestore = nil } })
    ) {
      Button("Restore anyway", role: .destructive) {
        if let request = model.driftedRestore {
          Task { await model.restore(request.consumer, library: request.library, force: true) }
        }
      }
      Button("Cancel", role: .cancel) {}
    } message: {
      Text("Its package.json changed after it was linked. Restoring puts back the version from before linking, and drops those changes.")
    }
    .task(id: navigation.wantsNewLibrary) {
      guard navigation.wantsNewLibrary, model.connection == .online else { return }
      navigation.wantsNewLibrary = false
      await model.chooseLibraryFolder(navigation: navigation)
    }
    .task(id: model.connection) {
      if model.connection == .online, model.consumers.isEmpty { await model.discoverConsumers() }
    }
    .dropDestination(for: URL.self) { urls, _ in
      guard model.connection == .online, let folder = urls.first(where: \.hasDirectoryPath) else { return false }
      model.open(folderPath(folder), navigation: navigation, orAddAsLibrary: true)
      return true
    }
    .showsInDock()
  }

  @ViewBuilder private var detail: some View {
    // Settings shows whatever the connection, so dryfit can be started or its log opened from there.
    if navigation.selection == .settings {
      SettingsView(model: model, actions: actions)
    } else if model.connection == .online, navigation.selection == nil || !exists(navigation.selection) {
      WelcomeView(model: model, navigation: navigation)
    } else {
      connectedDetail
    }
  }

  private func exists(_ item: SidebarItem?) -> Bool {
    switch item {
    case .library(let name): model.libraries.contains { $0.id == name }
    case .app(let root): model.apps.contains { $0.root == root }
    case .group(let name): model.status?.groups.contains { $0.name == name } == true
    case .settings, nil: false
    }
  }

  @ViewBuilder private var connectedDetail: some View {
    switch model.connection {
    case .online:
      switch navigation.selection {
      case .library(let name) where model.libraries.contains { $0.id == name }:
        LibraryDetail(name: name, model: model, navigation: navigation, actions: actions)
      case .app(let root) where model.apps.contains { $0.root == root }:
        AppDetail(root: root, model: model, navigation: navigation, actions: actions)
      case .group(let name) where model.status?.groups.contains { $0.name == name } == true:
        GroupDetail(name: name, model: model, navigation: navigation)
      default:
        WelcomeView(model: model, navigation: navigation)
      }
    case .offline, .starting:
      ServiceUnavailableView(model: model, actions: actions).frame(maxWidth: .infinity, maxHeight: .infinity)
    case .connecting:
      ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
    case .incompatible(let daemonVersion):
      IncompatibleView(model: model, actions: actions, daemonVersion: daemonVersion)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
  }
}

// MARK: Sidebar

/// The sidebar: the system's source list, so it is the window's floating glass column, moves with ↑
/// and ↓, selects and reorders the way every Mac list does. Each list keeps the order the user
/// dragged it into; Move Up and Move Down in a row's menu do the same from the keyboard.
private struct Sidebar: View {
  let model: MenuModel
  @Bindable var navigation: AppNavigation
  /// Narrows the three lists by name: with thirty apps, scrolling is the slow way to one.
  @State private var filter = ""
  @AppStorage("sidebarAppsExpanded") private var appsExpanded = true

  private var filtering: Bool { !filter.trimmingCharacters(in: .whitespaces).isEmpty }
  private func matches(_ name: String) -> Bool { !filtering || name.localizedStandardContains(filter) }

  var body: some View {
    let allApps = model.apps
    let apps = allApps.filter { matches($0.name) }
    let groups = model.groups.filter { matches($0.name) }
    let libraries = model.libraries.filter { matches($0.library.name) }
    List(selection: $navigation.selection) {
      Section {
        ForEach(libraries) { row in
          let failed = row.links.contains { $0.status == .failed }
          SidebarLabel(
            name: row.library.name, symbol: "shippingbox", failed: failed, dev: false,
            watched: row.library.isWatched, count: row.links.count, caption: caption(row), showsZero: true)
            .tag(SidebarItem.library(row.library.name))
            .contextMenu {
              Button("Sync Now") { Task { await model.sync(row.library.name) } }
              Button("Show in Finder") { revealInFinder(row.library.root) }
              moveItems(.libraries, row.id, model.libraries.map(\.id))
            }
        }
        .onMove(perform: filtering ? nil : { model.move(.libraries, ids: model.libraries.map(\.id), from: $0, to: $1) })
        if model.libraries.isEmpty, model.connection == .online {
          Text("No libraries yet").foregroundStyle(DS.muted).selectionDisabled()
        }
      } header: {
        SidebarHeader(title: "Libraries")
      }
      if !apps.isEmpty {
        Section(isExpanded: $appsExpanded) {
          ForEach(apps) { app in
            SidebarLabel(
              name: app.name, symbol: "macwindow", failed: app.hasFailedInstall, dev: !app.linked.isEmpty,
              watched: false, count: app.linked.count, caption: caption(app))
              .tag(SidebarItem.app(app.root))
              .contextMenu {
                Button("Show in Finder") { revealInFinder(app.root) }
                Divider()
                Button("Hide App") { Task { await model.hideApp(app.root, navigation: navigation) } }
                  .disabled(!app.linked.isEmpty)
                moveItems(.apps, app.root, apps.map(\.root))
              }
          }
          .onMove(perform: filtering ? nil : { model.move(.apps, ids: allApps.map(\.root), from: $0, to: $1) })
        } header: {
          SidebarHeader(title: "Apps", count: allApps.count)
        }
      }
      if !groups.isEmpty {
        Section {
          ForEach(groups) { group in
            SidebarLabel(
              name: group.name, symbol: "square.stack.3d.up", failed: false, dev: false, watched: false,
              count: group.consumers.count, caption: group.consumers.count == 1 ? "1 app" : "\(group.consumers.count) apps",
              differs: model.status?.warnings.contains { $0.group == group.name } == true)
              .tag(SidebarItem.group(group.name))
              .contextMenu { moveItems(.groups, group.name, groups.map(\.name)) }
          }
          .onMove(perform: filtering ? nil : { model.move(.groups, ids: groups.map(\.name), from: $0, to: $1) })
        } header: {
          SidebarHeader(title: "Groups")
        }
      }
    }
    .listStyle(.sidebar)
    .searchable(text: $filter, placement: .sidebar, prompt: "Filter")
    .environment(\.sidebarRowSize, .small)
    .font(DS.body)
    .safeAreaBar(edge: .bottom, spacing: 0) { bottomBar }
    .background {
      // ⌥⌘↑ and ⌥⌘↓ move the selected row, as Move Up and Move Down in its menu do.
      Group {
        Button("Move Up") { moveSelection(up: true) }.keyboardShortcut(.upArrow, modifiers: [.command, .option])
        Button("Move Down") { moveSelection(up: false) }.keyboardShortcut(.downArrow, modifiers: [.command, .option])
      }
      .opacity(0)
      .frame(width: 0, height: 0)
      .accessibilityHidden(true)
    }
  }

  @ViewBuilder private func moveItems(_ kind: ItemOrder.Kind, _ id: String, _ ids: [String]) -> some View {
    if ids.count > 1, let index = ids.firstIndex(of: id) {
      Divider()
      Button("Move Up") { model.move(kind, ids: ids, from: IndexSet(integer: index), to: index - 1) }
        .keyboardShortcut(.upArrow, modifiers: [.command, .option])
        .disabled(index == 0)
      Button("Move Down") { model.move(kind, ids: ids, from: IndexSet(integer: index), to: index + 2) }
        .keyboardShortcut(.downArrow, modifiers: [.command, .option])
        .disabled(index == ids.count - 1)
    }
  }

  /// Moves the selected library, app or group one place within its own list.
  private func moveSelection(up: Bool) {
    let (kind, id, ids): (ItemOrder.Kind, String, [String])
    switch navigation.selection {
    case .library(let name)?: (kind, id, ids) = (.libraries, name, model.libraries.map(\.id))
    case .app(let root)?: (kind, id, ids) = (.apps, root, model.apps.map(\.root))
    case .group(let name)?: (kind, id, ids) = (.groups, name, model.groups.map(\.name))
    default: return
    }
    guard let index = ids.firstIndex(of: id), up ? index > 0 : index < ids.count - 1 else { return }
    model.move(kind, ids: ids, from: IndexSet(integer: index), to: up ? index - 1 : index + 2)
  }

  private var bottomBar: some View {
    VStack(alignment: .leading, spacing: 6) {
      if let activity = model.activity {
        HStack(spacing: 6) {
          ProgressView().controlSize(.mini)
          Text(activity).lineLimit(1).truncationMode(.middle)
        }
        .font(DS.caption)
        .foregroundStyle(DS.muted)
        .accessibilityElement(children: .combine)
      }
      HStack(spacing: 6) {
        Menu {
          Button("Add Library…") { Task { await model.chooseLibraryFolder(navigation: navigation) } }
          Button("Add App…") { Task { await model.chooseApp(navigation: navigation) } }
          Divider()
          Button("New Group…") { navigation.groupEditor = .new }
        } label: {
          Label("Add", systemImage: "plus")
        }
        .menuStyle(.button)
        .buttonStyle(.borderless)
        .menuIndicator(.hidden)
        .fixedSize()
        .disabled(model.connection != .online)
        .help("Add a library, an app or a group")
        Spacer()
        Button {
          navigation.selection = .settings
        } label: {
          Image(systemName: "gearshape")
        }
        .buttonStyle(.borderless)
        .foregroundStyle(navigation.selection == .settings ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(.secondary))
        .help("Settings (⌘,)")
        .accessibilityLabel("Settings")
      }
    }
    .font(DS.body)
    .padding(.horizontal, 12)
    .padding(.vertical, 8)
  }

  private func caption(_ row: LibraryRow) -> String {
    let apps = if row.links.contains(where: { $0.status == .failed }) {
      "Install failed"
    } else {
      switch row.links.count {
      case 0: "Not linked"
      case 1: "Linked to 1 app"
      default: "Linked to \(row.links.count) apps"
      }
    }
    return row.library.isWatched ? "\(apps) · Auto-sync on" : apps
  }

  private func caption(_ app: AppSummary) -> String {
    if app.hasFailedInstall { return "Install failed" }
    let linked = app.linked.map(\.library)
    if !linked.isEmpty { return "Dev build of " + linked.joined(separator: ", ") }
    return "Uses " + app.libraries.map(\.library).joined(separator: ", ")
  }
}

/// A sidebar section's name, small and spaced, with how many it holds.
private struct SidebarHeader: View {
  let title: String
  var count: Int? = nil

  var body: some View {
    HStack {
      Text(title)
      Spacer()
      if let count { Text("\(count)").monospacedDigit() }
    }
    .font(.system(size: 11, weight: .semibold))
    .textCase(.uppercase)
    .tracking(0.5)
    .foregroundStyle(DS.muted)
    .padding(.trailing, 8)
  }
}

/// One sidebar row: a grey symbol, the name, an auto-sync mark, and at the end what matters most: a red
/// dot for a failed install, a DEV chip for an app on a dev build, otherwise how many apps it links.
private struct SidebarLabel: View {
  let name: String
  let symbol: String
  let failed: Bool
  let dev: Bool
  let watched: Bool
  let count: Int
  let caption: String
  var differs = false
  /// A library with no apps says 0; an app with none says nothing.
  var showsZero = false

  var body: some View {
    HStack(spacing: 8) {
      Image(systemName: symbol).foregroundStyle(.secondary).frame(width: 18).accessibilityHidden(true)
      Text(name).font(DS.body).lineLimit(1)
      Spacer(minLength: 4)
      if failed {
        StatusDot(color: .red)
      } else if dev {
        Chip(text: "DEV", kind: .dev)
      } else if differs {
        Chip(text: "differ", kind: .warning)
      } else if count == 0 && !showsZero {
        EmptyView()
      } else {
        Text("\(count)").font(DS.caption).foregroundStyle(DS.muted).monospacedDigit()
      }
    }
    .help(caption)
    .accessibilityElement(children: .combine)
    .accessibilityValue(failed ? "Install failed. \(caption)" : caption)
  }
}

// MARK: Welcome

private struct WelcomeView: View {
  let model: MenuModel
  let navigation: AppNavigation

  var body: some View {
    PinnedPage {
      Text("Welcome to dryfit").font(DS.title).frame(maxWidth: .infinity, alignment: .leading).frame(minHeight: 44)
    } content: {
      Text("dryfit publishes each change to a private registry on this Mac and installs it into your apps the way a release would. When you're done, it puts every app back exactly as it was.")
        .foregroundStyle(DS.muted)
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: 620, alignment: .leading)
      steps
      if let error = model.actionError {
        ErrorBanner(message: error) { model.dismissActionError() }
      }
    }
  }

  /// The first step not done yet is the one to do: it takes the primary button and a tint.
  private var steps: some View {
    let foldersDone = !(model.roots ?? []).isEmpty
    let libraryDone = !model.libraries.isEmpty
    let linkedDone = !(model.status?.links.isEmpty ?? true)
    let loginDone = model.startsAtLogin ?? true
    let current = [foldersDone, libraryDone, linkedDone, loginDone].firstIndex(of: false)
    return HairlineGroup {
      Step(number: 1, title: "Tell dryfit where your apps live", detail: rootsDetail, done: foldersDone, current: current == 0) {
        Button(foldersDone ? "Change…" : "Add folders…") { Task { await model.chooseProjectFolders() } }
          .buttonStyle(current == 0 ? .primaryPill : .pill)
      }
      Step(
        number: 2, title: "Add a library you're working on",
        detail: "Choose its folder. dryfit works out how to build it.", done: libraryDone, current: current == 1
      ) {
        if !libraryDone {
          Button("Add library…") { Task { await model.chooseLibraryFolder(navigation: navigation) } }
            .buttonStyle(current == 1 ? .primaryPill : .pill)
        }
      }
      Step(
        number: 3, title: "Link it to an app",
        detail: "dryfit lists the apps that use your library under Apps. Link one, then sync, or turn on Auto-sync.",
        done: linkedDone, current: current == 2
      ) {
        EmptyView()
      }
      if let startsAtLogin = model.startsAtLogin {
        Step(
          number: 4, title: "Keep it running",
          detail: "Start dryfit when you log in, so auto-sync is on again after a restart. Opening this app at login does not start it.",
          done: startsAtLogin, current: current == 3
        ) {
          if !startsAtLogin {
            Button("Start at login") { Task { await model.setStartAtLogin(true) } }
              .buttonStyle(.pill(busy: model.isBusy(.startAtLogin)))
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
          Circle().fill(.green)
          Image(systemName: "checkmark").font(.system(size: 11, weight: .bold)).foregroundStyle(.white)
        } else {
          Circle().strokeBorder(current ? Color.accentColor : DS.strongBorder, lineWidth: current ? 1.5 : 1)
          Text("\(number)").font(DS.caption.weight(.semibold)).monospacedDigit()
            .foregroundStyle(current ? Color.accentColor : DS.muted)
        }
      }
      .frame(width: 24, height: 24)
      .accessibilityLabel(done ? "Done" : "Step \(number)")
      TwoLine(title: title, caption: detail, titleFont: DS.rowTitle, wraps: true)
        .frame(maxWidth: .infinity, alignment: .leading)
      actions
    }
    .padding(.horizontal, 16)
    .padding(.vertical, 14)
    .background(current ? DS.accentTint : .clear)
  }
}

// MARK: Library

private struct LibraryDetail: View {
  let name: String
  let model: MenuModel
  let navigation: AppNavigation
  let actions: MenuActions
  @State private var confirmingRemoval = false
  @Environment(\.timeZone) private var timeZone

  var body: some View {
    if let row = model.libraries.first(where: { $0.id == name }) {
      content(row)
    }
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
    return PinnedPage {
      PinnedHeader(
        symbol: "shippingbox", tint: .release, title: library.name,
        subtitle: [published.built.map { "built \($0)" }, syncing ? "Syncing…" : nil]
          .compactMap { $0 }.joined(separator: " · "),
        mono: published.built == nil ? nil : library.lastPublishedVersion
      ) {
        if published.built != nil { Chip(text: "DEV BUILD", kind: .dev) }
      } actions: {
        AutoSyncToggle(isOn: Binding(
          get: { library.isWatched },
          set: { enabled in Task { await model.setWatch(name, enabled: enabled) } }))
          .disabled(model.isBusy(.watch(name)))
          .help(library.isWatched
            ? "Auto-sync is on: every change you save to \(name) is synced to its apps"
            : "Turn on to sync every change you save to \(name)")
        Button("Sync now") { Task { await model.sync(name) } }
          .buttonStyle(PillButtonStyle(kind: .primary, busy: syncing))
        .disabled(row.links.isEmpty)
        .help(row.links.isEmpty ? "Link an app first" : "Build, publish and install into every linked app")
      }
    } content: {
      if let error = model.actionError {
        ErrorBanner(message: error) { model.dismissActionError() }
      }
      ForEach(failed) { link in InstallFailedCallout(link: link, model: model, actions: actions) }

      VStack(alignment: .leading, spacing: 0) {
        SectionHeader("Linked apps", count: row.links.count)
        HairlineGroup {
          if links.isEmpty {
            GroupRow {
              Text("No app is linked yet. Link one below to install the dev build.").foregroundStyle(DS.muted)
            }
          } else {
            LinkedAppsHeader()
          }
          ForEach(links) { link in LinkedAppRow(link: link, model: model) }
        }
      }

      AvailableAppsSection(library: name, candidates: candidates, model: model)

      // Set once, rarely changed: a card of its own, but below what is used every day.
      VStack(alignment: .leading, spacing: 0) {
        SectionHeader("Build")
        HairlineGroup {
          ValueRow(label: "Command") {
            if let build = library.build.map({ BuildCommand(command: $0.command, args: $0.args).line }) {
              Text(build).font(DS.mono).lineLimit(1).truncationMode(.middle).textSelection(.enabled).help(build)
            } else {
              Text("No build step")
            }
          } trailing: {
            Button("Change…") { navigation.libraryEditor = LibraryEditorRequest(root: library.root) }.buttonStyle(.pill)
          }
          ValueRow(label: "Publishes") {
            Text(publishFolder(library)).font(DS.mono).lineLimit(1).truncationMode(.head).textSelection(.enabled)
          } trailing: {}
          ValueRow(label: "Library") {
            Text(abbreviatedPath(library.root)).font(DS.mono).lineLimit(1).truncationMode(.head).textSelection(.enabled)
          } trailing: {}
        }
      }

      DangerCard(
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

/// The switch for auto-sync with its name beside it.
struct AutoSyncToggle: View {
  @Binding var isOn: Bool

  var body: some View {
    HStack(spacing: 6) {
      Text("Auto-sync").font(DS.caption).foregroundStyle(DS.muted).accessibilityHidden(true)
      Toggle("Auto-sync", isOn: $isOn).toggleStyle(.switch).controlSize(.small).labelsHidden()
    }
    .fixedSize()
  }
}

// MARK: Group

private struct GroupDetail: View {
  let name: String
  let model: MenuModel
  let navigation: AppNavigation
  @State private var confirmingDeletion = false
  @Environment(\.timeZone) private var timeZone

  var body: some View {
    if let group = model.status?.groups.first(where: { $0.name == name }) {
      content(group)
    }
  }

  private func content(_ group: DryfitAPI.Group) -> some View {
    let warnings = model.status?.warnings.filter { $0.group == name } ?? []
    return PinnedPage {
      PinnedHeader(
        symbol: "square.stack.3d.up", tint: .purple, title: group.name,
        subtitle: "Link a library into all of these apps at once, and restore them together."
      ) {
        EmptyView()
      } actions: {
        PillMenu(busy: model.isBusy(.linkGroup(name))) {
          ForEach(model.status?.libraries ?? []) { library in
            Button(library.name) { Task { await model.linkGroup(name, library: library.name) } }
          }
        } label: {
          Text("Link library")
        }
        .disabled(model.status?.libraries.isEmpty ?? true)
        .help("Link a library into every app in \(name)")
        Button("Restore all") { Task { await model.restoreGroup(name) } }
          .buttonStyle(.pill(busy: model.isBusy(.restoreGroup(name))))
        .help("Put every app in \(name) back on released versions")
      }
    } content: {
      if let error = model.actionError {
        ErrorBanner(message: error) { model.dismissActionError() }
      }
      VStack(alignment: .leading, spacing: 0) {
        SectionHeader(title: "Apps", count: group.consumers.count) {
          Button("Edit…") { navigation.groupEditor = .edit(group) }.buttonStyle(.borderless)
        }
        HairlineGroup {
          ForEach(group.consumers, id: \.self) { consumer in
            GroupRow {
              TwoLine(title: projectName(consumer), caption: abbreviatedPath(consumer), titleFont: DS.rowTitle)
                .layoutPriority(1)
              Spacer(minLength: 8)
              let libraries = linkedLibraries(consumer)
              if libraries.isEmpty {
                Chip(text: "Released versions", kind: .release)
              } else {
                Chip(text: "Dev build of " + libraries.joined(separator: ", "), kind: .dev)
              }
            }
          }
        }
      }
      ForEach(Array(warnings.enumerated()), id: \.offset) { _, warning in
        Callout(
          condition: .warning, title: "\(warning.library) differs between these apps",
          message: warning.versions
            .map { "\(projectName($0.consumer)) is on \(DevVersion.describe($0.version, timeZone: timeZone))" }
            .joined(separator: " · ")
        ) {
          Button("Link \(warning.library) into both") { Task { await model.linkGroup(name, library: warning.library) } }
            .buttonStyle(.pill(busy: model.isBusy(.linkGroup(name))))
        }
      }
      DangerCard(
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
