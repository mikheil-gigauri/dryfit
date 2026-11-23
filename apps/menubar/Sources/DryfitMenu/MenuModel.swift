import DryfitAPI
import Foundation
import Observation

/// Something worth telling the user about: a failed build, install, publish or watch.
public struct Failure: Identifiable, Equatable, Sendable {
  public let id: UUID
  public let title: String
  /// The captured output, or the daemon's explanation.
  public let detail: String
  public let date: Date
  /// The app an install failed in, so its row can show the output.
  public let consumer: String?
  /// What failed, such as the build of one library, so a newer failure of it replaces this one and a
  /// success clears it. Nil for one-off failures, which stay until dismissed.
  public let subject: String?
  /// The library the failure is about, so the failures window can open its page.
  public let library: String?

  public init(
    id: UUID = UUID(), title: String, detail: String, date: Date = .now, consumer: String? = nil,
    subject: String? = nil, library: String? = nil
  ) {
    self.id = id
    self.title = title
    self.detail = detail
    self.date = date
    self.consumer = consumer
    self.subject = subject
    self.library = library
  }
}

/// Posts failures where the user will see them: a system notification in the app.
public protocol Notifier: AnyObject {
  /// `quietly` when the same thing was failing already: the user has heard, so it replaces the last
  /// notification of it without a sound.
  func post(_ failure: Failure, quietly: Bool)
  /// What `failure` was about works again; `message` says so in place of its notification.
  func recovered(_ failure: Failure, message: String)
}

/// A restore to retry once the user agrees: an app, and the one library in it or nil for all.
public struct RestoreRequest: Equatable, Sendable {
  public let consumer: String
  public let library: String?

  public init(consumer: String, library: String? = nil) {
    self.consumer = consumer
    self.library = library
  }
}

/// Whether dryfit's service starts when the user logs in (`dryfit daemon install`), and how to change it.
public struct StartAtLogin {
  public let isOn: () -> Bool
  public let set: (Bool) async throws -> Void

  public init(isOn: @escaping () -> Bool, set: @escaping (Bool) async throws -> Void) {
    self.isOn = isOn
    self.set = set
  }
}

/// A library with the consumers it is linked into.
public struct LibraryRow: Identifiable, Equatable {
  public let library: Library
  public let links: [Link]
  public var id: String { library.name }
}

/// The menu's state and actions (ADR 0013). It follows the daemon's events, keeps `status` current,
/// and never starts the daemon unless asked.
@Observable public final class MenuModel {
  public enum Lookup: Sendable {
    case running(any DaemonAPI, Health)
    case notRunning
    case incompatible(Health)
  }

  public enum Connection: Equatable {
    case connecting, offline, starting, online
    /// The daemon speaks another API version; dryfit or this app needs updating.
    case incompatible(daemonVersion: String)
  }

  /// What the menu bar icon shows, most urgent first.
  public enum Icon: Equatable {
    case offline, attention, working, idle
  }

  /// Something the user started; while it runs, its control shows progress and cannot be repeated.
  public enum Action: Hashable {
    /// `restore(consumer, library)`: one library in an app, or all of them when the library is nil.
    case sync(String), watch(String), link(String, String), restore(String, String?)
    case linkGroup(String), restoreGroup(String), discover
    case register(String), unregister(String), saveGroup(String), deleteGroup(String)
    case roots, stop, installCLI, updateCLI, startAtLogin
    /// Hiding or showing an app again, by its folder.
    case hide(String)
  }

