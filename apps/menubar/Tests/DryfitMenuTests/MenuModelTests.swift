import DryfitAPI
import Foundation
import Testing

@testable import DryfitMenu

@MainActor @Suite struct MenuModelTests {
  let daemon = FakeDaemon()
  let notifier = RecordingNotifier()

  /// Whether the fake daemon is up, for tests that start it.
  final class Switch {
    var on = false
  }

  func makeModel(
    lookup: @escaping @MainActor () -> MenuModel.Lookup? = { nil },
    launch: @escaping @MainActor () async throws -> Void = {},
    install: @escaping @MainActor () async throws -> Void = {},
    appVersion: String? = nil,
    update: (@MainActor () async throws -> Void)? = nil,
    startAtLogin: StartAtLogin? = nil,
    devServers: DevServers = DevServers { _ in [] }
  ) -> MenuModel {
    let daemon = daemon
    return MenuModel(
      connect: { lookup() ?? .running(daemon, health) },
      launch: launch,
      install: install,
      appVersion: appVersion,
      update: update,
      startAtLogin: startAtLogin,
      notifier: notifier,
      devServers: devServers,
      sleep: { _ in try await Task.sleep(for: .milliseconds(2)) }
    )
  }

  /// Runs the model's connection loop for the length of the test.
  func started(_ model: MenuModel) async -> Task<Void, Never> {
    let task = Task { await model.run() }
    await eventually { model.connection == .online }
    return task
  }

  @Test func connectsAndShowsTheDaemonsState() async {
    let model = makeModel()
    let task = await started(model)
    defer { task.cancel() }

    #expect(model.status == linkedStatus)
    #expect(model.icon == .idle)
    #expect(model.libraries.map(\.library.name) == ["@acme/ui", "@acme/forms"])
    #expect(model.libraries.first?.links.map(\.consumer) == [shop])
  }

  @Test func showsOfflineAndStartsTheDaemonOnlyWhenAsked() async {
    let daemonUp = Switch()
    let model = makeModel(
      lookup: { daemonUp.on ? nil : .notRunning },
      launch: { daemonUp.on = true })
    let task = Task { await model.run() }
    defer { task.cancel() }

    await eventually { model.connection == .offline }
    #expect(model.icon == .offline)

    await model.startDaemon()

    await eventually { model.connection == .online }
    #expect(daemonUp.on)
  }

  @Test func explainsWhyTheDaemonCouldNotBeStarted() async {
    let model = makeModel(
      lookup: { .notRunning },
      launch: { throw DaemonLauncher.Failure.cliNotFound })
    let task = Task { await model.run() }
    defer { task.cancel() }
    await eventually { model.connection == .offline }

    await model.startDaemon()

    #expect(model.connection == .offline)
    #expect(model.startError?.contains("not installed") == true)
    #expect(model.cliMissing)
  }

  @Test func installsTheCLIWhenAsked_thenStartsTheDaemon() async {
    let installed = Switch()
    let daemonUp = Switch()
    let model = makeModel(
      lookup: { daemonUp.on ? nil : .notRunning },
      launch: {
        guard installed.on else { throw DaemonLauncher.Failure.cliNotFound }
        daemonUp.on = true
      },
      install: { installed.on = true })
    let task = Task { await model.run() }
    defer { task.cancel() }
    await eventually { model.connection == .offline }
    await model.startDaemon()
    #expect(model.cliMissing)

    await model.installCLI()

    await eventually { model.connection == .online }
    #expect(!model.cliMissing)
  }

  @Test func offersToUpdateDryfitOnlyWhenItIsOlderThanTheApp() async {
    // The fake daemon runs 0.1.0.
    for (appVersion, canUpdate, offered) in [
      ("0.3.0", true, "0.1.0"), ("0.1.0", true, nil), ("0.0.9", true, nil), ("0.3.0", false, nil),
      (nil, true, nil),
    ] as [(String?, Bool, String?)] {
      let model = canUpdate ? makeModel(appVersion: appVersion, update: {}) : makeModel(appVersion: appVersion)
      let task = await started(model)
      #expect(model.outdatedVersion == offered, "app \(appVersion ?? "nil"), update \(canUpdate)")
      task.cancel()
    }
  }

