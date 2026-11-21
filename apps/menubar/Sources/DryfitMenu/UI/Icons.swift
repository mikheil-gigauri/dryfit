import SwiftUI

/// An SVG path (`M L H V Z A`, absolute and relative) as a SwiftUI path, in the icon's own units. The
/// mockup's icons are drawn from these paths, so the app draws the same shapes at the same weights.
nonisolated struct SVGPath: Sendable {
  let path: Path

  init(_ d: String) {
    var path = Path()
    var scanner = Scanner(d)
    var current = CGPoint.zero
    var start = CGPoint.zero
    var command: Character = "M"
    while let next = scanner.nextCommand() {
      command = next
      let relative = command.isLowercase
      func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
        relative ? CGPoint(x: current.x + x, y: current.y + y) : CGPoint(x: x, y: y)
      }
      switch command.uppercased() {
      case "M":
        var first = true
        while let x = scanner.number(), let y = scanner.number() {
          current = point(x, y)
          if first { path.move(to: current); start = current; first = false } else { path.addLine(to: current) }
        }
      case "L":
        while let x = scanner.number(), let y = scanner.number() {
          current = point(x, y)
          path.addLine(to: current)
        }
      case "H":
        while let x = scanner.number() {
          current = CGPoint(x: relative ? current.x + x : x, y: current.y)
          path.addLine(to: current)
        }
      case "V":
        while let y = scanner.number() {
          current = CGPoint(x: current.x, y: relative ? current.y + y : y)
          path.addLine(to: current)
        }
      case "A":
        while let rx = scanner.number(), let _ = scanner.number(), let _ = scanner.number(),
          let large = scanner.flag(), let sweep = scanner.flag(), let x = scanner.number(), let y = scanner.number()
        {
          let end = point(x, y)
          Self.arc(&path, from: current, to: end, radius: rx, large: large, sweep: sweep)
          current = end
        }
      case "Z":
        path.closeSubpath()
        current = start
      default: break
      }
    }
    self.path = path
  }

  /// A circular arc as short lines: icons are small, and the corners they round are a point or two.
  private static func arc(_ path: inout Path, from p1: CGPoint, to p2: CGPoint, radius r: CGFloat, large: Bool, sweep: Bool) {
    let x1 = (p1.x - p2.x) / 2, y1 = (p1.y - p2.y) / 2
    let d2 = x1 * x1 + y1 * y1
    guard d2 > 0, r > 0 else { return path.addLine(to: p2) }
    let radius = max(r, d2.squareRoot())
    let k = ((radius * radius - d2) / d2).squareRoot() * (large != sweep ? 1 : -1)
    let cx = k * y1 + (p1.x + p2.x) / 2
    let cy = -k * x1 + (p1.y + p2.y) / 2
    let a1 = atan2((y1 + (p1.y + p2.y) / 2 - cy), (x1 + (p1.x + p2.x) / 2 - cx))
    let a2 = atan2((-y1 + (p1.y + p2.y) / 2 - cy), (-x1 + (p1.x + p2.x) / 2 - cx))
    var delta = a2 - a1
    if sweep && delta < 0 { delta += 2 * .pi }
    if !sweep && delta > 0 { delta -= 2 * .pi }
    let steps = 12
    for step in 1...steps {
      let angle = a1 + delta * CGFloat(step) / CGFloat(steps)
      path.addLine(to: CGPoint(x: cx + radius * cos(angle), y: cy + radius * sin(angle)))
    }
  }

  private struct Scanner {
    private let chars: [Character]
    private var index = 0

    init(_ text: String) { chars = Array(text) }

    mutating func nextCommand() -> Character? {
      skipSeparators()
      guard index < chars.count, chars[index].isLetter else { return nil }
      defer { index += 1 }
      return chars[index]
    }

    mutating func number() -> CGFloat? {
      skipSeparators()
      guard index < chars.count else { return nil }
      var text = ""
      if chars[index] == "-" || chars[index] == "+" { text.append(chars[index]); index += 1 }
      var dot = false
      while index < chars.count {
        let c = chars[index]
        if c.isNumber { text.append(c) } else if c == ".", !dot { dot = true; text.append(c) } else { break }
        index += 1
      }
      return Double(text).map { CGFloat($0) }
    }

    /// An arc flag is one digit and may touch the number after it ("0 014.5").
    mutating func flag() -> Bool? {
      skipSeparators()
      guard index < chars.count, chars[index] == "0" || chars[index] == "1" else { return nil }
      defer { index += 1 }
      return chars[index] == "1"
    }

    private mutating func skipSeparators() {
      while index < chars.count, chars[index] == " " || chars[index] == "," { index += 1 }
    }
  }
}

/// A shape drawn from SVG paths in a square of `box` units, scaled to the frame it is given.
nonisolated struct SVGShape: Shape {
  let paths: [SVGPath]
  let box: CGFloat

  func path(in rect: CGRect) -> Path {
    let scale = min(rect.width, rect.height) / box
    var result = Path()
    for svg in paths { result.addPath(svg.path.applying(CGAffineTransform(scaleX: scale, y: scale))) }
    return result
  }
}

/// The mockup's line icons, at the size and stroke weight it draws them.
struct Icon: View {
  enum Kind {
    case library, app, group, search, gear, folder, chevron
  }

  let kind: Kind
  var size: CGFloat = 15
  var color: Color = Theme.muted