  public internal(set) var connection = Connection.connecting
  public internal(set) var status: Status?
  /// What the daemon is doing now, in words.
  public internal(set) var activity: String?
  /// Newest first.
  public internal(set) var failures: [Failure] = []
  public internal(set) var hasUnseenFailure = false
  /// Apps whose framework caches dryfit cleared after installing a dev build while their dev server
  /// was running: it still holds what was deleted and shows the change only after a restart (ADR 0007).
  /// Kept until that server restarts or stops, the user says it needs no restart, or the app is put back.
  public internal(set) var restartNeeded: Set<String> = []
  public internal(set) var consumers: [DiscoveredConsumer] = []
  /// Apps the user added by hand from outside the project folders, until they are linked.
  public internal(set) var addedApps: [DiscoveredConsumer] = []
  public internal(set) var inFlight: Set<Action> = []
  /// Why the last action did not work, shown under the controls.
  public internal(set) var actionError: String?
  /// Why starting the daemon did not work.
  public internal(set) var startError: String?
  /// Starting failed because the CLI is not installed, so the app offers to install it.
  public internal(set) var cliMissing = false
  /// Why updating dryfit did not work.
  public internal(set) var updateError: String?
  /// This app's version, to tell whether dryfit is older; nil outside a built app.
  public let appVersion: String?
  /// The folders searched for projects; nil until the daemon has said.
  public internal(set) var roots: [String]?
  /// Apps the user hid, which dryfit no longer lists; nil until the daemon has said.
  public internal(set) var hiddenApps: [String]?
  /// An app whose restore was refused because its package.json changed since it was linked. The
  /// user decides whether to restore it anyway.
  public var driftedRestore: RestoreRequest?
  /// Whether dryfit's service starts at login, so auto-sync is on again after a restart; nil where
  /// the app cannot change it (outside a built app). The app opening at login does not start it.
  public internal(set) var startsAtLogin: Bool?
  /// The order the user put libraries, apps and groups in; kept between launches.
  public internal(set) var order: ItemOrder {
    didSet { if order != oldValue { orderStore.save(order) } }
  }
  private(set) var lastEventID: Int?

  @ObservationIgnored private let connect: () async -> Lookup
  @ObservationIgnored private let launch: () async throws -> Void
  @ObservationIgnored private let install: () async throws -> Void
  /// Updates the CLI and restarts the daemon with it; nil when the app cannot (a checkout's CLI).
  @ObservationIgnored private let update: (() async throws -> Void)?
  @ObservationIgnored private let startAtLogin: StartAtLogin?
  @ObservationIgnored private let notifier: any Notifier
  @ObservationIgnored private let orderStore: ItemOrderStore
  @ObservationIgnored private let devServers: DevServers
  /// When dryfit cleared each app's caches, for apps whose dev server may predate it.
  @ObservationIgnored private var clearedAt: [String: Date] = [:]
  /// Looks at the dev servers again while any app waits on a restart.
  @ObservationIgnored private var devServerWatch: Task<Void, Never>?
  /// Tests' clock; nil sleeps for real.
  @ObservationIgnored private let sleep: (@Sendable (Duration) async throws -> Void)?
  @ObservationIgnored private var api: (any DaemonAPI)?
  @ObservationIgnored private var nudged = false
  /// The status request in flight; callers that arrive meanwhile wait for it and its re-run.
  @ObservationIgnored private var refreshing: Task<Void, Never>?
  @ObservationIgnored private var refreshAgain = false
  @ObservationIgnored private var startDeadline: ContinuousClock.Instant?

  static let minimumDelay = Duration.seconds(1)
  static let maximumDelay = Duration.seconds(10)
  static let startTimeout = Duration.seconds(30)
  static let stableConnection = Duration.seconds(30)
  static let devServerInterval = Duration.seconds(2)
  static let unseenFailureCodes: Set<String> = [
    "publish-failed", "registry-failed", "state-corrupt", "daemon-failed", "internal",
  ]

  public init(
    connect: @escaping () async -> Lookup,
    launch: @escaping () async throws -> Void,
    install: @escaping () async throws -> Void = {},
    appVersion: String? = nil,
    update: (() async throws -> Void)? = nil,
    startAtLogin: StartAtLogin? = nil,
    notifier: any Notifier,
    orderStore: ItemOrderStore = .memory,
    devServers: DevServers = .system,
    // No closure literal as the default: Swift 6.2 on macOS 26 aborts in swift_task_dealloc when a
    // default async closure from this MainActor-by-default module is called ("freed pointer was not
    // the last allocation").
    sleep: (@Sendable (Duration) async throws -> Void)? = nil
  ) {
    self.connect = connect
    self.launch = launch
    self.install = install
    self.appVersion = appVersion
    self.update = update
    self.startAtLogin = startAtLogin
    self.startsAtLogin = startAtLogin?.isOn()
    self.notifier = notifier
    self.orderStore = orderStore
    self.devServers = devServers
    self.order = orderStore.load()
    self.sleep = sleep
  }

