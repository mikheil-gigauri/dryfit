import AppKit
import DryfitAPI
import Foundation
import SwiftUI
import Testing

@testable import DryfitMenu

/// Draws views in real windows on the screen and photographs them with `screencapture`, so what lands
/// in the PNG is what the Mac draws, controls and window chrome included (an offscreen render is not).
/// Off unless `DRYFIT_LIVE` names the folder to write to; `DRYFIT_SCENES` picks scenes by name.
///
///     DRYFIT_LIVE=/tmp/live DRYFIT_SCENES=prims swift test --filter LiveCapture
@MainActor @Suite(.serialized) struct LiveCapture {
  nonisolated static let folder = ProcessInfo.processInfo.environment["DRYFIT_LIVE"]
  nonisolated static let only = ProcessInfo.processInfo.environment["DRYFIT_SCENES"]?.split(separator: ",").map(String.init)

  @Test(.enabled(if: ProcessInfo.processInfo.environment["DRYFIT_LIVE"] != nil)) func scenes() async throws {
    _ = NSApplication.shared
    NSApp.setActivationPolicy(.accessory)
    for scene in LiveScenes.all where Self.only == nil || Self.only!.contains(scene.name) {
      for dark in [false, true] {
        try await capture(scene, dark: dark)
      }
    }
  }

  private func capture(_ scene: LiveScene, dark: Bool) async throws {
    let appearance = NSAppearance(named: dark ? .darkAqua : .aqua)!
    let host = NSHostingController(rootView: scene.view().environment(\.timeZone, TimeZone(identifier: "UTC")!))
    let window = NSWindow(
      contentRect: NSRect(origin: NSPoint(x: 80, y: 120), size: scene.size),
      styleMask: scene.chrome ? [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView] : [.borderless],
      backing: .buffered, defer: false)
    window.appearance = appearance
    if scene.chrome {
      window.titlebarAppearsTransparent = true
      window.titleVisibility = .hidden
    }
    window.isReleasedWhenClosed = false
    window.contentViewController = host
    window.setContentSize(scene.size)
    if scene.fit {
      host.view.layoutSubtreeIfNeeded()
      window.setContentSize(CGSize(width: scene.size.width, height: host.view.fittingSize.height))
    }
    window.backgroundColor = .clear
    window.orderFrontRegardless()
    try await Task.sleep(for: .milliseconds(700))
    let path = "\(Self.folder!)/\(scene.name)-\(dark ? "d" : "l").png"
    let shot = Process()
    shot.executableURL = URL(filePath: "/usr/sbin/screencapture")
    shot.arguments = ["-x", "-o", "-l", "\(window.windowNumber)", path]
    try shot.run()
    shot.waitUntilExit()
    window.orderOut(nil)
    Self.retained.append(window)
  }

  private static var retained: [NSWindow] = []
}

struct LiveScene {
  let name: String
  let size: CGSize
  var chrome = false
  /// The window takes the height of what it shows.
  var fit = false
  let view: @MainActor () -> AnyView
}

@MainActor enum LiveScenes {
  static var all: [LiveScene] { [prims] + widgets }

  static let prims = LiveScene(name: "prims", size: CGSize(width: 520, height: 300)) {
    AnyView(
      VStack(alignment: .leading, spacing: 14) {
        HStack(spacing: 8) {
          Button("Open dryfit") {}.buttonStyle(.flat)
          Button("Sync now") {}.buttonStyle(.flat(.primary))
          Button("Restore") {}.buttonStyle(.flat(small: true))
          Button("+ storybook") {}.buttonStyle(.flat(.accent, small: true))
          Button("Delete…") {}.buttonStyle(.flat(.bad))
          Button("Disabled") {}.buttonStyle(.flat).disabled(true)
        }
        HStack(spacing: 8) {
          Tag(text: "DEV", kind: .dev)
          Tag(text: "Release ^1.3.0", kind: .release)
          Tag(text: "Install failed", kind: .bad)
          Tag(text: "Versions differ", kind: .warn)
          Tag(text: "Not linked")
          Tag(text: "Installed", kind: .ok)
          DrySwitch(isOn: .constant(true), label: "on")
          DrySwitch(isOn: .constant(false), label: "off")
          Spin()
          Dot(color: Theme.ok)
          MoreMenu { Button("Show in Finder") {} }
        }
        HStack(spacing: 12) {
          StatusGlyph(kind: .ok)
          StatusGlyph(kind: .failed)
          StatusGlyph(kind: .update)
          StatusGlyph(kind: .waiting)
          StatusGlyph(kind: .warning, size: 34)
          Icon(kind: .library)
          Icon(kind: .app)
          Icon(kind: .group)
          Icon(kind: .search, size: 13)
          Icon(kind: .gear)
          Icon(kind: .folder)
          Icon(kind: .library, size: 24)
        }
        Well { Icon(kind: .search, size: 13); Text("Filter").foregroundStyle(Theme.muted) }.frame(width: 200)
      }
      .padding(20)
      .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
      .foregroundStyle(Theme.text)
      .background(Theme.window))
  }
}

// MARK: The menu bar widget, one scene per state of the mockup

extension LiveScenes {
  private static func consumers(_ names: [String], using library: String = "@acme/ui") -> [DiscoveredConsumer] {
    names.map { DiscoveredConsumer(root: "/Users/me/code/\($0)", name: $0, libraries: [.init(name: library, range: "^1.3.0")], packageManager: .npm) }
  }

