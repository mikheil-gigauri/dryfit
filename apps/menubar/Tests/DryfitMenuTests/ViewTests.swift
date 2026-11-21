import AppKit
import DryfitAPI
import Foundation
import SwiftUI
import Testing

@testable import DryfitMenu

/// A model in a given state, without a daemon behind it.
@MainActor func model(_ configure: (MenuModel) -> Void) -> MenuModel {
  let model = MenuModel(connect: { .notRunning }, launch: {}, notifier: RecordingNotifier())
  configure(model)
  return model
}

let at = Date(timeIntervalSince1970: 1_795_000_000)

@MainActor @Suite(.serialized) struct ViewTests {
  @Test func everyIconStateLooksDifferentAndIsATemplate() {
    let icons = [MenuModel.Icon.offline, .idle, .working, .attention]
    let images = icons.map(MenuBarIcon.image(for:))
    let allTemplates = images.allSatisfy { $0.isTemplate }
    #expect(allTemplates)
    let distinct = Set(images.compactMap(\.tiffRepresentation))
    #expect(distinct.count == icons.count)
  }

  @Test(.enabled(if: Snapshots.comparable, Comment(rawValue: Snapshots.skipped))) func menuBarIcons() {
    let row = HStack(spacing: 18) {
      ForEach([MenuModel.Icon.idle, .working, .attention, .offline], id: \.self) { icon in
        Image(nsImage: MenuBarIcon.image(for: icon)).resizable().frame(width: 60, height: 54)
      }
    }
    .padding(16)
    assertSnapshot(of: row, named: "menu-bar-icons")
  }

  @Test func describesDevVersionsInLocalTime() {
    let utc = TimeZone(identifier: "UTC")!
    #expect(DevVersion.describe("1.4.1-dev.20261118143201", timeZone: utc) == "1.4.1 · dev 14:32")
    #expect(DevVersion.describe("2.0.0-rc.1.dev.20261118090500", timeZone: utc) == "2.0.0-rc.1 · dev 09:05")
    #expect(DevVersion.describe("1.4.0") == "1.4.0")
  }

  @Test func saysWhereAnAppGetsALibraryFrom() {
    #expect(describeDependency("^1.3.0") == "^1.3.0 from the registry")
    #expect(describeDependency("file:../../releases/acme-ui-1.0.0.tgz") == "Local file acme-ui-1.0.0.tgz")
    #expect(describeDependency("link:../ui") == "Linked folder ui")
    #expect(describeDependency("workspace:*") == "From the workspace")
    #expect(describeDependency("github:acme/ui#main") == "From git")
    #expect(describeDependency("git+ssh://git@github.com/acme/ui.git") == "From git")
    #expect(describeDependency("https://example.com/ui.tgz") == "From a URL")
    #expect(describeDependency("npm:@acme/ui@^1.0.0") == "@acme/ui@^1.0.0 from the registry")
    #expect(describeDependency("../ui") == "Local folder ui")
  }

  @Test func comparesReleaseVersions() {
    #expect(ReleaseVersion.isOlder("0.1.0", than: "0.3.0"))
    #expect(ReleaseVersion.isOlder("0.9.0", than: "0.10.0"))
    #expect(ReleaseVersion.isOlder("1.2.3", than: "2.0.0"))
    #expect(!ReleaseVersion.isOlder("0.3.0", than: "0.3.0"))
    #expect(!ReleaseVersion.isOlder("0.10.0", than: "0.9.0"))
    // A dev build counts as the release it is based on.
    #expect(!ReleaseVersion.isOlder("0.3.0-dev.20261120101500", than: "0.3.0"))
    #expect(!ReleaseVersion.isOlder("0.3.0", than: "0.3.0+build.7"))
    // Anything that is not a release version never asks for an update.
    #expect(!ReleaseVersion.isOlder("main", than: "0.3.0"))
    #expect(!ReleaseVersion.isOlder("0.3", than: "0.4.0"))
    #expect(!ReleaseVersion.isOlder("0.3.0", than: ""))
  }