  // MARK: Derived state

  public var icon: Icon {
    switch connection {
    case .connecting, .offline, .starting: return .offline
    case .incompatible: return .attention
    case .online: break
    }
    if hasUnseenFailure || status?.links.contains(where: { $0.status == .failed }) == true { return .attention }
    if status?.jobs.running != nil || activity != nil || !inFlight.isEmpty { return .working }
    return .idle
  }

  /// The libraries in the user's order, each with its links in the user's order of apps.
  public var libraries: [LibraryRow] {
    guard let status else { return [] }
    let appRank = Dictionary(apps.enumerated().map { ($1.root, $0) }, uniquingKeysWith: { first, _ in first })
    return order.sorted(status.libraries, .libraries, by: \.name).map { library in
      LibraryRow(
        library: library,
        links: status.links.filter { $0.library == library.name }
          .sorted { (appRank[$0.consumer] ?? .max) < (appRank[$1.consumer] ?? .max) })
    }
  }

  /// Discovered consumers that depend on `library` and are not linked to it yet.
  public func linkCandidates(for library: String) -> [DiscoveredConsumer] {
    let linked = Set(status?.links.filter { $0.library == library }.map(\.consumer) ?? [])
    let hidden = Set(hiddenApps ?? [])
    let found = consumers + addedApps.filter { added in !consumers.contains { $0.root == added.root } }
    return found.filter { consumer in
      !hidden.contains(consumer.root) &&
      consumer.libraries.contains { $0.name == library } && !linked.contains(consumer.root)
    }
  }

  public func isBusy(_ action: Action) -> Bool { inFlight.contains(action) }

  /// The running dryfit's version when it is older than this app and the app can update it, else
  /// nil. The app updates itself, but the CLI it runs comes from npm and stays where it was.
  public var outdatedVersion: String? {
    guard update != nil, let appVersion, let running = runningVersion,
      ReleaseVersion.isOlder(running, than: appVersion)
    else { return nil }
    return running
  }

  /// Whether this app is older than the dryfit it found, so the app, not dryfit, needs updating.
  public var appIsOlder: Bool {
    guard let appVersion, let running = runningVersion else { return false }
    return ReleaseVersion.isOlder(appVersion, than: running)
  }

  private var runningVersion: String? {
    switch connection {
    case .online: status?.daemon.version
    case .incompatible(let daemonVersion): daemonVersion
    default: nil
    }
  }

  /// The latest failed install into `consumer` this session, with its output.
  public func installFailure(in consumer: String) -> Failure? {
    failures.first { $0.consumer == consumer }
  }

  /// Every project dryfit knows of: linked ones and those found in the project folders, by path.
  public var knownProjects: [String] {
    var paths = Set(consumers.map(\.root))
    paths.formUnion(status?.links.map(\.consumer) ?? [])
    paths.formUnion(status?.groups.flatMap(\.consumers) ?? [])
    return paths.sorted { projectName($0).localizedStandardCompare(projectName($1)) == .orderedAscending }
  }

  /// Needs the user's first steps: no project folders chosen, or no library added.
  public var needsSetup: Bool {
    connection == .online && (status?.libraries.isEmpty ?? false)
  }

  // MARK: Connection

  /// Follows the daemon for as long as the app runs: connects, follows its events, and when it goes
  /// away, looks again with backoff (re-reading `daemon.json`, since a restarted daemon may move).
  public func run() async {
    var delay = Self.minimumDelay
    while !Task.isCancelled {
      switch await connect() {
      case .running(let api, _):
        // Back to a quick retry only after a connection that held; one that drops straight away
        // (a stream the daemon keeps ending) keeps backing off instead of spinning every second.
        let connected = ContinuousClock.now
        await follow(api)
        if connected.duration(to: .now) >= Self.stableConnection { delay = Self.minimumDelay }
      case .notRunning:
        api = nil
        if connection == .starting, let deadline = startDeadline, ContinuousClock.now < deadline { break }
        if connection == .starting {
          startError = "dryfit did not start within 30 seconds. Open the log to see why."
          startDeadline = nil
        }
        connection = .offline
      case .incompatible(let health):
        api = nil
        connection = .incompatible(daemonVersion: health.version)
      }
      await pause(delay)
      delay = min(delay * 2, Self.maximumDelay)
    }
  }