  @Test func updatesDryfitWhenAsked() async {
    let updated = Switch()
    let model = makeModel(appVersion: "0.3.0", update: { updated.on = true })
    let task = await started(model)
    defer { task.cancel() }

    await model.updateCLI()

    #expect(updated.on)
    #expect(!model.isBusy(.updateCLI))
    #expect(model.updateError == nil)
  }

  @Test func explainsWhyUpdatingDryfitFailed() async {
    let model = makeModel(
      appVersion: "0.3.0", update: { throw DaemonLauncher.Failure.failed(output: "npm error code E403") })
    let task = await started(model)
    defer { task.cancel() }

    await model.updateCLI()

    #expect(model.updateError == "npm error code E403")
    #expect(!model.isBusy(.updateCLI))
  }

  @Test func tellsWhichSideOfAnAPIMismatchIsOlder() async {
    let older = Health(
      name: "dryfit", version: "0.0.5", apiVersion: 0, pid: 42, registryUrl: health.registryUrl,
      startedAt: health.startedAt)
    let newer = Health(
      name: "dryfit", version: "1.0.0", apiVersion: 2, pid: 42, registryUrl: health.registryUrl,
      startedAt: health.startedAt)
    for (running, dryfitIsOlder) in [(older, true), (newer, false)] {
      let model = makeModel(lookup: { .incompatible(running) }, appVersion: "0.3.0", update: {})
      let task = Task { await model.run() }
      await eventually { model.connection == .incompatible(daemonVersion: running.version) }
      #expect((model.outdatedVersion != nil) == dryfitIsOlder)
      #expect(model.appIsOlder == !dryfitIsOlder)
      task.cancel()
    }
  }

  @Test func readsTheProjectFoldersOnConnecting_andReplacesThem() async {
    let model = makeModel()
    let task = await started(model)
    defer { task.cancel() }
    #expect(model.roots == ["/Users/me/repos"])

    try? await model.setRoots(["/Users/me/work"])

    #expect(model.roots == ["/Users/me/work"])
    #expect(await daemon.calls == ["setRoots /Users/me/work", "discover"])
  }

  @Test func addsALibraryWithTheSettingsChosen_thenLooksForItsProjects() async throws {
    let model = makeModel()
    let task = await started(model)
    defer { task.cancel() }

    let preview = try await model.inspect("/r/ui")
    try await model.register(preview.root, publishDir: "/r/ui/dist", build: BuildCommand(line: "npm run build"))

    #expect(await daemon.calls == ["inspect /r/ui", "register /r/ui /r/ui/dist npm run build", "discover"])
  }

  @Test func asksBeforeRestoringAnAppWhosePackageJsonChanged() async {
    let model = makeModel()
    let task = await started(model)
    defer { task.cancel() }
    await daemon.fail(with: APIError(code: .manifestDrifted, message: "package.json changed"))

    await model.restore(shop)

    #expect(model.driftedRestore == RestoreRequest(consumer: shop))
    #expect(model.actionError == nil)

    await daemon.fail(with: nil)
    await model.restore(shop, force: true)

    #expect(model.driftedRestore == nil)
    #expect(await daemon.calls.last == "restore \(shop) force")
  }

  @Test func restoresOneLibraryAndRetriesThatLibraryAfterADrift() async {
    let model = makeModel()
    let task = await started(model)
    defer { task.cancel() }
    await daemon.fail(with: APIError(code: .manifestDrifted, message: "package.json changed"))

    await model.restore(shop, library: "@acme/ui")
    #expect(model.driftedRestore == RestoreRequest(consumer: shop, library: "@acme/ui"))

    await daemon.fail(with: nil)
    let request = model.driftedRestore!
    await model.restore(request.consumer, library: request.library, force: true)
    #expect(await daemon.calls.last == "restore @acme/ui in \(shop) force")

    daemon.channel.send(.consumerRestored(consumer: shop, library: "@acme/ui", ok: true), id: 1)
    await eventually { model.activity == "Restored @acme/ui in shop" }
  }

