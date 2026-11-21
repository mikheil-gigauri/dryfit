import AppKit
import DryfitAPI
import SwiftUI

/// "~/code/shop" for "/Users/me/code/shop".
func abbreviatedPath(_ path: String) -> String {
  (path as NSString).abbreviatingWithTildeInPath
}

func revealInFinder(_ path: String) {
  NSWorkspace.shared.activateFileViewerSelecting([URL(filePath: path)])
}

extension DryfitAPI.Link {
  func detail(timeZone: TimeZone) -> String {
    switch status {
    case .failed: "Install failed"
    case .pending: "Waiting for a sync"
    case .installed: installedVersion.map { DevVersion.describe($0, timeZone: timeZone) } ?? "Installed"
    }
  }
}

/// Where an app's package.json gets a library from, said plainly: "^1.3.0 from the registry", or
/// "Local file acme-ui-1.0.0.tgz" for a dependency that is not a version range at all.
func describeDependency(_ spec: String) -> String {
  let spec = spec.trimmingCharacters(in: .whitespaces)
  func last(_ path: Substring) -> String {
    let name = (String(path) as NSString).lastPathComponent
    return name.isEmpty ? String(path) : name
  }
  if spec.hasPrefix("file:") { return "Local file " + last(spec.dropFirst(5)) }
  if spec.hasPrefix("link:") || spec.hasPrefix("portal:") {
    return "Linked folder " + last(spec.drop { $0 != ":" }.dropFirst())
  }
  if spec.hasPrefix("workspace:") { return "From the workspace" }
  if spec.hasPrefix("git") || spec.hasPrefix("github:") || spec.contains(".git") { return "From git" }
  if spec.hasPrefix("http:") || spec.hasPrefix("https:") { return "From a URL" }
  if spec.hasPrefix("npm:") { return spec.dropFirst(4) + " from the registry" }
  if spec.hasPrefix(".") || spec.hasPrefix("/") || spec.hasPrefix("~") { return "Local folder " + last(Substring(spec)) }
  return "\(spec) from the registry"
}

extension Library {
  func published(timeZone: TimeZone) -> String {
    guard let version = lastPublishedVersion else { return "Not published yet" }
    return DevVersion.describe(version, timeZone: timeZone)
  }
}

/// The contents of a "Link to App" menu: projects found that use the library, then any folder.
struct LinkMenuItems: View {
  let library: String
  let model: MenuModel

  var body: some View {
    let candidates = model.linkCandidates(for: library)
    if !candidates.isEmpty {
      Section("Apps that use \(library)") {
        ForEach(candidates) { consumer in
          Button(projectName(consumer.root)) {
            Task { await model.link(library, into: consumer.root) }
          }
        }
      }
    } else {
      Text(model.isBusy(.discover) ? "Looking for apps…" : "No other app in your project folders uses \(library)")
    }
    Divider()
    Button("Choose App…") { Task { await model.chooseAppAndLink(library) } }
    Button("Look Again") { Task { await model.discoverConsumers() } }
  }
}