  /// Starts the daemon at the user's request, then looks for it straight away.
  public func startDaemon() async {
    guard connection == .offline else { return }
    connection = .starting
    startError = nil
    // Set before launching: the launch itself can take seconds (a login shell loading nvm), and the
    // connection loop must not call the start failed meanwhile.
    startDeadline = .now + Self.startTimeout
    do {
      try await launch()
      cliMissing = false
      nudged = true
    } catch {
      cliMissing = (error as? DaemonLauncher.Failure) == .cliNotFound
      startError = error.localizedDescription
      startDeadline = nil
      connection = .offline
    }
  }

  /// Installs the CLI with npm at the user's request, then starts the daemon with it.
  public func installCLI() async {
    guard !inFlight.contains(.installCLI) else { return }
    inFlight.insert(.installCLI)
    startError = nil
    do {
      try await install()
      cliMissing = false
      inFlight.remove(.installCLI)
      await startDaemon()
    } catch {
      startError = error.localizedDescription
      inFlight.remove(.installCLI)
    }
  }

  /// Updates dryfit with npm at the user's request and restarts it on the new version. The
  /// connection loop finds the restarted daemon by itself, as after any restart.
  public func updateCLI() async {
    guard let update, !inFlight.contains(.updateCLI) else { return }
    inFlight.insert(.updateCLI)
    updateError = nil
    defer { inFlight.remove(.updateCLI) }
    do {
      try await update()
    } catch {
      updateError = error.localizedDescription
    }
  }

  /// Starts dryfit's service at login, or stops doing so. Either way the service runs on: turning it
  /// on restarts it under launchd, and turning it off stops launchd's, so it is started again here.
  public func setStartAtLogin(_ enabled: Bool) async {
    guard let startAtLogin, !inFlight.contains(.startAtLogin) else { return }
    inFlight.insert(.startAtLogin)
    actionError = nil
    do {
      try await startAtLogin.set(enabled)
      if !enabled { try await launch() }
      nudged = true
    } catch {
      actionError = error.localizedDescription
    }
    startsAtLogin = startAtLogin.isOn()
    inFlight.remove(.startAtLogin)
  }

  /// Stops the daemon. The app keeps running and offers to start it again.
  public func stopDaemon() async {
    await perform(.stop) { _ = try await $0.shutdown() }
  }

  /// The user opened the menu, so any failure has now been seen.
  public func menuOpened() {
    hasUnseenFailure = false
  }

  /// The user has read why the last action failed.
  public func dismissActionError() {
    actionError = nil
  }

  /// The user says the app's dev server needs no restart, as when it reloaded by itself.
  public func restarted(_ consumer: String) {
    clearedAt[consumer] = nil
    restartNeeded.remove(consumer)
  }

  /// Asks for a restart only in apps with a dev server that started before their caches were cleared.
  /// One that started since has the new build, and with none running the next start loads it.
  func checkDevServers() {
    clearedAt = clearedAt.filter { consumer, cleared in
      devServers.running(consumer).contains { $0.started < cleared }
    }
    let waiting = Set(clearedAt.keys)
    if waiting != restartNeeded { restartNeeded = waiting }
    if !waiting.isEmpty, devServerWatch == nil {
      devServerWatch = Task { [weak self] in
        while let self, !Task.isCancelled {
          if let sleep { try? await sleep(Self.devServerInterval) } else { try? await Task.sleep(for: Self.devServerInterval) }
          checkDevServers()
          if clearedAt.isEmpty { break }
        }
        self?.devServerWatch = nil
      }
    }
  }

  /// The user dismissed the failures they have read.
  public func clearFailures() {
    failures = []
    hasUnseenFailure = false
  }

