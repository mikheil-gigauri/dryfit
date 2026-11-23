import Foundation
import Testing

@testable import DryfitMenu

@MainActor @Suite struct DevServersTests {
  @Test(arguments: [
    ["/usr/local/bin/node", "/repo/node_modules/@angular/cli/bin/ng.js", "serve"],
    ["node", "/repo/node_modules/.bin/ng", "s", "--port", "4300"],
    ["node", "/repo/node_modules/nx/bin/nx.js", "run", "shell:serve"],
    ["node", "/repo/node_modules/vite/bin/vite.js"],
    ["node", "/repo/node_modules/vite/bin/vite.js", "--host"],
    ["node", "/repo/node_modules/next/dist/bin/next", "dev"],
    ["node", "/usr/local/lib/node_modules/npm/bin/npm-cli.js", "start"],
    ["bun", "run", "dev"],
  ])
  func recognisesDevServers(_ argv: [String]) {
    #expect(Processes.isDevServer(argv))
  }

  @Test(arguments: [
    ["node", "/repo/node_modules/vite/bin/vite.js", "build"],
    ["node", "/repo/node_modules/vitest/vitest.mjs"],
    ["node", "/repo/node_modules/@angular/cli/bin/ng.js", "build", "--watch"],
    // Nx's daemon and the TypeScript server an editor runs in the folder.
    ["node", "/repo/node_modules/nx/src/daemon/server/start.js"],
    ["node", "/Applications/WebStorm.app/plugins/typescript/tsserver.js", "--serverMode", "partialSemantic"],
    ["node"],
  ])
  func ignoresOtherNodeProcesses(_ argv: [String]) {
    #expect(!Processes.isDevServer(argv))
  }

  @Test func readsArgumentsFromAProcargsBuffer() {
    var bytes = withUnsafeBytes(of: Int32(3).littleEndian) { Array($0) }
    bytes += Array("/usr/local/bin/node".utf8) + [0, 0, 0]
    bytes += Array("node".utf8) + [0] + Array("ng.js".utf8) + [0] + Array("serve".utf8) + [0]
    bytes += Array("PATH=/usr/bin".utf8) + [0]
    #expect(Processes.parseArguments(bytes) == ["node", "ng.js", "serve"])
  }

  @Test func countsFoldersInsideTheAppButNotItsNeighbours() {
    #expect(Processes.isInside("/repos/shop", "/repos/shop"))
    #expect(Processes.isInside("/repos/shop/apps/web", "/repos/shop"))
    #expect(!Processes.isInside("/repos/shop-admin", "/repos/shop"))
  }

  /// A real node process serving in a temporary folder, found through libproc.
  @Test func findsARunningNodeServerInTheAppsFolder() async throws {
    guard let node = ["/opt/homebrew/bin/node", "/usr/local/bin/node"]
      .first(where: FileManager.default.isExecutableFile(atPath:))
      ?? Self.which("node")
    else { return }
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent("dryfit-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: folder) }

    let before = Date.now.addingTimeInterval(-1)
    let process = Process()
    process.executableURL = URL(fileURLWithPath: node)
    process.arguments = ["-e", "setInterval(() => {}, 1000)", "serve"]
    process.currentDirectoryURL = folder
    try process.run()
    defer { process.terminate() }
    try await Task.sleep(for: .milliseconds(300))

    let found = DevServers.system.running(folder.path)
    #expect(found.map(\.pid) == [process.processIdentifier])
    #expect(found.first.map { $0.started > before } == true)
    #expect(DevServers.system.running(folder.deletingLastPathComponent().appendingPathComponent("elsewhere").path).isEmpty)
  }

  private static func which(_ tool: String) -> String? {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/bin/zsh")
    process.arguments = ["-lc", "command -v \(tool)"]
    let pipe = Pipe()
    process.standardOutput = pipe
    guard (try? process.run()) != nil else { return nil }
    process.waitUntilExit()
    let path = String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
      .trimmingCharacters(in: .whitespacesAndNewlines)
    return path.isEmpty ? nil : path
  }
}
