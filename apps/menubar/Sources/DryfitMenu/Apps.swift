import DryfitAPI
import Foundation
import SwiftUI

/// An app dryfit can link libraries into: one already linked, or one that depends on a registered
/// library and was found in the project folders or added by hand.
public struct AppSummary: Identifiable, Equatable {
  /// A registered library the app depends on, and the app's link to it when there is one.
  public struct Entry: Identifiable, Equatable {
    public let library: String
    /// The version range in the app's package.json, when known.
    public let range: String?
    public let link: DryfitAPI.Link?
    public var id: String { library }
  }

  public let root: String
  public let packageManager: String?
  public let libraries: [Entry]

  public var id: String { root }
  public var name: String { projectName(root) }
  public var linked: [DryfitAPI.Link] { libraries.compactMap(\.link) }
  public var unlinked: [Entry] { libraries.filter { $0.link == nil } }
  public var hasFailedInstall: Bool { linked.contains { $0.status == .failed } }
}

extension MenuModel {
  /// Every app that uses a registered library, by name.
  public var apps: [AppSummary] {
    guard let status else { return [] }
    let registered = Set(status.libraries.map(\.name))
    var found: [String: DiscoveredConsumer] = [:]
    let hidden = Set(hiddenApps ?? [])
    for consumer in addedApps + consumers where !hidden.contains(consumer.root) { found[consumer.root] = consumer }
    let roots = Set(found.keys).union(status.links.map(\.consumer))
    let sorted = roots.compactMap { root -> AppSummary? in
      let consumer = found[root]
      let links = status.links.filter { $0.consumer == root }
      var names = (consumer?.libraries ?? []).map(\.name).filter(registered.contains)
      for link in links where !names.contains(link.library) { names.append(link.library) }
      guard !names.isEmpty else { return nil }
      let entries = names.sorted().map { name in
        AppSummary.Entry(
          library: name,
          range: consumer?.libraries.first { $0.name == name }?.range,
          link: links.first { $0.library == name })
      }
      return AppSummary(root: root, packageManager: consumer?.packageManager.name, libraries: entries)
    }
    .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    return order.sorted(sorted, .apps, by: \.root)
  }

  /// Asks for an app's folder, then shows it with the libraries it can be linked to.
  public func chooseApp(navigation: AppNavigation) async {
    let chosen = await FolderPanel.choose(
      prompt: "Add App", message: "Choose the folder with your app's package.json.", startingAt: roots?.first)
    if let root = chosen.first { open(root, navigation: navigation, orAddAsLibrary: false) }
  }

  /// Works out what a folder is from its package.json and shows it: a registered library's page,
  /// an app that uses one of the libraries, or (when `orAddAsLibrary`) the form that adds a library.
  public func open(_ root: String, navigation: AppNavigation, orAddAsLibrary: Bool) {
    let root = normalizedPath(root)
    actionError = nil
    if let library = status?.libraries.first(where: { $0.root == root }) {
      navigation.selection = .library(library.name)
      return
    }
    guard let manifest = PackageManifest.read(root) else {
      actionError = "\(projectName(root)) has no package.json. Choose the folder that holds it."
      return
    }
    let registered = Set(status?.libraries.map(\.name) ?? [])
    if manifest.dependencies.contains(where: { registered.contains($0.name) }) {
      // Adding an app the user hid earlier is asking to see it again.
      if hiddenApps?.contains(root) == true {
        hiddenApps?.removeAll { $0 == root }
        Task { await showApp(root) }
      }
      if !(consumers + addedApps).contains(where: { $0.root == root }) {
        addedApps.append(
          DiscoveredConsumer(
            root: root, name: manifest.name, libraries: manifest.dependencies,
            packageManager: .init(name: PackageManifest.packageManager(in: root))))
      }
      navigation.selection = .app(root)
    } else if orAddAsLibrary {
      navigation.libraryEditor = LibraryEditorRequest(root: root)
    } else if registered.isEmpty {
      actionError = "Add a library first, then add the apps that use it."
    } else {
      actionError = "\(projectName(root)) does not depend on any of your libraries. Add one to its package.json, then add the app again."
    }
  }
}

/// The parts of a package.json that tell whether a folder is an app using a library.
struct PackageManifest: Decodable {
  let name: String?
  private let dependencyFields: [String: [String: String]]

  var dependencies: [DiscoveredConsumer.Dependency] {
    Self.fields.flatMap { field -> [DiscoveredConsumer.Dependency] in
      let entries: [String: String] = dependencyFields[field] ?? [:]
      return entries.keys.sorted().map { name in
        DiscoveredConsumer.Dependency(name: name, field: field, range: entries[name] ?? "")
      }
    }
  }

  private static let fields = ["dependencies", "devDependencies", "peerDependencies", "optionalDependencies"]

  private struct Key: CodingKey {
    var stringValue: String
    var intValue: Int? { nil }
    init(stringValue: String) { self.stringValue = stringValue }
    init?(intValue: Int) { nil }
  }