  private func follow(_ api: any DaemonAPI) async {
    self.api = api
    // Subscribed before reading status, so nothing that happens in between is missed.
    let events = api.events(after: lastEventID)
    // Online once there is something to show, so the menu never flashes an empty daemon.
    // Anything shown as in progress belonged to the daemon before this connection; it may have died
    // mid-job and never sent job:finished.
    await refresh(clearingActivityWhenIdle: true)
    if roots == nil { roots = try? await api.roots() }
    if hiddenApps == nil { hiddenApps = try? await api.hiddenApps() }
    connection = .online
    startError = nil
    startDeadline = nil
    do {
      for try await event in events { handle(event) }
    } catch {}
    self.api = nil
    activity = nil
    if !Task.isCancelled { connection = .offline }
  }

  private func pause(_ total: Duration) async {
    let step = Duration.milliseconds(250)
    var waited = Duration.zero
    while waited < total, !nudged, !Task.isCancelled {
      if let sleep { try? await sleep(step) } else { try? await Task.sleep(for: step) }
      waited += step
    }
    nudged = false
  }

  // MARK: Events

  func handle(_ event: ServerEvent) {
    lastEventID = event.id
    switch event.kind {
    case .buildStarted(let library):
      activity = "Building \(library)…"
    case .buildFailed(let library, let output):
      fail("Build of \(library) failed", output, subject: Self.buildSubject(library), library: library)
    case .buildSucceeded(let library):
      recover(Self.buildSubject(library), "\(library) builds again")
    case .publishSucceeded(let library, let version):
      activity = "Published \(library) \(DevVersion.describe(version))"
    case .installStarted(let library, let consumer, _):
      activity = "Installing \(library) into \(projectName(consumer))…"
    case .installFailed(let library, let consumer, _, let output):
      fail(
        "Install of \(library) into \(projectName(consumer)) failed", output, consumer: consumer,
        subject: Self.installSubject(library, consumer), library: library)
    case .installSucceeded(let library, let consumer, _):
      recover(Self.installSubject(library, consumer), "\(library) installs into \(projectName(consumer)) again")
    case .consumerRestored(let consumer, let library, _):
      activity = library.map { "Restored \($0) in \(projectName(consumer))" } ?? "Restored \(projectName(consumer))"
      // Back on its releases, the app has no dev build left to restart for.
      if library == nil { restarted(consumer) }
      // Nor a failed install to show: its row is gone, and the failure would turn into a banner.
      failures.removeAll { failure in
        failure.consumer == consumer && (library.map { failure.subject == Self.installSubject($0, consumer) } ?? true)
      }
      if failures.isEmpty { hasUnseenFailure = false }
    case .cachesCleared(let consumer, _):
      // The daemon's time, so an event replayed after reconnecting is not taken as new.
      clearedAt[consumer] = Self.date(event.at) ?? .now
      checkDevServers()
    case .jobStarted(let job):
      activity = describe(job)
      scheduleRefresh()
    case .jobQueued, .stateChanged:
      scheduleRefresh()
    case .jobFinished(_, let error):
      // A failed build or install has its own event with the output. A refused request (drifted,
      // already linked, bad input) went back to whoever asked, this app or the CLI, so only failures
      // nobody saw are reported here.
      if let error, Self.unseenFailureCodes.contains(error.code) { fail(error.message, error.message) }
      Task { await refresh(clearingActivityWhenIdle: true) }
    case .watchFailed(let library, let message):
      fail("Auto-sync of \(library) stopped", message, subject: "watch \(library)", library: library)
      scheduleRefresh()
    case .libraryChanged, .unknown:
      break
    }
  }

  private static func buildSubject(_ library: String) -> String { "build \(library)" }

  /// An event's ISO 8601 time, as the daemon writes it (with milliseconds) or without them.
  static func date(_ at: String) -> Date? {
    (try? Date(at, strategy: Date.ISO8601FormatStyle(includingFractionalSeconds: true)))
      ?? (try? Date(at, strategy: .iso8601))
  }
  private static func installSubject(_ library: String, _ consumer: String) -> String {
    "install \(library) into \(consumer)"
  }