  var body: some View {
    ZStack {
      switch kind {
      case .library:
        stroke(["M12 2.5l8.5 4.5v10L12 21.5 3.5 17V7z", "M3.5 7L12 11.5 20.5 7M12 11.5v10"], 1.7, cap: .round)
      case .app:
        Rect(x: 3, y: 4.5, w: 18, h: 15, r: 3).stroke(color, style: StrokeStyle(lineWidth: 1.7 * size / 24, lineJoin: .round))
        stroke(["M3 9h18"], 1.7, cap: .butt)
      case .group:
        stroke(["M12 3l9 4.5-9 4.5-9-4.5z", "M3 12l9 4.5 9-4.5M3 16.5l9 4.5 9-4.5"], 1.7, cap: .butt)
      case .search:
        Circle().stroke(color, style: StrokeStyle(lineWidth: 2.2 * size / 24))
          .frame(width: 13 * size / 24, height: 13 * size / 24).position(x: 10.5 * size / 24, y: 10.5 * size / 24)
        stroke(["M16 16l5 5"], 2.2, cap: .round)
      case .gear:
        stroke(
          ["M10.08 4.85 L10.47 2.32 L13.53 2.32 L13.92 4.85 L15.70 5.59 L17.76 4.07 L19.93 6.24 L18.41 8.30 L19.15 10.08 L21.68 10.47 L21.68 13.53 L19.15 13.92 L18.41 15.70 L19.93 17.76 L17.76 19.93 L15.70 18.41 L13.92 19.15 L13.53 21.68 L10.47 21.68 L10.08 19.15 L8.30 18.41 L6.24 19.93 L4.07 17.76 L5.59 15.70 L4.85 13.92 L2.32 13.53 L2.32 10.47 L4.85 10.08 L5.59 8.30 L4.07 6.24 L6.24 4.07 L8.30 5.59Z"], 1.7, cap: .round)
        Circle().stroke(color, style: StrokeStyle(lineWidth: 1.7 * size / 24))
          .frame(width: 6 * size / 24, height: 6 * size / 24).position(x: 12 * size / 24, y: 12 * size / 24)
      case .chevron:
        stroke(["M9 6l6 6-6 6"], 1.7, cap: .round)
      case .folder:
        stroke(
          ["M3 6.5A1.5 1.5 0 014.5 5H9l2 2.5h8.5A1.5 1.5 0 0121 9v8.5a1.5 1.5 0 01-1.5 1.5h-15A1.5 1.5 0 013 17.5z"], 1.8, cap: .butt)
      }
    }
    .frame(width: size, height: size)
    .accessibilityHidden(true)
  }

  private func stroke(_ d: [String], _ width: CGFloat, cap: CGLineCap) -> some View {
    SVGShape(paths: d.map(SVGPath.init), box: 24)
      .stroke(color, style: StrokeStyle(lineWidth: width * size / 24, lineCap: cap, lineJoin: .round))
  }

  private nonisolated struct Rect: Shape {
    let x: CGFloat, y: CGFloat, w: CGFloat, h: CGFloat, r: CGFloat
    func path(in rect: CGRect) -> Path {
      let s = rect.width / 24
      return Path(roundedRect: CGRect(x: x * s, y: y * s, width: w * s, height: h * s), cornerRadius: r * s)
    }
  }
}

/// How something is doing, as the mockup's filled circle with a mark in it (or a plain clock for waiting).
struct StatusGlyph: View {
  enum Kind { case ok, failed, update, waiting, warning }

  let kind: Kind
  var size: CGFloat = 16

  var body: some View {
    ZStack {
      switch kind {
      case .ok:
        Circle().fill(Theme.ok)
        mark("M4 7.2l2 2 4-4.4", 1.6)
      case .failed:
        Circle().fill(Theme.bad)
        mark("M4.5 4.5l5 5M9.5 4.5l-5 5", 1.6)
      case .update:
        Circle().fill(Theme.warn)
        mark("M7 10.5V4M4.3 6.6L7 4l2.7 2.6", 1.5)
      case .waiting:
        Circle().inset(by: 0.7 * size / 14).stroke(Theme.faint, lineWidth: 1.4 * size / 14)
        SVGShape(paths: [SVGPath("M7 3.8V7l2.2 1.4")], box: 14)
          .stroke(Theme.faint, style: StrokeStyle(lineWidth: 1.4 * size / 14, lineCap: .round, lineJoin: .round))
      case .warning:
        SVGShape(paths: [SVGPath("M7 1.2L13.2 12H.8z")], box: 14)
          .fill(Theme.warn)
        SVGShape(paths: [SVGPath("M7 1.2L13.2 12H.8z")], box: 14)
          .stroke(Theme.warn, style: StrokeStyle(lineWidth: 1 * size / 14, lineJoin: .round))
        SVGShape(paths: [SVGPath("M7 5.2v3.2M7 10v.1")], box: 14)
          .stroke(.white, style: StrokeStyle(lineWidth: 1.4 * size / 14, lineCap: .round))
      }
    }
    .frame(width: size, height: size)
    .accessibilityLabel(label)
  }

  private func mark(_ d: String, _ width: CGFloat) -> some View {
    SVGShape(paths: [SVGPath(d)], box: 14)
      .stroke(.white, style: StrokeStyle(lineWidth: width * size / 14, lineCap: .round, lineJoin: .round))
  }

  private var label: String {
    switch kind {
    case .ok: "Installed"
    case .failed: "Failed"
    case .update: "Update available"
    case .waiting: "Waiting"
    case .warning: "Needs attention"
    }
  }
}