  @Test func notificationsCarryTheFirstLinesOfOutput() {
    let output = "\n> ng build ui\n\nTS2304: Cannot find name 'Butto'.\n  at button.ts:4\n  at more\n"
    #expect(UserNotifier.summary(of: output) == "> ng build ui\nTS2304: Cannot find name 'Butto'.\nat button.ts:4")
  }

  @Test(.enabled(if: Snapshots.comparable, Comment(rawValue: Snapshots.skipped))) func online() {
    let failed = "npm ERR! code ERESOLVE\nnpm ERR! ERESOLVE unable to resolve dependency tree"
    let busy = model { model in
      model.connection = .online
      model.status = Status(
        daemon: health,
        libraries: [ui, forms],
        links: [
          Link(library: "@acme/ui", consumer: shop, status: .installed, installedVersion: version, guarded: true),
          Link(library: "@acme/ui", consumer: admin, status: .failed),
        ],
        groups: [Group(name: "checkout", consumers: [shop, admin])],
        warnings: [
          CoherenceWarning(
            group: "checkout", library: "@acme/ui",
            versions: [.init(consumer: shop, version: version), .init(consumer: admin, version: "1.4.0")])
        ],
        jobs: Jobs(running: Job(id: 3, label: "sync @acme/ui", queuedAt: "")))
      model.consumers = [
        DiscoveredConsumer(
          root: "/r/storybook", name: "storybook",
          libraries: [.init(name: "@acme/ui", range: "^1.3.0"), .init(name: "@acme/forms", range: "^2.0.0")],
          packageManager: .npm)
      ]
      model.failures = [
        Failure(title: "Install of @acme/ui into admin failed", detail: failed, date: at, consumer: admin)
      ]
      model.activity = "Installing @acme/ui into admin…"
      model.restartNeeded = [shop]
    }
    assertSnapshot(of: MenuContent(model: busy, actions: MenuActions()), named: "online")
  }

  @Test(.enabled(if: Snapshots.comparable, Comment(rawValue: Snapshots.skipped))) func emptyAndIdle() {
    let empty = model { model in
      model.connection = .online
      model.status = Status(daemon: health)
      model.consumers = [DiscoveredConsumer(root: "/r/blog", name: "blog", libraries: [], packageManager: .npm)]
    }
    assertSnapshot(of: MenuContent(model: empty, actions: MenuActions()), named: "empty")
  }

  @Test(.enabled(if: Snapshots.comparable, Comment(rawValue: Snapshots.skipped))) func offlineAfterAFailedStart() {
    let offline = model { model in
      model.connection = .offline
      model.startError = DaemonLauncher.Failure.cliNotFound.localizedDescription
      model.cliMissing = true
    }
    assertSnapshot(of: MenuContent(model: offline, actions: MenuActions()), named: "offline")
  }

  @Test(.enabled(if: Snapshots.comparable, Comment(rawValue: Snapshots.skipped))) func windowShowsALibrary() {
    let linked = model { model in
      model.connection = .online
      model.roots = ["/Users/me/repos"]
      model.status = Status(
        daemon: health,
        libraries: [ui, forms],
        links: [
          Link(library: "@acme/ui", consumer: shop, status: .installed, installedVersion: version, guarded: true),
          Link(library: "@acme/ui", consumer: admin, status: .failed),
        ],
        groups: [Group(name: "checkout", consumers: [shop, admin])])
      model.failures = [Failure(title: "Install of @acme/ui into admin failed", detail: "npm ERR! code ERESOLVE", date: at, consumer: admin)]
      model.consumers = [
        DiscoveredConsumer(root: shop, name: "shop", libraries: [.init(name: "@acme/ui", range: "^1.4.0")], packageManager: .npm),
        DiscoveredConsumer(root: admin, name: "admin", libraries: [.init(name: "@acme/ui", range: "^1.4.0")], packageManager: .pnpm),
        DiscoveredConsumer(
          root: "/Users/me/repos/storybook", name: "storybook",
          libraries: [.init(name: "@acme/ui", range: "^1.3.0"), .init(name: "@acme/forms", range: "^2.0.0")],
          packageManager: .npm),
      ]
    }
    let navigation = AppNavigation()
    navigation.selection = .library("@acme/ui")
    assertSnapshot(
      of: MainWindow(model: linked, navigation: navigation, actions: MenuActions()), named: "window-library",
      size: CGSize(width: 900, height: 820))
    let app = AppNavigation()
    app.selection = .app("/Users/me/repos/storybook")
    assertSnapshot(
      of: MainWindow(model: linked, navigation: app, actions: MenuActions()), named: "window-app",
      size: CGSize(width: 900, height: 620))
  }