  private static let manyNames = [
    "billing", "checkout-web", "customer-portal", "dashboard", "docs-site", "email-templates", "help-center", "invoices", "landing",
    "marketing-site", "mobile-web", "onboarding", "orders", "partner-portal", "payments", "pricing", "reports", "search",
    "settings-app", "status-page", "support-desk", "team-admin", "tracking", "vendor-hub", "web-embed", "widgets", "wiki", "workflows",
  ]

  /// The healthy state of the mockup: ui linked into admin and shop, forms not linked, a group.
  @MainActor private static func online(_ tweak: (MenuModel) -> Void = { _ in }) -> MenuModel {
    model { m in
      m.connection = .online
      m.status = Status(
        daemon: health, libraries: [ui, forms],
        links: [
          Link(library: "@acme/ui", consumer: admin, status: .installed, installedVersion: version),
          Link(library: "@acme/ui", consumer: shop, status: .installed, installedVersion: version),
        ],
        groups: [Group(name: "checkout", consumers: [shop, admin])])
      m.consumers = consumers(["storybook"]) + consumers(["storybook"], using: "@acme/forms")
      tweak(m)
    }
  }

  /// A model whose app is at 1.3.0, so a dryfit at 1.2.0 is the older one.
  @MainActor private static func versioned(_ configure: (MenuModel) -> Void) -> MenuModel {
    let m = MenuModel(connect: { .notRunning }, launch: {}, appVersion: "1.3.0", update: {}, notifier: RecordingNotifier())
    configure(m)
    return m
  }

  @MainActor private static func widget(_ name: String, _ m: MenuModel, chrome: Bool = false) -> LiveScene {
    LiveScene(name: name, size: CGSize(width: 372, height: 700), fit: true) {
      AnyView(
        MenuContent(model: m, actions: MenuActions(checkForUpdates: {}))
          .background(Theme.color(0xf5f6fa, 0x242429))
          .clipShape(.rect(cornerRadius: 20)))
    }
  }

  @MainActor static var widgets: [LiveScene] {
    let failed = Failure(title: "Install of @acme/ui into admin failed", detail: "npm ERR! code ERESOLVE\nnpm ERR! Could not resolve dependency", date: at, consumer: admin)
    let build = Failure(title: "Build of @acme/ui failed", detail: "✘ [ERROR] TS2304: Cannot find name 'Butto'", date: at, consumer: nil)
    let manyLinks = ["admin", "shop", "billing", "orders", "reports", "invoices"].map { n in
      Link(library: "@acme/ui", consumer: "/Users/me/code/\(n)", status: n == "admin" ? .failed : .installed, installedVersion: n == "admin" ? nil : version)
    }
    return [
      widget("m-ok", online()),
      widget("m-work", online { $0.activity = "Installing @acme/ui into shop…" }),
      widget("m-fail", online {
        $0.status = Status(
          daemon: health, libraries: [ui, forms],
          links: [Link(library: "@acme/ui", consumer: admin, status: .failed), Link(library: "@acme/ui", consumer: shop, status: .installed, installedVersion: version)],
          groups: [Group(name: "checkout", consumers: [shop, admin])])
        $0.failures = [failed]
        $0.restartNeeded = [shop]
      }),
      widget("m-fail2", online { $0.failures = [build, build, build] }),
      widget("m-many", online {
        $0.status = Status(daemon: health, libraries: [ui, forms], links: manyLinks, groups: [Group(name: "checkout", consumers: [shop, admin])])
        $0.consumers = consumers(manyNames) + consumers(manyNames, using: "@acme/forms")
        $0.failures = [Failure(title: "Install of @acme/ui into admin failed", detail: "npm ERR!", date: at, consumer: "/Users/me/code/admin")]
      }),
      widget("m-empty", model { $0.connection = .online; $0.status = Status(daemon: health) }),
      widget("m-old", versioned { $0.connection = .online; $0.consumers = consumers(["storybook"]) + consumers(["storybook"], using: "@acme/forms"); $0.status = Status(daemon: Health(name: "dryfit", version: "1.2.0", apiVersion: 1, pid: 42, registryUrl: "http://127.0.0.1:4874/", startedAt: "2026-11-18T09:00:00.000Z"), libraries: [ui, forms], links: [Link(library: "@acme/ui", consumer: admin, status: .installed, installedVersion: version), Link(library: "@acme/ui", consumer: shop, status: .installed, installedVersion: version)], groups: [Group(name: "checkout", consumers: [shop, admin])]) }),
      widget("m-drift", online { $0.driftedRestore = RestoreRequest(consumer: shop, library: "@acme/ui") }),
      widget("m-err", online { $0.actionError = "storybook doesn't depend on @acme/ui any more. Its package.json no longer lists it." }),
      widget("m-diff", online {
        $0.status = Status(
          daemon: health, libraries: [ui, forms],
          links: [Link(library: "@acme/ui", consumer: admin, status: .installed, installedVersion: version), Link(library: "@acme/ui", consumer: shop, status: .installed, installedVersion: version)],
          groups: [Group(name: "checkout", consumers: [shop, admin])],
          warnings: [CoherenceWarning(group: "checkout", library: "@acme/ui", versions: [.init(consumer: shop, version: version), .init(consumer: admin, version: "1.3.0")])])
      }),
      widget("m-off", model { $0.connection = .offline }),
      widget("m-nocli", model { $0.connection = .offline; $0.cliMissing = true }),
      widget("m-inst", model { $0.connection = .offline; $0.cliMissing = true; $0.inFlight = [.installCLI] }),
      widget("m-serr", model { $0.connection = .offline; $0.startError = "Port 4873 is already in use by another process." }),
      widget("m-conn", model { $0.connection = .connecting }),
      widget("m-inc", versioned { $0.connection = .incompatible(daemonVersion: "1.2.0") }),
    ]
  }
}
