import AppKit
import SwiftUI
import Testing

@testable import DryfitMenu

/// The design foundation: tokens and the parts every screen is built from.
@MainActor @Suite(.serialized) struct FoundationTests {
  /// The size, in points, of what a view actually draws: its ink, not its frame. An icon that is
  /// blank, clipped or tiny shows here, which a frame never would.
  private func ink(of view: some View, scale: CGFloat = 2, minAlpha: UInt8 = 40) -> CGSize? {
    let renderer = ImageRenderer(content: view.padding(8))
    renderer.scale = scale
    guard let image = renderer.cgImage else { return nil }
    let width = image.width, height = image.height
    var pixels = [UInt8](repeating: 0, count: width * height * 4)
    guard
      let context = CGContext(
        data: &pixels, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
        space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
    else { return nil }
    context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
    var minX = width, maxX = -1, minY = height, maxY = -1
    for y in 0..<height {
      for x in 0..<width where pixels[(y * width + x) * 4 + 3] > minAlpha {
        minX = min(minX, x); maxX = max(maxX, x); minY = min(minY, y); maxY = max(maxY, y)
      }
    }
    guard maxX >= minX else { return nil }
    return CGSize(width: CGFloat(maxX - minX + 1) / scale, height: CGFloat(maxY - minY + 1) / scale)
  }

  @Test(arguments: Condition.allCases) func everyStatusIconIsDrawnAtItsSize(condition: Condition) throws {
    let drawn = try #require(ink(of: StatusIcon(condition: condition)), "\(condition) drew nothing")
    // At 16 pt the glyph fills most of its square: never a speck, never cut off at the frame's edge.
    #expect(drawn.width >= 13 && drawn.height >= 12, "\(condition) is \(drawn) pt")
    #expect(drawn.width <= 18 && drawn.height <= 18, "\(condition) is \(drawn) pt")
  }

  @Test func statusIconsAreTheSameSizeSoRowsLineUp() throws {
    let sizes = try Condition.allCases.map { try #require(ink(of: StatusIcon(condition: $0))) }
    let widths = sizes.map(\.width)
    // The triangle is wider than the clock by design; none is more than a few points off.
    #expect((widths.max() ?? 0) - (widths.min() ?? 0) <= 3, "widths \(widths)")
  }

  @Test func everyStatusSaysItInWordsToo() {
    #expect(Set(Condition.allCases.map(\.label)).count == Condition.allCases.count)
    #expect(Set(Condition.allCases.map(\.symbol)).count == Condition.allCases.count)
  }

  @Test func chipsAreDrawnAndNotTiny() throws {
    for kind in [Chip.Kind.neutral, .dev, .release, .ok, .warning, .failed] {
      let drawn = try #require(ink(of: Chip(text: "DEV", kind: kind), minAlpha: 8), "\(kind) drew nothing")
      #expect(drawn.height >= 16, "\(kind) chip is \(drawn.height) pt tall")
    }
  }

  @Test(.enabled(if: Snapshots.comparable, Comment(rawValue: Snapshots.skipped))) func foundationGallery() {
    assertSnapshot(of: Gallery(), named: "foundation", size: CGSize(width: 560, height: 640))
  }
}

/// Every part of the foundation once, as it is meant to look.
private struct Gallery: View {
  var body: some View {
    PinnedPage {
      PinnedHeader(symbol: "shippingbox", tint: .teal, title: "@acme/ui", subtitle: "1.4.1 · dev build 14:32") {
        Chip(text: "DEV BUILD", kind: .dev)
      } actions: {
        Button("Sync now") {}.buttonStyle(.primaryPill)
      }
    } content: {
      VStack(alignment: .leading, spacing: 0) {
        SectionHeader("Status", count: 5)
        HStack(spacing: 14) {
          ForEach(Condition.allCases, id: \.self) { condition in
            HStack(spacing: 4) {
              StatusIcon(condition: condition)
              Text(condition.label).font(DS.caption)
            }
          }
        }
      }
      VStack(alignment: .leading, spacing: 0) {
        SectionHeader(title: "Chips", count: nil) { Text("Look again").foregroundStyle(Color.accentColor) }
        HStack(spacing: 6) {
          Chip(text: "npm")
          Chip(text: "DEV", kind: .dev)
          Chip(text: "RELEASE", kind: .release)
          Chip(text: "Installed", kind: .ok, symbol: "checkmark")
          Chip(text: "Versions differ", kind: .warning)
          Chip(text: "Install failed", kind: .failed)
        }
      }
      VStack(alignment: .leading, spacing: 0) {
        SectionHeader("Linked apps", count: 2)
        HairlineGroup {
          GroupRow {
            StatusIcon(condition: .failed)
            TwoLine(title: "admin", caption: "pnpm · ~/code/admin")
            Spacer(minLength: 8)
            Chip(text: "Install failed", kind: .failed)
            Button("Restore") {}.buttonStyle(.pill)
          }
          GroupRow {
            StatusIcon(condition: .ok)
            TwoLine(title: "shop", caption: "npm · ~/code/shop")
            Spacer(minLength: 8)
            BuildChip(dev: true)
            Button("Restore") {}.buttonStyle(.pill)
          }
        }
      }
    }
  }
}
