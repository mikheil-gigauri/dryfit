import DryfitAPI
import Foundation
import SwiftUI
import Testing

@testable import DryfitMenu

private let names = [
  "billing", "checkout-web", "customer-portal", "dashboard", "docs-site", "email-templates", "help-center",
  "invoices", "landing", "marketing-site", "mobile-web", "onboarding", "orders", "partner-portal", "payments",
  "pricing", "reports", "search", "settings-app", "status-page", "support-desk", "team-admin", "tracking",
  "vendor-hub", "web-embed", "widgets", "wiki", "workflows",
]

/// The pages of the dryfit window, at the sizes they open at.
@MainActor @Suite(.serialized) struct WindowTests {
  private func window(_ model: MenuModel, _ selection: SidebarItem?, height: CGFloat = 820, named name: String) {
    let navigation = AppNavigation()
    navigation.selection = selection
    assertSnapshot(
      of: MainWindow(model: model, navigation: navigation, actions: MenuActions()), named: name,
      size: CGSize(width: 900, height: height))
  }

  /// Twenty-eight apps could be linked: the page lists five, with a search and a count, not all of them.
  @Test(.enabled(if: Snapshots.comparable, Comment(rawValue: Snapshots.skipped))) func libraryWithManyApps() {
    let busy = model { model in
      model.connection = .online
      model.roots = ["/Users/me/code"]
      model.status = Status(
        daemon: health, libraries: [ui],
        links: [Link(library: "@acme/ui", consumer: "/Users/me/code/invoices", status: .failed)], groups: [])
      model.failures = [
        Failure(
          title: "Install of @acme/ui into invoices failed", detail: "npm ERR! code ERESOLVE", date: at,
          consumer: "/Users/me/code/invoices")
      ]
      model.consumers = names.map {
        DiscoveredConsumer(
          root: "/Users/me/code/\($0)", name: $0, libraries: [.init(name: "@acme/ui", range: "^1.3.0")],
          packageManager: .npm)
      }
    }
    window(busy, .library("@acme/ui"), height: 900, named: "window-library-many")
  }

  @Test(.enabled(if: Snapshots.comparable, Comment(rawValue: Snapshots.skipped))) func groupWithDifferingVersions() {
    let grouped = model { model in
      model.connection = .online
      model.status = Status(
        daemon: health, libraries: [ui, forms],
        links: [
          Link(library: "@acme/ui", consumer: shop, status: .installed, installedVersion: version),
          Link(library: "@acme/ui", consumer: admin, status: .installed, installedVersion: "1.3.0"),
        ],
        groups: [Group(name: "checkout", consumers: [shop, admin])])
    }
    window(grouped, .group("checkout"), height: 620, named: "window-group")
  }

  /// The sidebar filter keeps the page's own list in order and never hides a page you are on.
  @Test func filteringTheSidebarKeepsEveryAppAvailable() {
    let busy = model { model in
      model.connection = .online
      model.status = Status(daemon: health, libraries: [ui], links: [], groups: [])
      model.consumers = names.map {
        DiscoveredConsumer(
          root: "/Users/me/code/\($0)", name: $0, libraries: [.init(name: "@acme/ui", range: "^1.3.0")],
          packageManager: .npm)
      }
    }
    #expect(filterLinkCandidates(busy.consumers ?? [], matching: "portal").count == 2)
  }

  /// A group of many possible apps gets a search, a count, and a save error that says what failed.
  @Test(.enabled(if: Snapshots.comparable, Comment(rawValue: Snapshots.skipped))) func groupEditorWithManyApps() {
    let busy = model { model in
      model.connection = .online
      model.status = Status(daemon: health, libraries: [ui], links: [], groups: [])
      model.consumers = names.map {
        DiscoveredConsumer(
          root: "/Users/me/code/\($0)", name: $0, libraries: [.init(name: "@acme/ui", range: "^1.3.0")],
          packageManager: .npm)
      }
    }
    let editor = GroupEditor(request: .new, model: busy, navigation: AppNavigation())
    assertSnapshot(of: editor, named: "sheet-group-new", size: CGSize(width: 440, height: 600))
  }
}
