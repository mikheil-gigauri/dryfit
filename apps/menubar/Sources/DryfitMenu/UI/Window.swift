import DryfitAPI
import SwiftUI

/// The dryfit window, drawn from the mockup's `.win`: a sidebar that is always there and a page.
/// There is no toolbar and no title bar; the window's own buttons float over the sidebar's corner.
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
    HStack(spacing: 0) {
      Sidebar(model: model, navigation: navigation)
      detail
        .frame(minWidth: 480, maxWidth: .infinity, minHeight: 460, maxHeight: .infinity)
        .background(Theme.window)
    }
    .ignoresSafeArea()
    .font(Theme.body)
    .foregroundStyle(Theme.text)
    .background(WindowChrome())
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
      SettingsPage(model: model, actions: actions)
    } else if model.connection == .online, navigation.selection == nil || !exists(navigation.selection) {
      WelcomePage(model: model, navigation: navigation)
    } else {
      connected
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

  @ViewBuilder private var connected: some View {
    switch model.connection {
    case .online:
      switch navigation.selection {
      case .library(let name) where model.libraries.contains { $0.id == name }:
        LibraryPage(name: name, model: model, navigation: navigation, actions: actions)
      case .app(let root) where model.apps.contains { $0.root == root }:
        AppPage(root: root, model: model, navigation: navigation, actions: actions)
      case .group(let name) where model.status?.groups.contains { $0.name == name } == true:
        GroupPage(name: name, model: model, navigation: navigation)
      default:
        WelcomePage(model: model, navigation: navigation)
      }
    case .offline, .starting:
      StatePage { ServiceUnavailable(model: model, actions: actions) }
    case .connecting:
      StatePage {
        Center(glyph: AnyView(Color.clear.frame(height: 30)), title: "Looking for dryfit…") { Spin().padding(.top, 2) }
      }
    case .incompatible(let daemonVersion):
      StatePage { IncompatibleState(model: model, actions: actions, daemonVersion: daemonVersion) }
    }
  }
}

// MARK: Page chrome

/// A page: its header, pinned, and below it what scrolls. Once content has scrolled under the header a
/// hairline and a soft shadow show where it ends.
struct Page<Top: View, Content: View>: View {
  @ViewBuilder var top: Top
  @ViewBuilder var content: Content
  @State private var scrolled = false

  var body: some View {
    VStack(spacing: 0) {
      top
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.window)
        .overlay(alignment: .bottom) { Rectangle().fill(scrolled ? Theme.hairline : .clear).frame(height: 1) }
        .shadow(color: .black.opacity(scrolled ? 0.25 : 0), radius: 7, y: 6)
        .zIndex(1)
      ScrollView {
        VStack(alignment: .leading, spacing: 22) { content }
          .padding(.horizontal, 28)
          .padding(.top, 18)
          .padding(.bottom, 36)
          .frame(maxWidth: 780, alignment: .leading)
          .frame(maxWidth: .infinity, alignment: .leading)
      }
      .onScrollGeometryChange(for: Bool.self) { $0.contentOffset.y > 0.5 } action: { _, now in
        withAnimation(.easeOut(duration: 0.15)) { scrolled = now }
      }
    }
  }
}

/// A page's header (`.top`): a tile, the name with chips beside it, a line under it, and the page's
/// actions at the far end.
struct PageTop<Chips: View, Sub: View, Actions: View>: View {
  var tile: (icon: Icon.Kind, tint: Color, color: Color)? = nil
  let title: String
  @ViewBuilder var chips: Chips
  @ViewBuilder var sub: Sub
  @ViewBuilder var actions: Actions

  var body: some View {
    HStack(spacing: 14) {
      if let tile {
        Icon(kind: tile.icon, size: 24, color: tile.color)
          .frame(width: 44, height: 44)
          .background(tile.tint, in: .rect(cornerRadius: 12))
      }
      VStack(alignment: .leading, spacing: 3) {
        HStack(spacing: 10) {
          Text(title).font(.system(size: 21, weight: .semibold)).lineLimit(1).lh(21, 1.15)
          chips
        }
        HStack(spacing: 8) { sub }.foregroundStyle(Theme.muted).lh(13)
      }
      Spacer(minLength: 14)
      HStack(spacing: 10) { actions }
    }
    .padding(.horizontal, 28)
    .padding(.top, 20)
    .padding(.bottom, 14)
  }
}

/// The header of a page that is only a title (`.top.plain`).
struct PlainTop: View {
  let title: String
  var body: some View {
    Text(title).font(.system(size: 21, weight: .semibold)).lh(21, 1.15)
      .frame(maxWidth: .infinity, alignment: .leading)
      .padding(.horizontal, 28)
      .padding(.top, 18)
      .padding(.bottom, 12)
  }
}

/// A page with no content of its own, only a state in the middle.
struct StatePage<Content: View>: View {
  @ViewBuilder var content: Content
  var body: some View {
    Page { PlainTop(title: "dryfit") } content: { content }
  }
}

// MARK: The window itself

/// Makes the window what the mockup draws: no title bar and no title, its buttons over the sidebar, and
/// movable by any part of it that is not a control.
private struct WindowChrome: NSViewRepresentable {
  func makeNSView(context: Context) -> NSView { Anchor() }
  func updateNSView(_ view: NSView, context: Context) {}

  private final class Anchor: NSView {
    override func viewDidMoveToWindow() {
      guard let window else { return }
      window.titlebarAppearsTransparent = true
      window.titleVisibility = .hidden
      window.isMovableByWindowBackground = true
      window.styleMask.insert(.fullSizeContentView)
      window.backgroundColor = NSColor(name: nil) { $0.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? NSColor(srgbRed: 0x1e / 255, green: 0x1e / 255, blue: 0x21 / 255, alpha: 1) : NSColor(srgbRed: 0xfb / 255, green: 0xfb / 255, blue: 0xfc / 255, alpha: 1) }
    }
  }
}
