import AppKit
import DryfitAPI
import Foundation
import SwiftUI
import Testing

@testable import DryfitMenu

/// Apps named like a company's: enough of them that listing every one would fill the screen.
private let manyNames = [
  "billing", "checkout-web", "customer-portal", "dashboard", "docs-site", "email-templates", "help-center",
  "invoices", "landing", "marketing-site", "mobile-web", "onboarding", "orders", "partner-portal", "payments",
  "pricing", "reports", "search", "settings-app", "status-page", "support-desk", "team-admin", "tracking",
  "vendor-hub", "web-embed", "widgets", "wiki", "workflows",
]

private func consumers(_ names: [String], using library: String = "@acme/ui") -> [DiscoveredConsumer] {
  names.map { name in
    DiscoveredConsumer(
      root: "/Users/me/code/\(name)", name: name, libraries: [.init(name: library, range: "^1.3.0")],
      packageManager: name.hasPrefix("p") ? .pnpm : .npm)
  }
}

@MainActor @Suite(.serialized) struct WidgetTests {
  @Test func searchMatchesNameAndFolderIgnoringCaseAndOrder() {
    let apps = consumers(manyNames)
    #expect(filterLinkCandidates(apps, matching: "").map { projectName($0.root) } == manyNames.sorted())
    #expect(filterLinkCandidates(apps, matching: "BILL").map { projectName($0.root) } == ["billing"])
    // A word of the folder matches too, and every word has to.
    #expect(filterLinkCandidates(apps, matching: "code portal").map { projectName($0.root) } == ["customer-portal", "partner-portal"])
    #expect(filterLinkCandidates(apps, matching: "portal customer").map { projectName($0.root) } == ["customer-portal"])
    #expect(filterLinkCandidates(apps, matching: "no such app").isEmpty)
  }

  @Test(.enabled(if: Snapshots.comparable, Comment(rawValue: Snapshots.skipped))) func healthy() {
    let calm = model { model in
      model.connection = .online
      model.status = Status(
        daemon: health, libraries: [ui, forms],
        links: [
          Link(library: "@acme/ui", consumer: shop, status: .installed, installedVersion: version),
          Link(library: "@acme/ui", consumer: admin, status: .installed, installedVersion: version),
        ],
        groups: [Group(name: "checkout", consumers: [shop, admin])])
      model.consumers = consumers(["storybook"]) + consumers(["storybook"], using: "@acme/forms")
    }
    assertSnapshot(of: MenuContent(model: calm, actions: MenuActions()), named: "widget-healthy")
  }

  /// Thirty apps use the library: at most three linked ones are listed (the failed one first), and the
  /// rest of the apps are behind one button with a count, not thirty chips.
  @Test(.enabled(if: Snapshots.comparable, Comment(rawValue: Snapshots.skipped))) func manyApps() {
    let names = ["admin", "shop", "reports", "orders", "landing", "invoices"]
    let busy = model { model in
      model.connection = .online
      model.status = Status(
        daemon: health, libraries: [ui, forms],
        links: names.enumerated().map { index, name in
          Link(
            library: "@acme/ui", consumer: "/Users/me/code/\(name)", status: name == "invoices" ? .failed : .installed,
            installedVersion: index == 4 ? nil : version)
        },
        groups: [])
      model.consumers = consumers(manyNames, using: "@acme/ui") + consumers(manyNames, using: "@acme/forms")
      model.failures = [
        Failure(
          title: "Install of @acme/ui into invoices failed", detail: "npm ERR! code ERESOLVE", date: at,
          consumer: "/Users/me/code/invoices")
      ]
    }
    assertSnapshot(of: MenuContent(model: busy, actions: MenuActions()), named: "widget-many")
  }

  @Test(.enabled(if: Snapshots.comparable, Comment(rawValue: Snapshots.skipped))) func linkPicker() {
    let picker = LinkPicker(library: "@acme/ui", candidates: consumers(manyNames), model: model { $0.connection = .online }) {}
      .frame(width: 348)
      .background(DS.groupFill, in: .rect(cornerRadius: 14))
      .padding(12)
    assertSnapshot(of: picker, named: "widget-link-picker", size: CGSize(width: 372, height: 380))
  }

  @Test(.enabled(if: Snapshots.comparable, Comment(rawValue: Snapshots.skipped))) func buildFailureAndWarnings() {
    let broken = model { model in
      model.connection = .online
      model.status = Status(daemon: health, libraries: [ui], links: [], groups: [])
      model.failures = [
        Failure(title: "Build of @acme/ui failed", detail: "✘ [ERROR] TS2304: Cannot find name 'Butto'", date: at, consumer: nil),
        Failure(title: "Auto-sync of @acme/forms stopped", detail: "watch stopped", date: at, consumer: nil),
      ]
      model.driftedRestore = RestoreRequest(consumer: shop, library: "@acme/ui")
      model.actionError = "storybook doesn't depend on @acme/ui any more."
    }
    assertSnapshot(of: MenuContent(model: broken, actions: MenuActions()), named: "widget-failures")
  }
}
