// Puts a mock render next to the app's render of the same state with their difference: mock | app | diff.
//   compare <mock.png> <app.png> <out.png>
// Prints the share of pixels that differ over the app's area, and both sizes when they don't match: the
// mock render is white around its surface, so its size is the box of what isn't white. The diff paints
// matching pixels as a faded copy of the mock and differing ones red, darker the more they differ.
import AppKit

func load(_ path: String) -> NSBitmapImageRep {
  guard let data = FileManager.default.contents(atPath: path), let rep = NSBitmapImageRep(data: data) else {
    FileHandle.standardError.write(Data("compare: can't read \(path)\n".utf8))
    exit(2)
  }
  // 8-bit RGBA on white, so a transparent corner in the app's render reads as the mock's white page.
  let out = NSBitmapImageRep(
    bitmapDataPlanes: nil, pixelsWide: rep.pixelsWide, pixelsHigh: rep.pixelsHigh, bitsPerSample: 8,
    samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: rep.pixelsWide * 4,
    bitsPerPixel: 32)!
  NSGraphicsContext.saveGraphicsState()
  NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: out)
  NSColor.white.setFill()
  NSRect(x: 0, y: 0, width: rep.pixelsWide, height: rep.pixelsHigh).fill()
  rep.draw(in: NSRect(x: 0, y: 0, width: rep.pixelsWide, height: rep.pixelsHigh))
  NSGraphicsContext.restoreGraphicsState()
  return out
}

/// The size in points (2x pixels) of the box around everything that isn't white.
func contentSize(_ rep: NSBitmapImageRep) -> (w: Int, h: Int) {
  let p = rep.bitmapData!
  var maxX = 0, maxY = 0
  for y in 0..<rep.pixelsHigh {
    for x in 0..<rep.pixelsWide {
      let i = y * rep.bytesPerRow + x * 4
      if p[i] < 254 || p[i + 1] < 254 || p[i + 2] < 254 {
        maxX = max(maxX, x + 1)
        maxY = max(maxY, y + 1)
      }
    }
  }
  return ((maxX + 1) / 2, (maxY + 1) / 2)
}

let args = CommandLine.arguments
guard args.count == 4 else {
  print("usage: compare <mock.png> <app.png> <out.png>")
  exit(2)
}
let a = load(args[1]), b = load(args[2])
let w = min(a.pixelsWide, b.pixelsWide), h = min(a.pixelsHigh, b.pixelsHigh), gap = 8
let out = NSBitmapImageRep(
  bitmapDataPlanes: nil, pixelsWide: w * 3 + gap * 2, pixelsHigh: h, bitsPerSample: 8, samplesPerPixel: 4,
  hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: (w * 3 + gap * 2) * 4, bitsPerPixel: 32)!
let pa = a.bitmapData!, pb = b.bitmapData!, po = out.bitmapData!
memset(po, 0x80, out.bytesPerRow * h)
var differing = 0
for y in 0..<h {
  for x in 0..<w {
    let ia = y * a.bytesPerRow + x * 4, ib = y * b.bytesPerRow + x * 4
    var d = 0
    for c in 0..<3 { d = max(d, abs(Int(pa[ia + c]) - Int(pb[ib + c]))) }
    for (col, src, i) in [(0, pa, ia), (1, pb, ib)] {
      let o = y * out.bytesPerRow + (x + col * (w + gap)) * 4
      for c in 0..<4 { po[o + c] = src[i + c] }
    }
    let o = y * out.bytesPerRow + (x + 2 * (w + gap)) * 4
    if d > 24 {
      differing += 1
      po[o] = 255
      po[o + 1] = UInt8(max(0, 200 - d))
      po[o + 2] = UInt8(max(0, 200 - d))
    } else {
      let g = UInt8(215 + Int(pa[ia]) * 40 / 255)
      po[o] = g
      po[o + 1] = g
      po[o + 2] = g
    }
    po[o + 3] = 255
  }
}
try! out.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: args[3]))
let mock = contentSize(a), app = (w: b.pixelsWide / 2, h: b.pixelsHigh / 2)
var line = String(format: "%6.2f%% differ", Double(differing) * 100 / Double(w * h))
if abs(mock.w - app.w) > 2 || abs(mock.h - app.h) > 2 { line += "   size: mock \(mock.w)×\(mock.h), app \(app.w)×\(app.h) pt" }
print(line)
