import AppKit
import DryfitAPI
import DryfitMenu
import ServiceManagement
import SwiftUI

@main
struct DryfitApp: App {
  @NSApplicationDelegateAdaptor private var delegate: AppDelegate

  var body: some Scene {
    MenuBarExtra {
      MenuContent(model: delegate.model, navigation: delegate.navigation, actions: delegate.actions)
    } label: {
      MenuBarLabel(icon: delegate.model.icon, menu: delegate.statusMenu, navigation: delegate.navigation)
    }
    .menuBarExtraStyle(.window)

    Window("dryfit", id: mainWindowID) {
      MainWindow(model: delegate.model, navigation: delegate.navigation, actions: delegate.actions)
        .onAppear { UserDefaults.standard.set(true, forKey: Self.welcomedKey) }
    }
    // No title bar: the window's own buttons float over the sidebar, as in the mockup.
    .windowStyle(.hiddenTitleBar)
    .defaultSize(width: 1000, height: 690)
    // Opens by itself only the first time, so a new user sees where to start.
    .defaultLaunchBehavior(UserDefaults.standard.bool(forKey: Self.welcomedKey) ? .suppressed : .presented)
    .restorationBehavior(.disabled)
    .commands {
      if let checkForUpdates = delegate.updates.checkForUpdates {
        CommandGroup(after: .appInfo) {
          Button("Check for Updates…", action: checkForUpdates)
        }
      }
      SettingsCommands(navigation: delegate.navigation)
      CommandGroup(replacing: .newItem) {
        Button("Add Library…") {
          Task { await delegate.model.chooseLibraryFolder(navigation: delegate.navigation) }
        }
        .keyboardShortcut("o")
        Button("Add App…") {
          Task { await delegate.model.chooseApp(navigation: delegate.navigation) }
        }
        .keyboardShortcut("o", modifiers: [.command, .shift])
        Button("New Group…") { delegate.navigation.groupEditor = .new }
          .keyboardShortcut("n", modifiers: [.command, .shift])
      }
    }
  }

  private static let welcomedKey = "welcomed"
}

/// Owns the model for the app's lifetime and follows the daemon from launch, not from the first time
/// the menu opens, so failures are noticed (and notified) while the menu is closed.
final class AppDelegate: NSObject, NSApplicationDelegate {
  let model: MenuModel
  let navigation = AppNavigation()
  let updates = Updates()
  private let home = DryfitHome.locate()
  private var failureWindow: FailureWindow?
  /// What a right-click on the menu bar icon shows.
  private(set) lazy var statusMenu = StatusMenu(model: model, actions: actions)
  private var connection: Task<Void, Never>?

  override init() {
    let home = home
    let launcher = DaemonLauncher()
    // The notifier opens the failure window, which needs the model: tied together after init.
    let relay = NotifierRelay()
    model = MenuModel(
      connect: {
        switch await DaemonLocator(home: home).locate() {
        case .running(let client, let health): .running(client, health)
        case .notRunning: .notRunning
        case .incompatible(let health): .incompatible(health)
        }
      },
      launch: { try await launcher.start() },
      install: { try await launcher.installCLI() },
      appVersion: Bundle.main.bundleURL.pathExtension == "app"
        ? Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String : nil,
      // A checkout's CLI ($DRYFIT_CLI) is not npm's to update.
      update: ProcessInfo.processInfo.environment["DRYFIT_CLI", default: ""].isEmpty
        ? { try await launcher.updateCLI() } : nil,
      // launchd needs a built app's stable path; under `swift run` there is nothing to start at login.
      startAtLogin: Bundle.main.bundleURL.pathExtension == "app"
        ? StartAtLogin(isOn: { launcher.startsAtLogin }, set: { try await launcher.setStartAtLogin($0) }) : nil,
      notifier: relay,
      orderStore: .userDefaults())
    super.init()
    failureWindow = FailureWindow(model: model) { [weak self] library in
      guard let self else { return }
      self.navigation.selection = .library(library)
      self.statusMenu.openWindow?()
      NSApp.activate()
    }
    relay.target = UserNotifier { [weak self] id in self?.failureWindow?.show(selecting: id) } ?? SilentNotifier()
  }

  func applicationDidFinishLaunching(_ notification: Notification) {
    connection = Task { [model] in await model.run() }
    statusMenu.install()
  }

  var actions: MenuActions {
    MenuActions(
      openLog: { [home] in NSWorkspace.shared.open(home.log) },
      showFailures: { [weak self] id in self?.failureWindow?.show(selecting: id) },
      quit: { NSApp.terminate(nil) },
      openAtLogin: Bundle.main.bundleURL.pathExtension == "app" ? Self.openAtLogin : nil,
      checkForUpdates: updates.checkForUpdates,
      installUpdatesAutomatically: updates.installAutomatically)
  }

  /// Registers the app itself as a login item, only when the user turns it on.
  private static var openAtLogin: Binding<Bool> {
    Binding(
      get: { SMAppService.mainApp.status == .enabled },
      set: { enabled in
        try? enabled ? SMAppService.mainApp.register() : SMAppService.mainApp.unregister()
      })
  }
}

private final class NotifierRelay: Notifier {
  var target: (any Notifier)?
  func post(_ failure: Failure, quietly: Bool) { target?.post(failure, quietly: quietly) }
  func recovered(_ failure: Failure, message: String) { target?.recovered(failure, message: message) }
}
