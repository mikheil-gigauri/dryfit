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

}