  /// The dev servers running in each app, by folder.
  @MainActor final class Servers {
    var running: [String: [DevServer]] = [:]
    var finder: DevServers { DevServers { [unowned self] in running[$0] ?? [] } }
  }

  @Test func asksForADevServerRestartOnlyWhileOneFromBeforeTheInstallRuns() async {
    let servers = Servers()
    let model = makeModel(devServers: servers.finder)
    let task = await started(model)
    defer { task.cancel() }

    // Nothing running: the next start loads the new build.
    daemon.channel.send(.cachesCleared(consumer: shop, paths: [".angular/cache"]), id: 1)
    await eventually { model.lastEventID == 1 }
    #expect(model.restartNeeded.isEmpty)

    servers.running[shop] = [DevServer(pid: 41, started: .now.addingTimeInterval(-60))]
    daemon.channel.send(.cachesCleared(consumer: shop, paths: [".angular/cache"]), id: 2)
    await eventually { model.restartNeeded == [shop] }

    // The user restarts it: a new process, started after the install.
    servers.running[shop] = [DevServer(pid: 42, started: .now.addingTimeInterval(1))]
    await eventually { model.restartNeeded.isEmpty }
  }

  @Test func dropsTheRestartHintWhenTheServerStopsTheUserSaysSoOrTheAppIsPutBack() async {
    let servers = Servers()
    servers.running[shop] = [DevServer(pid: 41, started: .now.addingTimeInterval(-60))]
    let model = makeModel(devServers: servers.finder)
    let task = await started(model)
    defer { task.cancel() }

    daemon.channel.send(.cachesCleared(consumer: shop, paths: [".angular/cache"]), id: 1)
    await eventually { model.restartNeeded == [shop] }
    model.restarted(shop)
    #expect(model.restartNeeded.isEmpty)

    daemon.channel.send(.cachesCleared(consumer: shop, paths: [".angular/cache"]), id: 2)
    await eventually { model.restartNeeded == [shop] }
    daemon.channel.send(.consumerRestored(consumer: shop, library: "@acme/ui", ok: true), id: 3)
    await eventually { model.activity == "Restored @acme/ui in shop" }
    #expect(model.restartNeeded == [shop])
    daemon.channel.send(.consumerRestored(consumer: shop, library: nil, ok: true), id: 4)
    await eventually { model.restartNeeded.isEmpty }

    daemon.channel.send(.cachesCleared(consumer: shop, paths: [".angular/cache"]), id: 5)
    await eventually { model.restartNeeded == [shop] }
    servers.running[shop] = []
    await eventually { model.restartNeeded.isEmpty }
  }

  @Test func timesAClearingByTheDaemonsClockSoAReplayedOneIsNotNew() async {
    let servers = Servers()
    // Restarted ten minutes ago, after the install the replayed event reports.
    servers.running[shop] = [DevServer(pid: 41, started: .now.addingTimeInterval(-600))]
    let model = makeModel(devServers: servers.finder)
    model.handle(ServerEvent(
      id: 1, at: Date.now.addingTimeInterval(-3600).formatted(.iso8601), kind: .cachesCleared(consumer: shop, paths: [])))
    #expect(model.restartNeeded.isEmpty)
    model.handle(ServerEvent(id: 2, at: "2099-01-01T00:00:00.000Z", kind: .cachesCleared(consumer: shop, paths: [])))
    #expect(model.restartNeeded == [shop])
  }

  @Test func startsDryfitAtLogin_andKeepsItRunningWhenTurnedOff() async {
    var installed = false
    var launches = 0
    let model = makeModel(
      launch: { launches += 1 },
      startAtLogin: StartAtLogin(isOn: { installed }, set: { installed = $0 }))
    #expect(model.startsAtLogin == false)

    await model.setStartAtLogin(true)
    #expect(model.startsAtLogin == true)
    #expect(launches == 0)

    // Uninstalling stops launchd's daemon, so the app starts it again the usual way.
    await model.setStartAtLogin(false)
    #expect(model.startsAtLogin == false)
    #expect(launches == 1)
    #expect(!model.isBusy(.startAtLogin))
  }