  @Test(.enabled(if: Snapshots.comparable, Comment(rawValue: Snapshots.skipped))) func windowWelcomesANewUser() {
    let fresh = model { model in
      model.connection = .online
      model.roots = []
      model.status = Status(daemon: health)
      model.startsAtLogin = false
    }
    assertSnapshot(
      of: MainWindow(model: fresh, navigation: AppNavigation(), actions: MenuActions()), named: "window-welcome",
      size: CGSize(width: 900, height: 620))
  }

  @Test(.enabled(if: Snapshots.comparable, Comment(rawValue: Snapshots.skipped))) func settings() {
    let online = model { model in
      model.connection = .online
      model.roots = ["/Users/me/repos", "/Users/me/work"]
      model.hiddenApps = ["/Users/me/repos/old-shop"]
      model.status = Status(daemon: health)
      model.startsAtLogin = true
    }
    // A page of the dryfit window, opened from the sidebar's gear or with ⌘,.
    let navigation = AppNavigation()
    navigation.selection = .settings
    assertSnapshot(
      of: MainWindow(model: online, navigation: navigation, actions: MenuActions(openAtLogin: .constant(true))),
      named: "settings", size: CGSize(width: 900, height: 700))
  }

  @Test(.enabled(if: Snapshots.comparable, Comment(rawValue: Snapshots.skipped))) func olderDryfit() {
    let outdated = MenuModel(
      connect: { .notRunning }, launch: {}, appVersion: "0.3.0", update: {}, notifier: RecordingNotifier())
    outdated.connection = .online
    outdated.status = Status(daemon: health, libraries: [ui], links: [
      Link(library: "@acme/ui", consumer: shop, status: .installed, installedVersion: version, guarded: true)
    ])
    assertSnapshot(of: MenuContent(model: outdated, actions: MenuActions()), named: "outdated")
  }

  @Test(.enabled(if: Snapshots.comparable, Comment(rawValue: Snapshots.skipped))) func incompatibleDaemon() {
    let incompatible = model { $0.connection = .incompatible(daemonVersion: "2.0.0") }
    assertSnapshot(of: MenuContent(model: incompatible, actions: MenuActions()), named: "incompatible")
  }

  @Test(.enabled(if: Snapshots.comparable, Comment(rawValue: Snapshots.skipped))) func failureWindow() {
    let output = """
      > ng build ui

      ✘ [ERROR] TS2304: Cannot find name 'Butto'. [plugin angular-compiler]

          projects/ui/src/button/button.ts:4:15:
            4 │   readonly kind: Butto = 'primary';
              ╵                  ~~~~~
      """
    let failures = [
      Failure(title: "Build of @acme/ui failed", detail: output, date: at, library: "@acme/ui"),
      Failure(title: "Auto-sync of @acme/forms stopped", detail: "EMFILE: too many open files", date: at - 600),
    ]
    assertSnapshot(
      of: FailureView(failures: failures, selection: .constant(failures[0].id)), named: "failures",
      size: CGSize(width: 720, height: 360))
  }
}
