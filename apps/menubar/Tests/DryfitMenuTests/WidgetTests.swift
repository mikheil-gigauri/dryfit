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

  /// Thirty apps use the library: at most three linked ones are listed (the failed one first), and the
  /// rest of the apps are behind one button with a count, not thirty chips.
}
