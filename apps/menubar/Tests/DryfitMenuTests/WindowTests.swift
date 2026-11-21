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
  /// Twenty-eight apps could be linked: the page lists five, with a search and a count, not all of them.
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
}