  /// Records a failure. One of something already failing takes its place, so saving a broken file again
  /// and again shows one failure, not a pile, and notifies once with a sound.
  private func fail(
    _ title: String, _ detail: String, consumer: String? = nil, subject: String? = nil, library: String? = nil
  ) {
    let failure = Failure(title: title, detail: detail, consumer: consumer, subject: subject, library: library)
    let repeated = subject != nil && failures.contains { $0.subject == subject }
    failures = Array(([failure] + failures.filter { subject == nil || $0.subject != subject }).prefix(20))
    hasUnseenFailure = true
    notifier.post(failure, quietly: repeated)
  }

  /// What failed works again: its failure is gone from the menu, and its notification says so.
  private func recover(_ subject: String, _ message: String) {
    guard let failure = failures.first(where: { $0.subject == subject }) else { return }
    failures.removeAll { $0.subject == subject }
    if failures.isEmpty { hasUnseenFailure = false }
    notifier.recovered(failure, message: message)
  }

  private func scheduleRefresh() {
    Task { await refresh() }
  }

  /// Reloads status. Requests that arrive while one is loading fold into a single follow-up.
  private func refresh(clearingActivityWhenIdle: Bool = false) async {
    // One request at a time. A caller that arrives mid-request asks for another round and waits
    // for it, so the status it sees was read after whatever it just did.
    if let running = refreshing {
      refreshAgain = true
      await running.value
    } else {
      let task = Task {
        repeat {
          refreshAgain = false
          guard let api else { break }
          if let next = try? await api.status(), next != status { status = next }
        } while refreshAgain
        // Cleared in the task, not by its first waiter, so a caller arriving after the last round
        // starts a new one instead of waiting on a finished task.
        refreshing = nil
      }
      refreshing = task
      await task.value
    }
    if clearingActivityWhenIdle, status?.jobs.running == nil, status?.jobs.queued.isEmpty != false {
      activity = nil
    }
  }

  // MARK: Actions

  public func sync(_ library: String) async {
    await perform(.sync(library)) { _ = try await $0.sync(library: library) }
  }

  public func setWatch(_ library: String, enabled: Bool) async {
    await perform(.watch(library)) { _ = try await $0.setWatch(library: library, enabled: enabled) }
  }

  public func link(_ library: String, into consumer: String) async {
    await perform(.link(library, consumer)) { api in
      let result = try await api.link(library: library, consumer: consumer)
      if result.guardOutcome == .failed {
        // Linked all the same: say that nothing will stop the dev build from being committed.
        self.actionError =
          "Linked \(library), but the commit guard could not go in: \(result.message ?? "no reason given")"
      }
    }
  }

  /// Puts an app back as it was before linking. When its package.json changed since, asks first
  /// (through `driftedRestore`) instead of overwriting the change.
  /// With `library`, only that library goes back to its release and the app's other links stay.
  public func restore(_ consumer: String, library: String? = nil, force: Bool = false) async {
    if force { driftedRestore = nil }
    // Both would edit the same package.json; the second would only fail once the first is done.
    guard !isRestoring(consumer) else { return }
    await perform(.restore(consumer, library)) { api in
      do {
        let result = try await api.restore(consumer: consumer, library: library, force: force)
        if !result.ok {
          self.fail("Restored \(projectName(consumer)), but the clean install failed", result.output ?? "")
        }
      } catch let error as APIError where error.code == .manifestDrifted && !force {
        self.driftedRestore = RestoreRequest(consumer: consumer, library: library)
      }
    }
  }

  // MARK: Libraries

  /// What adding `root` as a library would do. Throws when it is not a package.
  public func inspect(_ root: String) async throws -> LibraryPreview {
    guard let api else { throw APIError.unavailable("it is not running") }
    return try await api.inspect(root: root)
  }

  /// Adds a library, or changes how a registered one is built. Throws so the form can say why.
  public func register(_ root: String, publishDir: String?, build: BuildCommand?) async throws {
    try await run(.register(root)) { _ = try await $0.register(root: root, publishDir: publishDir, build: build) }
    // New dependencies may now count as consumers.
    await discoverConsumers()
  }

  /// Stops managing a library. The daemon refuses while apps are still linked to it.
  public func unregister(_ library: String) async {
    await perform(.unregister(library)) { _ = try await $0.unregister(library: library) }
  }

