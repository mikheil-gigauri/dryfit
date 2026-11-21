import DryfitAPI
import SwiftUI

/// The window's left column, drawn from the mockup's `.side`. It is always there: nothing hides it.
/// Rows move with ↑ and ↓, reorder by drag (or ⌥⌘↑ and ⌥⌘↓), and each list keeps the order the user
/// gave it.
struct Sidebar: View {
  let model: MenuModel
  @Bindable var navigation: AppNavigation
  @State private var filter = ""
  @AppStorage("sidebarAppsExpanded") private var appsExpanded = true

  private var filtering: Bool { !filter.trimmingCharacters(in: .whitespaces).isEmpty }
  private func matches(_ name: String) -> Bool { !filtering || name.localizedStandardContains(filter) }

  var body: some View {
    let allApps = model.apps
    let apps = allApps.filter { matches($0.name) }
    let groups = model.groups.filter { matches($0.name) }
    let libraries = model.libraries.filter { matches($0.library.name) }
    VStack(spacing: 0) {
      // Room for the window's own buttons, which float over this corner.
      Color.clear.frame(height: 26)
      Well {
        Icon(kind: .search, size: 13)
        TextField("", text: $filter, prompt: Text("Filter").foregroundStyle(Theme.muted))
          .textFieldStyle(.plain)
          .foregroundStyle(Theme.text)
          .focusEffectDisabled()
          .accessibilityLabel("Filter")
      }
      .padding(.bottom, 4)

      ScrollView {
        VStack(spacing: 0) {
          header("Libraries", top: 8)
          ForEach(libraries) { row in
            Item(
              name: row.library.name, icon: .library, selected: navigation.selection == .library(row.library.name),
              trailing: row.links.contains { $0.status == .failed } ? .failed : .count(row.links.count),
              caption: caption(row)
            ) { navigation.selection = .library(row.library.name) }
              .contextMenu {
                Button("Sync Now") { Task { await model.sync(row.library.name) } }
                Button("Show in Finder") { revealInFinder(row.library.root) }
                moveItems(.libraries, row.id, model.libraries.map(\.id))
              }
              .reorderable(model, .libraries, row.id, model.libraries.map(\.id), enabled: !filtering)
          }
          if model.libraries.isEmpty {
            Text("No libraries yet").foregroundStyle(Theme.muted).lh(13).padding(.vertical, 5).padding(.leading, 34)
              .frame(maxWidth: .infinity, alignment: .leading)
          }
          if !apps.isEmpty {
            Button { withAnimation(.snappy(duration: 0.15)) { appsExpanded.toggle() } } label: {
              header("Apps", count: allApps.count)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(appsExpanded ? "Collapse apps" : "Expand apps")
            if appsExpanded {
              ForEach(apps) { app in
                Item(
                  name: app.name, icon: .app, selected: navigation.selection == .app(app.root),
                  trailing: app.hasFailedInstall ? .failed : !app.linked.isEmpty ? .dev : .none,
                  caption: caption(app)
                ) { navigation.selection = .app(app.root) }
                  .contextMenu {
                    Button("Show in Finder") { revealInFinder(app.root) }
                    Divider()
                    Button("Hide App") { Task { await model.hideApp(app.root, navigation: navigation) } }
                      .disabled(!app.linked.isEmpty)
                    moveItems(.apps, app.root, apps.map(\.root))
                  }
                  .reorderable(model, .apps, app.root, allApps.map(\.root), enabled: !filtering)
              }
            }
          }
          if !groups.isEmpty {
            header("Groups")
            ForEach(groups) { group in
              Item(
                name: group.name, icon: .group, selected: navigation.selection == .group(group.name),
                trailing: model.status?.warnings.contains { $0.group == group.name } == true ? .differ : .count(group.consumers.count),
                caption: group.consumers.count == 1 ? "1 app" : "\(group.consumers.count) apps"
              ) { navigation.selection = .group(group.name) }
                .contextMenu { moveItems(.groups, group.name, groups.map(\.name)) }
                .reorderable(model, .groups, group.name, model.groups.map(\.name), enabled: !filtering)
            }
          }
        }
      }
      .scrollIndicators(.never)
      .focusable()
      .focusEffectDisabled()
      .onKeyPress(.upArrow) { step(-1, among: visibleItems(libraries, apps, groups)) }
      .onKeyPress(.downArrow) { step(1, among: visibleItems(libraries, apps, groups)) }

      foot
    }
    .padding(.top, 14)
    .padding(.horizontal, 10)
    .padding(.bottom, 10)
    .frame(width: 236)
    .frame(maxHeight: .infinity)
    .background(Theme.sidebar)
    .overlay(alignment: .trailing) { Rectangle().fill(Theme.hairline).frame(width: 1) }
    .font(Theme.body)
    .foregroundStyle(Theme.text)
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

  // MARK: Pieces

  /// A section's name (`.sg`): small, spaced, with how many it holds.
  private func header(_ title: String, count: Int? = nil, top: CGFloat = 12) -> some View {
    HStack {
      Text(title).textCase(.uppercase).tracking(0.44)
      Spacer()
      if let count { Text("\(count)").font(.system(size: 11, weight: .medium)).foregroundStyle(Theme.faint) }
    }
    .font(.system(size: 11, weight: .semibold))
    .foregroundStyle(Theme.muted)
    .lh(11)
    .padding(.horizontal, 8)
    .padding(.top, top)
    .padding(.bottom, 4)
    .contentShape(.rect)
  }

  private var foot: some View {
    VStack(alignment: .leading, spacing: 0) {
      Hair()
      HStack {
        Menu {
          Button("Add Library…") { Task { await model.chooseLibraryFolder(navigation: navigation) } }
          Button("Add App…") { Task { await model.chooseApp(navigation: navigation) } }
          Divider()
          Button("New Group…") { navigation.groupEditor = .new }
        } label: {
          Text("＋ Add ▾").font(.system(size: 12, weight: .medium)).foregroundStyle(Theme.text)
            .lh(12).padding(.vertical, 3).padding(.leading, 2).padding(.trailing, 9)
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
        .disabled(model.connection != .online)
        .help("Add a library, an app or a group")
        Spacer()
        Button { navigation.selection = .settings } label: {
          Icon(kind: .gear, size: 16, color: navigation.selection == .settings ? Theme.accent : Theme.faint)
            .padding(.horizontal, 6).padding(.vertical, 2)
        }
        .buttonStyle(.plain)
        .help("Settings (⌘,)")
        .accessibilityLabel("Settings")
      }
      .padding(.top, 8)
      .padding(.horizontal, 8)
      if let activity = model.activity {
        HStack(spacing: 6) {
          Spin()
          Text(activity).lineLimit(1).truncationMode(.middle)
        }
        .muted()
        .padding(.top, 2)
        .accessibilityElement(children: .combine)
      }
    }
  }

  /// What the list shows, top to bottom: the rows ↑ and ↓ walk through.
  private func visibleItems(_ libraries: [LibraryRow], _ apps: [AppSummary], _ groups: [DryfitAPI.Group]) -> [SidebarItem] {
    libraries.map { .library($0.library.name) } + (appsExpanded ? apps.map { .app($0.root) } : [])
      + groups.map { .group($0.name) }
  }

  private func step(_ offset: Int, among items: [SidebarItem]) -> KeyPress.Result {
    guard !items.isEmpty else { return .ignored }
    let current = navigation.selection.flatMap { items.firstIndex(of: $0) }
    let next = current.map { min(max($0 + offset, 0), items.count - 1) } ?? (offset > 0 ? 0 : items.count - 1)
    navigation.selection = items[next]
    return .handled
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

/// One row (`.si`): an icon, the name, and at the end what matters most.
private struct Item: View {
  enum Trailing: Equatable { case none, failed, dev, differ, count(Int) }

  let name: String
  let icon: Icon.Kind
  let selected: Bool
  let trailing: Trailing
  let caption: String
  let action: () -> Void

  var body: some View {
    HStack(spacing: 9) {
      Icon(kind: icon, size: 15).frame(width: 16)
      Text(name).font(.system(size: 13, weight: selected ? .semibold : .regular)).lineLimit(1).truncationMode(.tail)
        .frame(maxWidth: .infinity, alignment: .leading)
      switch trailing {
      case .none: EmptyView()
      case .failed: Dot(color: Theme.bad)
      case .dev: Tag(text: "DEV", kind: .dev, size: 10, inset: 6)
      case .differ: Tag(text: "differ", kind: .warn, size: 10, inset: 6)
      case .count(let n): Text("\(n)").font(.system(size: 11)).foregroundStyle(Theme.faint)
      }
    }
    .lh(13)
    .padding(.horizontal, 8)
    .padding(.vertical, 5)
    .background(selected ? Theme.selection : .clear, in: .rect(cornerRadius: 8))
    .contentShape(.rect(cornerRadius: 8))
    .onTapGesture(perform: action)
    .help(caption)
    .accessibilityElement(children: .combine)
    .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
    .accessibilityValue(trailing == .failed ? "Install failed. \(caption)" : caption)
    .accessibilityAction(.default, action)
  }
}

extension View {
  /// Drag a row onto another of its list to move it there.
  fileprivate func reorderable(_ model: MenuModel, _ kind: ItemOrder.Kind, _ id: String, _ ids: [String], enabled: Bool) -> some View {
    modifier(Reorderable(model: model, kind: kind, id: id, ids: ids, enabled: enabled))
  }
}

private struct Reorderable: ViewModifier {
  let model: MenuModel
  let kind: ItemOrder.Kind
  let id: String
  let ids: [String]
  let enabled: Bool
  @State private var targeted = false

  private var token: String { "\(kind)\u{1}\(id)" }

  func body(content: Content) -> some View {
    if enabled {
      content
        .draggable(token)
        .dropDestination(for: String.self) { items, _ in
          guard let dragged = items.first, dragged.hasPrefix("\(kind)\u{1}") else { return false }
          let from = String(dragged.dropFirst("\(kind)\u{1}".count))
          guard let source = ids.firstIndex(of: from), let target = ids.firstIndex(of: id), source != target else { return false }
          model.move(kind, ids: ids, from: IndexSet(integer: source), to: source < target ? target + 1 : target)
          return true
        } isTargeted: { targeted = $0 }
        .overlay(alignment: .top) {
          if targeted { Capsule().fill(Theme.accent).frame(height: 2).padding(.horizontal, 8) }
        }
    } else {
      content
    }
  }
}