  @Test func saysWhyStartingAtLoginFailed_andShowsWhatIsTrue() async {
    struct Refused: LocalizedError { var errorDescription: String? { "launchctl could not load the agent" } }
    let model = makeModel(startAtLogin: StartAtLogin(isOn: { false }, set: { _ in throw Refused() }))

    await model.setStartAtLogin(true)

    #expect(model.startsAtLogin == false)
    #expect(model.actionError == "launchctl could not load the agent")
  }

  @Test func offersNoStartAtLoginWhereTheAppCannotSetItUp() {
    #expect(makeModel().startsAtLogin == nil)
  }

  @Test func refusesADaemonOfAnotherAPIVersion() async {
    let newer = Health(name: "dryfit", version: "2.0.0", apiVersion: 2, pid: 1, registryUrl: "", startedAt: "")
    let model = makeModel(lookup: { .incompatible(newer) })
    let task = Task { await model.run() }
    defer { task.cancel() }

    await eventually { model.connection == .incompatible(daemonVersion: "2.0.0") }
    #expect(model.icon == .attention)
  }

  @Test func narratesWhatTheDaemonIsDoingAndRefreshesWhenStateChanges() async {
    let model = makeModel()
    let task = await started(model)
    defer { task.cancel() }
    let before = await daemon.statusCalls

    daemon.channel.send(.jobStarted(Job(id: 1, label: "sync @acme/ui", queuedAt: "")), id: 1)
    daemon.channel.send(.installStarted(library: "@acme/ui", consumer: shop, version: version), id: 2)
    await eventually { model.activity == "Installing @acme/ui into shop…" }
    #expect(model.icon == .working)

    daemon.channel.send(.stateChanged, id: 3)
    await eventually { await daemon.statusCalls > before }
  }

  @Test func waitsForASlowLaunchWithoutCallingTheStartFailed() async {
    let daemonUp = Switch()
    let model = makeModel(
      lookup: { daemonUp.on ? nil : .notRunning },
      launch: {
        // A login shell loading nvm: the connection loop runs many times meanwhile.
        try await Task.sleep(for: .milliseconds(150))
        daemonUp.on = true
      })
    let task = Task { await model.run() }
    defer { task.cancel() }
    await eventually { model.connection == .offline }

    let start = Task { await model.startDaemon() }
    try? await Task.sleep(for: .milliseconds(80))
    #expect(model.connection == .starting)
    #expect(model.startError == nil)

    await start.value
    await eventually { model.connection == .online }
    #expect(model.startError == nil)
  }

  @Test func notifiesOnlyFailuresNobodySaw_notRefusedRequests() async {
    let model = makeModel()
    let task = await started(model)
    defer { task.cancel() }

    let restore = Job(id: 1, label: "restore /repos/shop", queuedAt: "")
    daemon.channel.send(.jobFinished(restore, error: .init(code: "manifest-drifted", message: "package.json changed")), id: 1)
    let sync = Job(id: 2, label: "sync @acme/ui", queuedAt: "")
    daemon.channel.send(.jobFinished(sync, error: .init(code: "publish-failed", message: "Publishing failed")), id: 2)
    await eventually { notifier.posted.count == 1 }
    try? await Task.sleep(for: .milliseconds(20))

    #expect(notifier.posted.map(\.title) == ["Publishing failed"])
  }

  @Test func clearsProgressLeftByADaemonThatDiedMidJob() async {
    let model = makeModel()
    let task = await started(model)
    defer { task.cancel() }
    daemon.channel.send(.buildStarted(library: "@acme/ui"), id: 1)
    await eventually { model.activity != nil }

    daemon.channel.end()
    await eventually { daemon.channel.isOpen && model.connection == .online }

    #expect(model.activity == nil)
    #expect(model.icon == .idle)
  }

