import AppKit
import Foundation
import SwiftUI
import Testing

@testable import DryfitMenu

/// Draws every `LiveScenes` scene offscreen at 2x, light and dark, as `<scene>.<light|dark>.png`, for
/// `scripts/compare.sh` to put next to the mockup's own render of the same state. Unlike `LiveCapture`
/// it needs no screen and no Screen Recording permission, and two runs draw the same pixels.
/// Off unless `DRYFIT_SNAPSHOTS` names the folder to write to; `DRYFIT_SCENES` picks scenes by name.
///
///     DRYFIT_SNAPSHOTS=/tmp/app DRYFIT_SCENES=m-ok,w-lib swift test --filter Snapshots
@MainActor @Suite(.serialized) struct Snapshots {
  nonisolated static let folder = ProcessInfo.processInfo.environment["DRYFIT_SNAPSHOTS"]
  nonisolated static let only = ProcessInfo.processInfo.environment["DRYFIT_SCENES"]?.split(separator: ",").map(String.init)

  @Test(.enabled(if: ProcessInfo.processInfo.environment["DRYFIT_SNAPSHOTS"] != nil)) func scenes() throws {
    _ = NSApplication.shared
    let folder = URL(filePath: Self.folder!)
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    var unsettled: [String] = []
    for scene in LiveScenes.all where Self.only == nil || Self.only!.contains(scene.name) {
      for dark in [false, true] {
        let name = "\(scene.name).\(dark ? "dark" : "light")"
        if !render(scene, dark: dark, to: folder.appending(path: "\(name).png")) { unsettled.append(name) }
      }
    }
    #expect(unsettled.isEmpty, "never drew the same twice: \(unsettled.joined(separator: ", "))")
  }

  /// Draws until two draws in a row match, letting state that lands a moment later settle; false when
  /// they never do (something moves), after writing the last one anyway.
  private func render(_ scene: LiveScene, dark: Bool, to url: URL) -> Bool {
    let appearance = NSAppearance(named: dark ? .darkAqua : .aqua)!
    let root = scene.view()
      .environment(\.timeZone, TimeZone(identifier: "UTC")!)
      .environment(\.locale, Locale(identifier: "en_US"))
      .environment(\.drawStill, true)
    let host = NSHostingView(rootView: root)
    host.appearance = appearance
    var size = scene.size
    let window = NSWindow(contentRect: NSRect(origin: .zero, size: size), styleMask: [.borderless], backing: .buffered, defer: false)
    window.appearance = appearance
    window.isReleasedWhenClosed = false
    window.contentView = host
    if scene.fit {
      host.frame = NSRect(origin: .zero, size: size)
      host.layoutSubtreeIfNeeded()
      size.height = host.fittingSize.height
    }
    window.setContentSize(size)
    host.frame = NSRect(origin: .zero, size: size)

    var previous: Data?
    for _ in 0..<10 {
      window.makeFirstResponder(nil)
      host.layoutSubtreeIfNeeded()
      atTwoX(host.layer)
      guard let png = bitmap(of: host, size: size) else { return false }
      if png == previous {
        try? png.write(to: url)
        return true
      }
      previous = png
      RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.05))
    }
    try? previous?.write(to: url)
    return false
  }

  /// At 2x whatever the display, in sRGB, so a 1x Mac (mac-mini) draws what a Retina one does.
  private func bitmap(of host: NSView, size: CGSize) -> Data? {
    guard
      let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: Int(size.width * 2), pixelsHigh: Int(size.height * 2), bitsPerSample: 8,
        samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .calibratedRGB, bytesPerRow: 0, bitsPerPixel: 0
      )?.retagging(with: .sRGB)
    else { return nil }
    rep.size = size
    host.cacheDisplay(in: host.bounds, to: rep)
    return rep.representation(using: .png, properties: [:])
  }

  /// Layers draw at the window's backing scale, 1 on a 1x display: redraw each at 2 (images keep theirs).
  private func atTwoX(_ layer: CALayer?) {
    guard let layer else { return }
    let isImage = layer.contents.map { CFGetTypeID($0 as CFTypeRef) == CGImage.typeID } ?? false
    if layer.contentsScale != 2, !isImage {
      layer.contentsScale = 2
      layer.setNeedsDisplay()
    }
    layer.sublayers?.forEach(atTwoX)
  }
}