  init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: Key.self)
    name = try? container.decodeIfPresent(String.self, forKey: Key(stringValue: "name"))
    var fields: [String: [String: String]] = [:]
    for field in Self.fields {
      fields[field] = (try? container.decodeIfPresent([String: String].self, forKey: Key(stringValue: field))) ?? nil
    }
    dependencyFields = fields
  }

  static func read(_ root: String) -> PackageManifest? {
    let url = URL(filePath: root).appending(path: "package.json")
    guard let data = try? Data(contentsOf: url) else { return nil }
    return try? JSONDecoder().decode(PackageManifest.self, from: data)
  }

  /// The package manager a project uses, judged by its lockfile.
  static func packageManager(in root: String) -> String? {
    let lockfiles = [
      ("pnpm-lock.yaml", "pnpm"), ("yarn.lock", "yarn"), ("bun.lock", "bun"), ("bun.lockb", "bun"),
      ("package-lock.json", "npm"),
    ]
    let folder = URL(filePath: root)
    return lockfiles.first { FileManager.default.fileExists(atPath: folder.appending(path: $0.0).path) }?.1
  }
}

// MARK: App page

struct AppDetail: View {
  let root: String
  let model: MenuModel
  let navigation: AppNavigation
  let actions: MenuActions

  var body: some View {
    if let app = model.apps.first(where: { $0.root == root }) {
      content(app)
    }
  }

  private func content(_ app: AppSummary) -> some View {
    let failed = app.linked.filter { $0.status == .failed }
    return PinnedPage {
      PinnedHeader(symbol: "macwindow", tint: .purple, title: app.name, subtitle: summary(app)) {
        if let manager = app.packageManager { Chip(text: manager) }
      } actions: {
        IconButton(symbol: "folder", label: "Show \(app.name) in Finder", busy: false) { revealInFinder(app.root) }
        if !app.linked.isEmpty {
          Button { Task { await model.restore(app.root) } } label: {
            Label("Restore all", systemImage: "arrow.uturn.backward")
          }
          .buttonStyle(.pill)
          .disabled(model.isBusy(.restore(app.root, nil)) || app.libraries.contains { model.isBusy(.restore(app.root, $0.library)) })
          .help("Put every library in \(app.name) back on its release")
        }
      }
    } content: {
      if let error = model.actionError {
        ErrorBanner(message: error) { model.dismissActionError() }
      }
      ForEach(failed) { link in InstallFailedCallout(link: link, model: model, actions: actions) }
      VStack(alignment: .leading, spacing: 0) {
        SectionHeader("Libraries", count: app.libraries.count)
        HairlineGroup {
          ForEach(app.libraries) { entry in
            AppLibraryRow(app: app, entry: entry, model: model)
          }
        }
        Footnote("Your libraries that \(app.name) depends on. Restore puts that library's release back and keeps the others linked.")
      }
      DangerCard(
        title: "Hide \(app.name)",
        detail: app.linked.isEmpty
          ? "dryfit stops listing it. Settings can show it again."
          : "Restore it first: dryfit only hides apps on released versions.",
        button: "Hide", enabled: app.linked.isEmpty && !model.isBusy(.hide(app.root))
      ) { Task { await model.hideApp(app.root, navigation: navigation) } }
    }
  }

  private func summary(_ app: AppSummary) -> String {
    switch app.linked.count {
    case 0: "Uses released versions"
    case 1: "Uses the dev build of \(app.linked[0].library)"
    default: "Uses dev builds of \(app.linked.count) libraries"
    }
  }
}

private struct AppLibraryRow: View {
  let app: AppSummary
  let entry: AppSummary.Entry
  let model: MenuModel
  @Environment(\.timeZone) private var timeZone

  var body: some View {
    GroupRow {
      if let link = entry.link {
        StatusIcon(condition: link.condition)
      } else {
        Image(systemName: "shippingbox").foregroundStyle(DS.muted).frame(width: 18).accessibilityHidden(true)
      }
      TwoLine(title: entry.library, caption: detail, titleFont: DS.rowTitle)
        .frame(maxWidth: .infinity, alignment: .leading)
        .layoutPriority(1)
      if entry.link?.status == .failed {
        Chip(text: "Install failed", kind: .failed)
      } else {
        BuildChip(dev: entry.link != nil)
      }
      if entry.link == nil {
        Button("Link") { Task { await model.link(entry.library, into: app.root) } }
          .buttonStyle(.accentPill(busy: model.isBusy(.link(entry.library, app.root))))
          .help("Install the dev build of \(entry.library) into \(app.name)")
      } else {
        Button("Restore") { Task { await model.restore(app.root, library: entry.library) } }
          .buttonStyle(.pill(busy: model.isBusy(.restore(app.root, entry.library))))
          .disabled(model.isBusy(.restore(app.root, nil)))
          .help("Put \(app.name) back on the release of \(entry.library)")
      }
    }
    .contextMenu {
      Button("Show Installed Copy in Finder") { revealInFinder(app.root + "/node_modules/" + entry.library) }
    }
  }

  private var detail: String {
    if let link = entry.link { return link.detail(timeZone: timeZone) }
    return entry.range.map(describeDependency) ?? "Released version"
  }
}