  // MARK: Groups

  public func saveGroup(_ name: String, consumers: [String]) async throws {
    try await run(.saveGroup(name)) { _ = try await $0.saveGroup(name, consumers: consumers) }
  }

  public func deleteGroup(_ name: String) async {
    await perform(.deleteGroup(name)) { _ = try await $0.deleteGroup(name) }
  }

  // MARK: Project folders

  /// Replaces the folders searched for projects, then looks for projects in them.
  public func setRoots(_ next: [String]) async throws {
    try await run(.roots) { api in self.roots = try await api.setRoots(next) }
    await discoverConsumers()
  }

  // MARK: Hidden apps

  /// Stops listing an app: it stays on disk, but dryfit no longer offers it. The daemon refuses while
  /// the app is linked, since it could then only be restored from the command line.
  public func hideApp(_ root: String, navigation: AppNavigation? = nil) async {
    await perform(.hide(root)) { api in
      self.hiddenApps = try await api.hideApps([root], hidden: true)
      self.consumers.removeAll { $0.root == root }
      self.addedApps.removeAll { $0.root == root }
      if navigation?.selection == .app(root) { navigation?.selection = nil }
    }
  }

  /// Lists a hidden app again.
  public func showApp(_ root: String) async {
    await perform(.hide(root)) { api in self.hiddenApps = try await api.hideApps([root], hidden: false) }
    await discoverConsumers()
  }

  public func linkGroup(_ group: String, library: String) async {
    await perform(.linkGroup(group)) { api in
      self.report(try await api.linkGroup(group, library: library))
    }
  }

  /// Whether any restore of `consumer` runs: of one library or of all of them.
  public func isRestoring(_ consumer: String) -> Bool {
    inFlight.contains { if case .restore(consumer, _) = $0 { true } else { false } }
  }

  public func restoreGroup(_ group: String) async {
    await perform(.restoreGroup(group)) { api in
      self.report(try await api.restoreGroup(group))
    }
  }

  /// Looks for projects that use the registered libraries, for the Link menus.
  public func discoverConsumers() async {
    await perform(.discover) { api in self.consumers = try await api.discover() }
  }

  private func report(_ outcomes: [GroupMemberOutcome]) {
    let failed = outcomes.filter { $0.status == .failed }
    if !failed.isEmpty {
      actionError = failed.map { "\(projectName($0.consumer)): \($0.message ?? "failed")" }.joined(separator: "\n")
    }
  }

  /// Runs an action, reporting a failure under the controls.
  private func perform(_ action: Action, _ body: (any DaemonAPI) async throws -> Void) async {
    // Its controls only show while connected; one that slipped through as it went away does nothing.
    guard api != nil else { return }
    do {
      try await run(action, body)
    } catch let error as APIError where error.code == .buildFailed {
      // Its build:failed event has already reported it, with the output.
    } catch {
      actionError = error.localizedDescription
    }
  }

  /// Runs an action once at a time, showing it as busy, and lets its caller handle a failure.
  private func run(_ action: Action, _ body: (any DaemonAPI) async throws -> Void) async throws {
    guard let api else { throw APIError.unavailable("it is not running") }
    guard !inFlight.contains(action) else { return }
    inFlight.insert(action)
    actionError = nil
    defer { inFlight.remove(action) }
    do {
      try await body(api)
    } catch {
      await refresh()
      throw error
    }
    await refresh()
  }

  private func describe(_ job: Job) -> String {
    // Labels end in absolute paths, which may hold spaces ("restore x in /Users/me/My Apps/shop"),
    // and several apps are joined with ", ". Each path runs to the next ", " or the end.
    // Scoped library names hold a "/" too, so a path is one that starts after a space.
    var text = job.label
    if let space = text.range(of: " /") {
      let paths = text[space.upperBound...].split(separator: ", /").map { projectName("/" + $0) }
      text = text[..<space.lowerBound] + " " + paths.joined(separator: ", ")
    }
    return text.prefix(1).uppercased() + text.dropFirst()
  }
}

/// A project's folder name, which is how people refer to it.
func projectName(_ path: String) -> String {
  URL(filePath: path).lastPathComponent
}
