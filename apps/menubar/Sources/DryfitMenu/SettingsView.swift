import DryfitAPI
import SwiftUI

/// dryfit's settings, a page of the dryfit window: where to look for apps, the background service,
/// opening at login, and updates.
public struct SettingsView: View {
  let model: MenuModel
  let actions: MenuActions

  public init(model: MenuModel, actions: MenuActions) {
    self.model = model
    self.actions = actions
  }

  public var body: some View {
    PinnedPage {
      Text("Settings").font(DS.title).frame(maxWidth: .infinity, alignment: .leading).frame(minHeight: 44)
    } content: {
      if let error = model.actionError {
        ErrorBanner(message: error) { model.dismissActionError() }
      }

      section("Project folders", footnote: "dryfit looks in these folders for apps that use your libraries.") {
        HairlineGroup {
          if model.connection != .online {
            GroupRow { Text("Start dryfit to change these.").foregroundStyle(DS.muted) }
          } else if let roots = model.roots, !roots.isEmpty {
            ForEach(roots, id: \.self) { root in
              GroupRow {
                Image(systemName: "folder").foregroundStyle(DS.muted).accessibilityHidden(true)
                Text(abbreviatedPath(root)).font(DS.mono).lineLimit(1).truncationMode(.head)
                Spacer(minLength: 8)
                Button {
                  Task {
                    do {
                      try await model.setRoots(roots.filter { $0 != root })
                    } catch {
                      model.actionError = error.localizedDescription
                    }
                  }
                } label: {
                  // The row's own height, but a 24 pt target.
                  Image(systemName: "minus.circle").foregroundStyle(DS.muted).hitTarget(CGSize(width: 16, height: 16))
                }
                .buttonStyle(.plain)
                .disabled(model.isBusy(.roots))
                .help("Stop looking in \(abbreviatedPath(root))")
                .accessibilityLabel("Remove \(abbreviatedPath(root))")
              }
            }
          } else {
            GroupRow { Text("No folders yet. Add the folders that hold your apps.").foregroundStyle(DS.muted) }
          }
          GroupRow {
            Spacer()
            Button("Add folders…") { Task { await model.chooseProjectFolders() } }
              .buttonStyle(.pill(busy: model.isBusy(.roots)))
              .disabled(model.connection != .online)
          }
        }
      }

      if let hidden = model.hiddenApps, !hidden.isEmpty, model.connection == .online {
        section("Hidden apps", count: hidden.count) {
          HairlineGroup {
            ForEach(hidden, id: \.self) { root in
              GroupRow {
                Image(systemName: "eye.slash").foregroundStyle(DS.muted).accessibilityHidden(true)
                TwoLine(title: projectName(root), caption: abbreviatedPath(root)).layoutPriority(1)
                Spacer(minLength: 8)
                Button("Show") { Task { await model.showApp(root) } }
                  .buttonStyle(.pill(busy: model.isBusy(.hide(root))))
                  .help("List \(projectName(root)) again")
              }
              .help(abbreviatedPath(root))
            }
          }
        }
      }

      section("dryfit service") {
        HairlineGroup {
          GroupRow {
            Text("Status")
            Spacer(minLength: 8)
            StatusDot(color: statusColor)
            Text(status).foregroundStyle(DS.muted)
          }
          if let outdated = model.outdatedVersion {
            GroupRow {
              StatusIcon(condition: .update)
              Text("dryfit \(outdated) is older than this app")
              Spacer(minLength: 8)
              UpdateDryfitControl(model: model, prominent: false)
            }
            .background(Color.orange.opacity(0.1))
          }
          if let registry = model.status?.daemon.registryUrl, model.connection == .online {
            GroupRow {
              Text("Registry")
              Spacer(minLength: 8)
              Text(registry).font(DS.mono).foregroundStyle(DS.muted).lineLimit(1).truncationMode(.middle).textSelection(.enabled)
            }
          }
          if let startsAtLogin = model.startsAtLogin {
            GroupRow {
              TwoLine(title: "Start dryfit at login", caption: "So auto-sync is on again after a restart.")
              Spacer(minLength: 8)
              if model.isBusy(.startAtLogin) { ProgressView().controlSize(.mini) }
              Toggle(
                "Start dryfit at login",
                isOn: Binding(get: { startsAtLogin }, set: { on in Task { await model.setStartAtLogin(on) } })
              )
              .toggleStyle(.switch)
              .controlSize(.small)
              .labelsHidden()
              .disabled(model.isBusy(.startAtLogin))
            }
            .help("Start dryfit when you log in, so auto-sync is on again after a restart")
          }
          GroupRow {
            Button("Open log", action: actions.openLog).buttonStyle(.pill)
            Spacer()
            switch model.connection {
            case .online:
              Button("Stop") { Task { await model.stopDaemon() } }.buttonStyle(.pill(busy: model.isBusy(.stop)))
            case .offline:
              Button("Start") { Task { await model.startDaemon() } }.buttonStyle(.primaryPill)
            case .starting:
              Button("Start") {}.buttonStyle(.pill(busy: true))
            default:
              EmptyView()
            }
          }
        }
      }

      if let openAtLogin = actions.openAtLogin {
        section("General") {
          HairlineGroup {
            GroupRow {
              Text("Open this app at login")
              Spacer()
              LiveToggle(title: "Open at login", source: openAtLogin)
            }
          }
        }
      }

      if let checkForUpdates = actions.checkForUpdates {
        section(
          "Updates",
          footnote: "dryfit looks for a new version once a day and, when installing automatically, replaces itself while you're not using it."
        ) {
          HairlineGroup {
            if let installAutomatically = actions.installUpdatesAutomatically {
              GroupRow {
                Text("Install updates automatically")
                Spacer()
                LiveToggle(title: "Install updates automatically", source: installAutomatically)
              }
            }
            GroupRow {
              Spacer()
              Button("Check now", action: checkForUpdates).buttonStyle(.pill)
            }
          }
        }
      }
    }
    // The window's toolbar carries the page's name; the page has no actions of its own.
    .navigationTitle("Settings")
  }

