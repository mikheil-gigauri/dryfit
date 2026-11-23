import AppKit
import DryfitAPI
import Foundation
import SwiftUI
import Testing

@testable import DryfitMenu

/// The stills the promo video (apps/promo) is cut from: the library page as apps get linked, synced and
/// restored, and the menu bar widget. Drawn in real dark windows on a Retina screen when there is one,
/// so they come out at 2x. Off unless `DRYFIT_PROMO` names the folder to write to.
///
///     DRYFIT_PROMO=../promo/public/ui xcrun swift test --filter PromoCapture
@MainActor @Suite(.serialized) struct PromoCapture {
  nonisolated static let folder = ProcessInfo.processInfo.environment["DRYFIT_PROMO"]

  @Test(.enabled(if: ProcessInfo.processInfo.environment["DRYFIT_PROMO"] != nil)) func stills() async throws {
    _ = NSApplication.shared
    NSApp.setActivationPolicy(.accessory)
    for (name, size, fit, view) in Self.scenes {
      try await capture(name, size: size, fit: fit, view: view)
    }
  }

  private static let ui = "@acme/ui"
  private static let older = "1.4.1-dev.20261118143012"
  private static let actions = MenuActions(
    openAtLogin: .constant(false), checkForUpdates: {}, installUpdatesAutomatically: .constant(true))

  private static func app(_ root: String, _ name: String) -> DiscoveredConsumer {
    DiscoveredConsumer(root: root, name: name, libraries: [.init(name: ui, range: "^1.3.0")], packageManager: .npm)
  }

  /// `installed` overrides the version an app is on, for the moment a sync has reached some apps only.
  private static func state(
    linked: [String], version: String = version, installed: [String: String] = [:], watching: Bool = false,
    _ tweak: (MenuModel) -> Void = { _ in }
  ) -> MenuModel {
    model { m in
      m.connection = .online
      m.status = Status(
        daemon: health,
        libraries: [
          Library(name: ui, root: DryfitMenuTests.ui.root, publishDir: DryfitMenuTests.ui.publishDir, lastPublishedVersion: version, watch: watching),
          forms,
        ],
        links: linked.map {
          Link(library: ui, consumer: $0, status: .installed, installedVersion: installed[$0] ?? version, guarded: true)
        },
        groups: [Group(name: "checkout", consumers: [shop, admin])])
      m.consumers = [app(admin, "admin"), app(shop, "shop"), app("/Users/me/repos/storybook", "storybook")]
      tweak(m)
    }
  }

  private static func window(_ m: MenuModel) -> AnyView {
    let navigation = AppNavigation()
    navigation.selection = .library(ui)
    return AnyView(MainWindow(model: m, navigation: navigation, actions: actions))
  }

  private static var scenes: [(String, CGSize, Bool, () -> AnyView)] {
    let page = CGSize(width: 1000, height: 690)
    return [
      // Link admin, then shop, on the older build.
      ("link-0", page, false, { window(state(linked: [], version: older)) }),
      ("link-0b", page, false, { window(state(linked: [], version: older) { $0.inFlight = [.link(ui, admin)] }) }),
      ("link-1", page, false, { window(state(linked: [admin], version: older)) }),
      ("link-1b", page, false, { window(state(linked: [admin], version: older) { $0.inFlight = [.link(ui, shop)] }) }),
      ("link-2", page, false, { window(state(linked: [admin, shop], version: older)) }),
      // A save: build, publish, then install into each app in turn.
      ("watch-a", page, false, {
        window(state(linked: [admin, shop], version: older, watching: true) {
          $0.inFlight = [.sync(ui)]
          $0.activity = "Building @acme/ui…"
        })
      }),
      ("watch-b", page, false, {
        window(state(linked: [admin, shop], installed: [admin: older, shop: older], watching: true) {
          $0.inFlight = [.sync(ui)]
          $0.activity = "Installing @acme/ui into admin…"
        })
      }),
      ("watch-c", page, false, {
        window(state(linked: [admin, shop], installed: [shop: older], watching: true) {
          $0.inFlight = [.sync(ui)]
          $0.activity = "Installing @acme/ui into shop…"
        })
      }),
      ("watch-d", page, false, { window(state(linked: [admin, shop], watching: true)) }),
      // Restore shop, then admin.
      ("restore-1", page, false, { window(state(linked: [admin, shop], watching: true) { $0.inFlight = [.restore(shop, ui)] }) }),
      ("restore-2", page, false, { window(state(linked: [admin], watching: true)) }),
      ("restore-2b", page, false, { window(state(linked: [admin], watching: true) { $0.inFlight = [.restore(admin, ui)] }) }),
      ("restore-3", page, false, { window(state(linked: [], watching: true)) }),
      ("menu", CGSize(width: 372, height: 700), true, {
        AnyView(
          MenuContent(model: state(linked: [admin, shop], watching: true), actions: MenuActions(checkForUpdates: {}))
            .background(Theme.color(0xf5f6fa, 0x242429))
            .clipShape(.rect(cornerRadius: 20)))
      }),
    ]
  }

  private func capture(_ name: String, size: CGSize, fit: Bool, view: () -> AnyView) async throws {
    let host = NSHostingController(rootView: view().environment(\.timeZone, TimeZone(identifier: "UTC")!))
    let chrome = !fit
    let screen = NSScreen.screens.first { $0.backingScaleFactor >= 2 } ?? NSScreen.main!
    let origin = NSPoint(x: screen.frame.minX + 40, y: screen.frame.maxY - size.height - 80)
    let window = NSWindow(
      contentRect: NSRect(origin: origin, size: size),
      styleMask: chrome ? [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView] : [.borderless],
      backing: .buffered, defer: false, screen: screen)
    window.appearance = NSAppearance(named: .darkAqua)
    if chrome {
      window.titlebarAppearsTransparent = true
      window.titleVisibility = .hidden
    }
    window.isReleasedWhenClosed = false
    window.contentViewController = host
    window.setContentSize(size)
    if fit {
      host.view.layoutSubtreeIfNeeded()
      window.setContentSize(CGSize(width: size.width, height: host.view.fittingSize.height))
    }
    window.setFrameOrigin(origin)
    window.backgroundColor = .clear
    window.orderFrontRegardless()
    try await Task.sleep(for: .milliseconds(800))
    let shot = Process()
    shot.executableURL = URL(filePath: "/usr/sbin/screencapture")
    shot.arguments = ["-x", "-o", "-l", "\(window.windowNumber)", "\(Self.folder!)/\(name).png"]
    try shot.run()
    shot.waitUntilExit()
    window.orderOut(nil)
    Self.retained.append(window)
  }

  private static var retained: [NSWindow] = []
}
