import Darwin
import Foundation

/// A process serving an app in development, such as `ng serve`, `vite` or `next dev`.
public nonisolated struct DevServer: Equatable, Sendable {
  public let pid: Int32
  public let started: Date

  public init(pid: Int32, started: Date) {
    self.pid = pid
    self.started = started
  }
}

/// Finds the dev servers running in an app's folder. After an install clears an app's caches, only a
/// server that was already running still holds the old build (ADR 0007), so the menu asks for a restart
/// only while one does.
public struct DevServers {
  public let running: (_ root: String) -> [DevServer]

  public init(running: @escaping (String) -> [DevServer]) {
    self.running = running
  }

  /// This Mac's processes, read with libproc.
  public static let system = DevServers(running: Processes.devServers(in:))
}

/// Reads this user's processes: a dev server is a node, bun or deno process working in the app's folder
/// whose arguments ask to serve it.
nonisolated enum Processes {
  static let runtimes: Set<String> = ["node", "bun", "deno"]
  /// Subcommands that serve an app: `ng serve`, `nx serve`, `next dev`, `npm start`, `webpack serve`.
  static let serveWords: Set<String> = ["serve", "dev", "start"]
  /// Tools that serve with no subcommand: `vite` (but not `vite build`).
  static let servers: Set<String> = ["vite", "webpack-dev-server"]
  static let notServing: Set<String> = ["build", "optimize", "preview"]

  static func devServers(in root: String) -> [DevServer] {
    let root = realPath(root) ?? root
    return allPIDs().compactMap { pid in
      guard let info = bsdInfo(pid), runtimes.contains(string(info.pbi_comm)),
        let cwd = workingDirectory(pid), isInside(cwd, root),
        let argv = arguments(pid), isDevServer(argv)
      else { return nil }
      let started = Double(info.pbi_start_tvsec) + Double(info.pbi_start_tvusec) / 1_000_000
      return DevServer(pid: pid, started: Date(timeIntervalSince1970: started))
    }
  }

  /// Whether a process's arguments, its executable first, start a dev server.
  static func isDevServer(_ argv: [String]) -> Bool {
    var previous = ""
    for (index, word) in argv.enumerated().dropFirst() {
      let name = toolName(word)
      if serveWords.contains(word) { return true }
      // `nx run shop:serve`
      if let target = word.split(separator: ":").last, word.contains(":"), serveWords.contains(String(target)) {
        return true
      }
      // `ng s`
      if word == "s", previous == "ng" { return true }
      if servers.contains(name) { return !argv[(index + 1)...].contains { notServing.contains($0) } }
      previous = name
    }
    return false
  }

  /// "vite" for `/repo/node_modules/vite/bin/vite.js`.
  static func toolName(_ word: String) -> String {
    let base = (word as NSString).lastPathComponent
    for suffix in [".js", ".mjs", ".cjs"] where base.hasSuffix(suffix) { return String(base.dropLast(suffix.count)) }
    return base
  }

  static func isInside(_ path: String, _ root: String) -> Bool {
    path == root || path.hasPrefix(root.hasSuffix("/") ? root : root + "/")
  }

  /// The arguments in a `KERN_PROCARGS2` buffer: argc, the executable's path, padding, then argv.
  static func parseArguments(_ bytes: [UInt8]) -> [String]? {
    guard bytes.count >= 4 else { return nil }
    let argc = Int(bytes.withUnsafeBytes { $0.loadUnaligned(as: Int32.self) })
    var i = 4
    while i < bytes.count, bytes[i] != 0 { i += 1 }
    while i < bytes.count, bytes[i] == 0 { i += 1 }
    var argv: [String] = []
    while argv.count < argc, i < bytes.count {
      let start = i
      while i < bytes.count, bytes[i] != 0 { i += 1 }
      argv.append(String(decoding: bytes[start..<i], as: UTF8.self))
      i += 1
    }
    return argv
  }

  // MARK: libproc

  private static func allPIDs() -> [pid_t] {
    let count = proc_listallpids(nil, 0)
    guard count > 0 else { return [] }
    // Room for processes started since counting.
    var pids = [pid_t](repeating: 0, count: Int(count) + 64)
    let found = pids.withUnsafeMutableBytes { proc_listallpids($0.baseAddress, Int32($0.count)) }
    return pids.prefix(Int(max(found, 0))).filter { $0 > 0 }
  }

  private static func bsdInfo(_ pid: pid_t) -> proc_bsdinfo? {
    var info = proc_bsdinfo()
    let size = Int32(MemoryLayout<proc_bsdinfo>.size)
    return proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, size) == size ? info : nil
  }

  private static func workingDirectory(_ pid: pid_t) -> String? {
    var info = proc_vnodepathinfo()
    let size = Int32(MemoryLayout<proc_vnodepathinfo>.size)
    guard proc_pidinfo(pid, PROC_PIDVNODEPATHINFO, 0, &info, size) == size else { return nil }
    return string(info.pvi_cdir.vip_path)
  }

  private static func arguments(_ pid: pid_t) -> [String]? {
    var mib: [Int32] = [CTL_KERN, KERN_PROCARGS2, pid]
    var size = 0
    guard sysctl(&mib, 3, nil, &size, nil, 0) == 0, size > 0 else { return nil }
    var bytes = [UInt8](repeating: 0, count: size)
    guard sysctl(&mib, 3, &bytes, &size, nil, 0) == 0 else { return nil }
    return parseArguments(Array(bytes.prefix(size)))
  }

  private static func realPath(_ path: String) -> String? {
    guard let resolved = realpath(path, nil) else { return nil }
    defer { free(resolved) }
    return String(cString: resolved)
  }

  /// A fixed-size C string, such as `pbi_comm`.
  private static func string<T>(_ tuple: T) -> String {
    withUnsafeBytes(of: tuple) { String(decoding: $0.prefix { $0 != 0 }, as: UTF8.self) }
  }
}