  @Test func namesAppsByFolderInJobLabels_evenWithSpacesInTheirPaths() async {
    let model = makeModel()
    let task = await started(model)
    defer { task.cancel() }

    daemon.channel.send(.jobStarted(Job(id: 1, label: "restore @acme/ui in /Users/me/My Apps/shop", queuedAt: "")), id: 1)
    await eventually { model.activity == "Restore @acme/ui in shop" }
    daemon.channel.send(.jobStarted(Job(id: 2, label: "hide /a/old shop, /b/admin", queuedAt: "")), id: 2)
    await eventually { model.activity == "Hide old shop, admin" }
  }

  @Test func reportsABuildFailureOnceWithItsOutput() async {
    let model = makeModel()
    let task = await started(model)
    defer { task.cancel() }

    daemon.channel.send(.buildFailed(library: "@acme/ui", output: "TS2304: Cannot find name 'Butto'."), id: 1)
    let job = Job(id: 1, label: "sync @acme/ui", queuedAt: "")
    daemon.channel.send(.jobFinished(job, error: .init(code: "build-failed", message: "Building @acme/ui failed")), id: 2)
    await eventually { notifier.posted.count == 1 }
    try? await Task.sleep(for: .milliseconds(20))

    #expect(notifier.posted.count == 1)
    #expect(model.failures.first?.title == "Build of @acme/ui failed")
    #expect(model.failures.first?.detail == "TS2304: Cannot find name 'Butto'.")
    #expect(model.icon == .attention)

    model.menuOpened()
    #expect(model.icon == .idle)
  }

  @Test func aBuildThatKeepsFailingIsOneFailure_heardOnce() async {
    let model = makeModel()
    let task = await started(model)
    defer { task.cancel() }

    daemon.channel.send(.buildFailed(library: "@acme/ui", output: "TS2304: Cannot find name 'Butto'."), id: 1)
    daemon.channel.send(.buildFailed(library: "@acme/ui", output: "TS2304: Cannot find name 'Buton'."), id: 2)
    await eventually { notifier.posted.count == 2 }

    #expect(model.failures.map(\.detail) == ["TS2304: Cannot find name 'Buton'."])
    #expect(notifier.quiet.map(\.detail) == ["TS2304: Cannot find name 'Buton'."])
  }

  @Test func aBuildOrInstallThatWorksAgainClearsItsFailureAndSaysSo() async {
    let model = makeModel()
    let task = await started(model)
    defer { task.cancel() }

    daemon.channel.send(.buildFailed(library: "@acme/ui", output: "TS2304"), id: 1)
    daemon.channel.send(
      .installFailed(library: "@acme/ui", consumer: admin, version: version, output: "npm ERR! ERESOLVE"), id: 2)
    daemon.channel.send(.watchFailed(library: "@acme/forms", message: "EMFILE"), id: 3)
    await eventually { model.failures.count == 3 }

    daemon.channel.send(.buildSucceeded(library: "@acme/ui"), id: 4)
    daemon.channel.send(.installSucceeded(library: "@acme/ui", consumer: shop, version: version), id: 5)
    daemon.channel.send(.installSucceeded(library: "@acme/ui", consumer: admin, version: version), id: 6)
    await eventually { model.failures.count == 1 }

    #expect(model.failures.map(\.title) == ["Auto-sync of @acme/forms stopped"])
    #expect(notifier.recoveries == ["@acme/ui builds again", "@acme/ui installs into admin again"])
    #expect(model.icon == .attention)
  }

  @Test func restoringAnAppClearsItsFailedInstalls_andNothingIsLeftToSee() async {
    let model = makeModel()
    let task = await started(model)
    defer { task.cancel() }

    daemon.channel.send(
      .installFailed(library: "@acme/ui", consumer: admin, version: version, output: "npm ERR! ERESOLVE"), id: 1)
    await eventually { model.failures.count == 1 }
    daemon.channel.send(.consumerRestored(consumer: admin, library: nil, ok: true), id: 2)
    await eventually { model.failures.isEmpty }

    #expect(!model.hasUnseenFailure)
    #expect(notifier.recoveries.isEmpty)
  }

