import AppKit
import DryfitAPI
import SwiftUI

/// The menu a right-click (or Control-click) on dryfit's menu bar icon shows: settings, the log,
/// login, updates, stopping and quitting. A left click still opens the menu bar window.
///
/// `MenuBarExtra` offers no right-click of its own, so this watches the app's own events for a
/// secondary click on the status bar window and shows the menu there instead of the window.
public final class StatusMenu: NSObject {
  let model: MenuModel
  let actions: MenuActions
  /// Set by the menu bar icon, which is always on screen, so the menu can open SwiftUI's windows.
  public var openWindow: (() -> Void)?
  var navigation: AppNavigation?
  private var monitor: Any?

  public init(model: MenuModel, actions: MenuActions) {
    self.model = model
    self.actions = actions
  }

  /// Starts showing the menu on a secondary click on the menu bar icon.
  public func install() {
    guard monitor == nil else { return }
    monitor = NSEvent.addLocalMonitorForEvents(matching: [.rightMouseDown, .leftMouseDown]) { [weak self] event in
      guard let self, Self.isSecondaryClick(event), let window = event.window,
        Self.isStatusBarWindow(window), let button = window.contentView
      else { return event }
      self.show(below: button)
      return nil
    }
  }

  static func isSecondaryClick(_ event: NSEvent) -> Bool {
    event.type == .rightMouseDown || (event.type == .leftMouseDown && event.modifierFlags.contains(.control))
  }

  /// The window AppKit puts a status item's button in. Its class is private, so it goes by name.
  private static func isStatusBarWindow(_ window: NSWindow) -> Bool {
    window.className.contains("StatusBarWindow")
  }

  private func show(below view: NSView) {
    let menu = makeMenu()
    let y = view.isFlipped ? view.bounds.maxY + 5 : view.bounds.minY - 5
    menu.popUp(positioning: nil, at: NSPoint(x: view.bounds.minX, y: y), in: view)
  }

  /// Built each time it opens, so it reflects what is true now.
  func makeMenu() -> NSMenu {
    let menu = NSMenu()
    menu.autoenablesItems = false
    menu.addItem(item("Open dryfit", action: #selector(openMainWindow)))
    menu.addItem(item("Settings…", action: #selector(showSettings), key: ","))
    menu.addItem(.separator())
    menu.addItem(item("Open Log", action: #selector(openLog)))
    if !model.failures.isEmpty {
      menu.addItem(item("Show Failures…", action: #selector(showFailures)))
    }
    if let openAtLogin = actions.openAtLogin {
      let login = item("Open at Login", action: #selector(toggleOpenAtLogin))
      login.state = openAtLogin.wrappedValue ? .on : .off
      menu.addItem(login)
    }
    if actions.checkForUpdates != nil {
      menu.addItem(item("Check for Updates…", action: #selector(checkForUpdates)))
    }
    // Whichever of the two applies, so the menu can always bring dryfit back.
    if model.connection == .online {
      menu.addItem(.separator())
      menu.addItem(item("Stop dryfit", action: #selector(stopDaemon)))
    } else if model.connection == .offline, !model.cliMissing {
      menu.addItem(.separator())
      menu.addItem(item("Start dryfit", action: #selector(startDaemon)))
    }
    menu.addItem(.separator())
    menu.addItem(item("Quit dryfit", action: #selector(quit), key: "q"))
    return menu
  }

  private func item(_ title: String, action: Selector, key: String = "") -> NSMenuItem {
    let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
    item.target = self
    return item
  }

  @objc private func openMainWindow() {
    openWindow?()
    NSApp.activate()
  }

  @objc private func showSettings() {
    guard let openWindow else { return }
    navigation?.showSettings(openWindow)
  }

  @objc private func openLog() { actions.openLog() }
  @objc private func showFailures() { actions.showFailures(nil) }
  @objc private func toggleOpenAtLogin() { actions.openAtLogin?.wrappedValue.toggle() }
  @objc private func checkForUpdates() { actions.checkForUpdates?() }
  @objc private func stopDaemon() { Task { await model.stopDaemon() } }
  @objc private func startDaemon() { Task { await model.startDaemon() } }
  @objc private func quit() { actions.quit() }
}

/// The menu bar icon. It also hands the status menu SwiftUI's window actions, which only views get.
public struct MenuBarLabel: View {
  let icon: MenuModel.Icon
  let menu: StatusMenu
  let navigation: AppNavigation
  @Environment(\.openWindow) private var openWindow

  public init(icon: MenuModel.Icon, menu: StatusMenu, navigation: AppNavigation) {
    self.icon = icon
    self.menu = menu
    self.navigation = navigation
  }

  public var body: some View {
    Image(nsImage: MenuBarIcon.image(for: icon))
      .onAppear {
        menu.openWindow = { openWindow(id: mainWindowID) }
        menu.navigation = navigation
      }
  }
}

/// Settings… (⌘,) in the app menu, opening the dryfit window at Settings.
public struct SettingsCommands: Commands {
  let navigation: AppNavigation
  @Environment(\.openWindow) private var openWindow

  public init(navigation: AppNavigation) {
    self.navigation = navigation
  }

  public var body: some Commands {
    CommandGroup(replacing: .appSettings) {
      Button("Settings…") { navigation.showSettings { openWindow(id: mainWindowID) } }
        .keyboardShortcut(",")
    }
  }
}