  /// A titled card of settings, with a note under it when it needs one.
  private func section<Body: View>(
    _ title: String, count: Int? = nil, footnote: String? = nil, @ViewBuilder content: () -> Body
  ) -> some View {
    VStack(alignment: .leading, spacing: 0) {
      SectionHeader(title, count: count)
      content()
      if let footnote { Footnote(footnote) }
    }
  }

  private var statusColor: Color {
    switch model.connection {
    case .online: .green
    case .connecting, .starting: .yellow
    case .offline: Color.primary.opacity(0.25)
    case .incompatible: .orange
    }
  }

  private var status: String {
    switch model.connection {
    case .online: model.status.map { "Running, version \($0.daemon.version)" } ?? "Running"
    case .connecting: "Looking for dryfit…"
    case .starting: "Starting…"
    case .offline: "Not running"
    case .incompatible(let version): "dryfit \(version) does not match this app"
    }
  }
}

/// A switch over a setting SwiftUI cannot observe (a login item, the updater's preference). It keeps
/// its own copy, and reads the setting back after each change, so it moves when clicked and shows
/// what really happened: a login item macOS refused, for one, turns it off again.
private struct LiveToggle: View {
  let title: String
  let source: Binding<Bool>
  @State private var isOn: Bool

  init(title: String, source: Binding<Bool>) {
    self.title = title
    self.source = source
    _isOn = State(initialValue: source.wrappedValue)
  }

  var body: some View {
    Toggle(
      title,
      isOn: Binding(
        get: { isOn },
        set: { wanted in
          source.wrappedValue = wanted
          isOn = source.wrappedValue
        })
    )
    .toggleStyle(.mini)
    .onAppear { isOn = source.wrappedValue }
  }
}