  @Test func reportsFailedInstallsAndJobsWithoutOwnEvents() async {
    let model = makeModel()
    let task = await started(model)
    defer { task.cancel() }

    daemon.channel.send(
      .installFailed(library: "@acme/ui", consumer: admin, version: version, output: "npm ERR! ERESOLVE"), id: 1)
    let job = Job(id: 2, label: "sync @acme/ui", queuedAt: "")
    daemon.channel.send(.jobFinished(job, error: .init(code: "publish-failed", message: "Publishing failed")), id: 2)
    daemon.channel.send(.watchFailed(library: "@acme/ui", message: "EMFILE"), id: 3)
    await eventually { notifier.posted.count == 3 }

    #expect(notifier.posted.map(\.title) == [
      "Install of @acme/ui into admin failed", "Publishing failed", "Auto-sync of @acme/ui stopped",
    ])
  }

  @Test func reconnectsWhenTheDaemonGoesAwayAndResumesAfterTheLastEvent() async {
    let model = makeModel()
    let task = await started(model)
    defer { task.cancel() }
    daemon.channel.send(.stateChanged, id: 41)
    await eventually { model.lastEventID == 41 }

    daemon.channel.end()

    await eventually { daemon.channel.resumedAfter.count == 2 }
    #expect(daemon.channel.resumedAfter == [nil, 41])
    await eventually { model.connection == .online }
  }

  @Test func runsActionsAndShowsTheirErrors() async {
    let model = makeModel()
    let task = await started(model)
    defer { task.cancel() }

    await model.sync("@acme/ui")
    await model.setWatch("@acme/ui", enabled: false)
    await model.link("@acme/ui", into: admin)
    #expect(await daemon.calls == ["sync @acme/ui", "watch @acme/ui false", "link @acme/ui \(admin)"])
    #expect(model.actionError == nil)

    await daemon.fail(with: APIError(code: .snapshotMissing, message: "No snapshot of shop was found."))
    await model.restore(shop)
    #expect(model.actionError == "No snapshot of shop was found.")
    #expect(model.isBusy(.restore(shop, nil)) == false)
  }

  @Test func leavesBuildFailuresToTheirEventInsteadOfRepeatingThem() async {
    let model = makeModel()
    let task = await started(model)
    defer { task.cancel() }
    await daemon.fail(with: APIError(code: .buildFailed, message: "Building @acme/ui failed", output: "TS2304"))

    await model.sync("@acme/ui")

    #expect(model.actionError == nil)
  }

  @Test func recordsARestoreWhoseCleanInstallFailed() async {
    let model = makeModel()
    let task = await started(model)
    defer { task.cancel() }
    await daemon.setRestoreReply(RestoreResult(ok: false, output: "npm ERR! network"))

    await model.restore(shop)

    #expect(model.failures.first?.title == "Restored shop, but the clean install failed")
    #expect(model.failures.first?.detail == "npm ERR! network")
  }

  @Test func summarisesGroupMembersThatFailed() async {
    let model = makeModel()
    let task = await started(model)
    defer { task.cancel() }
    await daemon.setGroupReply([
      .init(consumer: shop, status: .done),
      .init(consumer: admin, status: .failed, message: "Install into admin failed"),
    ])

    await model.linkGroup("checkout", library: "@acme/ui")

    #expect(model.actionError == "admin: Install into admin failed")
  }

  @Test func offersToLinkOnlyDiscoveredConsumersThatUseTheLibraryAndAreNotLinked() async {
    let model = makeModel()
    let task = await started(model)
    defer { task.cancel() }
    await daemon.setDiscovered([
      DiscoveredConsumer(root: shop, name: "shop", libraries: [.init(name: "@acme/ui", range: "^1.4.0")], packageManager: .npm),
      DiscoveredConsumer(root: admin, name: "admin", libraries: [.init(name: "@acme/ui", range: "^1.4.0")], packageManager: .npm),
      DiscoveredConsumer(root: "/r/blog", name: "blog", libraries: [.init(name: "@acme/forms", range: "*")], packageManager: .npm),
    ])

    await model.discoverConsumers()

    #expect(model.linkCandidates(for: "@acme/ui").map(\.root) == [admin])
    #expect(model.linkCandidates(for: "@acme/forms").map(\.root) == ["/r/blog"])
  }

  @Test func listsAppsThatUseALibraryOrAreLinkedToOne() async {
    let model = makeModel()
    let task = await started(model)
    defer { task.cancel() }
    await daemon.setDiscovered([
      DiscoveredConsumer(root: admin, name: "admin", libraries: [.init(name: "@acme/ui", range: "^1.4.0")], packageManager: .pnpm),
      DiscoveredConsumer(root: "/r/blog", name: "blog", libraries: [.init(name: "@acme/forms", range: "*")], packageManager: .npm),
      DiscoveredConsumer(root: "/r/other", name: "other", libraries: [.init(name: "left-pad", range: "*")], packageManager: .npm),
    ])

    await model.discoverConsumers()

    #expect(model.apps.map(\.name) == ["admin", "blog", "shop"])
    let shopApp = model.apps.first { $0.root == shop }
    #expect(shopApp?.linked.map(\.library) == ["@acme/ui"])
    #expect(shopApp?.packageManager == nil)
    let adminApp = model.apps.first { $0.root == admin }
    #expect(adminApp?.unlinked.map(\.library) == ["@acme/ui"])
    #expect(adminApp?.libraries.first?.range == "^1.4.0")
    #expect(adminApp?.packageManager == "pnpm")
  }

  @Test func hidesAnApp_untilItIsShownAgain() async {
    await daemon.setDiscovered([
      DiscoveredConsumer(root: admin, name: "admin", libraries: [.init(name: "@acme/ui", range: "^1.4.0")], packageManager: .npm)
    ])
    let model = makeModel()
    let task = await started(model)
    defer { task.cancel() }
    await model.discoverConsumers()
    #expect(model.hiddenApps == [])
    #expect(model.apps.map(\.root).contains(admin))
    let navigation = AppNavigation()
    navigation.selection = .app(admin)

    await model.hideApp(admin, navigation: navigation)

    #expect(model.hiddenApps == [admin])
    #expect(!model.apps.map(\.root).contains(admin))
    #expect(model.linkCandidates(for: "@acme/ui").isEmpty)
    #expect(navigation.selection == nil)

    await model.showApp(admin)

    #expect(model.hiddenApps == [])
    #expect(model.apps.map(\.root).contains(admin))
    #expect(await daemon.calls.suffix(3) == ["hide \(admin)", "show \(admin)", "discover"])
  }

  @Test func saysWhyALinkedAppCannotBeHidden() async {
    let model = makeModel()
    let task = await started(model)
    defer { task.cancel() }
    await daemon.fail(with: APIError(code: .consumerLinked, message: "\(shop) is still linked; restore it first"))

    await model.hideApp(shop)

    #expect(model.actionError?.contains("restore it first") == true)
    #expect(model.hiddenApps == [])
    #expect(model.apps.map(\.root).contains(shop))
  }

  @Test func opensAFolderAsAnApp_aLibrary_orSaysWhyNot() async throws {
    let model = makeModel()
    let task = await started(model)
    defer { task.cancel() }
    let folder = FileManager.default.temporaryDirectory.appending(path: "dryfit-apps-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: folder) }
    func project(_ name: String, _ manifest: String?, lockfile: String? = nil) throws -> String {
      let root = folder.appending(path: name)
      try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
      if let manifest { try manifest.write(to: root.appending(path: "package.json"), atomically: true, encoding: .utf8) }
      if let lockfile { try "".write(to: root.appending(path: lockfile), atomically: true, encoding: .utf8) }
      return root.path(percentEncoded: false)
    }
    let store = try project(
      "store", #"{"name":"store","devDependencies":{"@acme/forms":"^2.0.0","typescript":"~5.9.0"}}"#,
      lockfile: "pnpm-lock.yaml")
    let unrelated = try project("unrelated", #"{"name":"unrelated","dependencies":{"left-pad":"*"}}"#)
    let empty = try project("empty", nil)
    let navigation = AppNavigation()

    model.open(store, navigation: navigation, orAddAsLibrary: false)
    #expect(navigation.selection == .app(store))
    let app = model.apps.first { $0.root == store }
    #expect(app?.unlinked.map(\.library) == ["@acme/forms"])
    #expect(app?.libraries.first?.range == "^2.0.0")
    #expect(app?.packageManager == "pnpm")
    #expect(model.linkCandidates(for: "@acme/forms").map(\.root) == [store])

    model.open(unrelated, navigation: navigation, orAddAsLibrary: false)
    #expect(model.actionError?.contains("does not depend on any of your libraries") == true)
    model.open(unrelated, navigation: navigation, orAddAsLibrary: true)
    #expect(navigation.libraryEditor?.root == unrelated)

    model.open(empty, navigation: navigation, orAddAsLibrary: true)
    #expect(model.actionError == "empty has no package.json. Choose the folder that holds it.")

    model.open(ui.root, navigation: navigation, orAddAsLibrary: true)
    #expect(navigation.selection == .library("@acme/ui"))
    #expect(model.actionError == nil)
  }

  @Test func listsLibrariesInTheOrderTheUserDraggedThem_andKeepsIt() async {
    var kept = ItemOrder()
    let store = ItemOrderStore(load: { kept }, save: { kept = $0 })
    let model = MenuModel(
      connect: { [daemon] in .running(daemon, health) }, launch: {}, notifier: notifier, orderStore: store,
      sleep: { _ in try await Task.sleep(for: .milliseconds(2)) })
    let task = await started(model)
    defer { task.cancel() }
    #expect(model.libraries.map(\.id) == ["@acme/ui", "@acme/forms"])

    model.move(.libraries, ids: model.libraries.map(\.id), from: [1], to: 0)

    #expect(model.libraries.map(\.id) == ["@acme/forms", "@acme/ui"])
    #expect(kept.libraries == ["@acme/forms", "@acme/ui"])
    let relaunched = MenuModel(connect: { .notRunning }, launch: {}, notifier: notifier, orderStore: store)
    #expect(relaunched.order.libraries == ["@acme/forms", "@acme/ui"])
  }

  @Test func putsItemsNeverMovedAfterTheMovedOnes_inTheirOwnOrder() {
    var order = ItemOrder()
    order.apps = ["/r/c", "/r/a"]

    #expect(order.sorted(["/r/a", "/r/b", "/r/c", "/r/d"], .apps, by: { $0 }) == ["/r/c", "/r/a", "/r/b", "/r/d"])
  }

  @Test func rightClickingTheMenuBarIconOffersWhatTheFootersMenuDid() async {
    let model = makeModel()
    let task = await started(model)
    defer { task.cancel() }
    func titles(_ actions: MenuActions) -> [String] {
      StatusMenu(model: model, actions: actions).makeMenu().items.map(\.title).filter { !$0.isEmpty }
    }

    #expect(titles(MenuActions(checkForUpdates: {})) == [
      "Open dryfit", "Settings…", "Open Log", "Check for Updates…", "Stop dryfit", "Quit dryfit",
    ])
    #expect(!titles(MenuActions()).contains("Check for Updates…"))
  }

  /// The Open panel hands back folder paths ending in a slash; the daemon stores them without one.
  @Test func opensAFolderChosenWithATrailingSlashAsTheSameApp() async throws {
    let model = makeModel()
    let task = await started(model)
    defer { task.cancel() }
    let folder = FileManager.default.temporaryDirectory.appending(path: "dryfit-slash-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: folder) }
    let store = folder.appending(path: "store")
    try FileManager.default.createDirectory(at: store, withIntermediateDirectories: true)
    try #"{"name":"store","dependencies":{"@acme/forms":"^2.0.0"}}"#
      .write(to: store.appending(path: "package.json"), atomically: true, encoding: .utf8)
    let root = store.path(percentEncoded: false)
    let navigation = AppNavigation()

    model.open(root + "/", navigation: navigation, orAddAsLibrary: false)
    model.open(root, navigation: navigation, orAddAsLibrary: false)

    #expect(navigation.selection == .app(root))
    #expect(model.apps.filter { $0.name == "store" }.map(\.root) == [root])
    #expect(folderPath(URL(filePath: root, directoryHint: .isDirectory)) == root)
    #expect(normalizedPath("/") == "/")
  }
}
