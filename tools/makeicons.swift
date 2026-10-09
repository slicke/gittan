// makeicons.swift - builds Gittan's application icons from the artwork.
//
//   swift tools/makeicons.swift <artwork.png> <outdir> <Gittan.ico>
//
// The artwork is a rounded square painted on a white background with a soft
// gray halo around it. The halo cannot be told from the icon's light gray
// right side by color alone, so the icon's outline is measured where it is
// unambiguous: the left, top and right edges and the bottom-left corner
// profile (dark blue against the halo). The profile is mirrored to the other
// three corners, the outline is shrunk by one pixel and softened by a 3x3
// average, and everything outside it becomes transparent.
//
// Writes:
//   <outdir>/gittan.png          1024x1024 master, the icon filling the canvas
//   <outdir>/png/gittan-<n>.png  16..512 for Linux desktop files
//   <outdir>/Gittan.icns         macOS, icon inset to Apple's 824/1024 grid
//   <Gittan.ico>                 Windows/Linux LCL icon, 16..256
//
// macOS only (CoreGraphics, ImageIO, iconutil).

import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

let args = CommandLine.arguments
guard args.count == 4 else {
  FileHandle.standardError.write("usage: makeicons.swift <artwork.png> <outdir> <Gittan.ico>\n".data(using: .utf8)!)
  exit(2)
}
let srcPath = args[1], outDir = args[2], icoPath = args[3]

func fail(_ msg: String) -> Never {
  FileHandle.standardError.write("makeicons: \(msg)\n".data(using: .utf8)!)
  exit(1)
}

// ---------------------------------------------------------------------------
// Pixel buffers
// ---------------------------------------------------------------------------

struct Bitmap {
  let width: Int, height: Int
  let ctx: CGContext
  let data: UnsafeMutablePointer<UInt8>  // RGBA, premultiplied, top row first

  init(width: Int, height: Int) {
    self.width = width; self.height = height
    let cs = CGColorSpaceCreateDeviceRGB()
    guard let c = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
                            bytesPerRow: width * 4, space: cs,
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
      fail("cannot create \(width)x\(height) bitmap")
    }
    c.interpolationQuality = .high
    ctx = c
    data = c.data!.bindMemory(to: UInt8.self, capacity: width * height * 4)
  }

  // A bitmap context stores the top row first; y counts from the top.
  @inline(__always) func offset(_ x: Int, _ y: Int) -> Int { (y * width + x) * 4 }

  func rgba(_ x: Int, _ y: Int) -> (Int, Int, Int, Int) {
    let i = offset(x, y)
    return (Int(data[i]), Int(data[i + 1]), Int(data[i + 2]), Int(data[i + 3]))
  }

  var image: CGImage { ctx.makeImage()! }

  func draw(_ img: CGImage, in rect: CGRect) {
    // Flip to top-down coordinates for the caller.
    ctx.draw(img, in: CGRect(x: rect.minX, y: CGFloat(height) - rect.maxY, width: rect.width, height: rect.height))
  }

  func pngData() -> Data {
    let out = NSMutableData()
    guard let dest = CGImageDestinationCreateWithData(out, UTType.png.identifier as CFString, 1, nil) else {
      fail("cannot create PNG destination")
    }
    CGImageDestinationAddImage(dest, image, nil)
    guard CGImageDestinationFinalize(dest) else { fail("cannot encode PNG") }
    return out as Data
  }
}

func load(_ path: String) -> Bitmap {
  guard let src = CGImageSourceCreateWithURL(URL(fileURLWithPath: path) as CFURL, nil),
        let img = CGImageSourceCreateImageAtIndex(src, 0, nil) else { fail("cannot read \(path)") }
  let bm = Bitmap(width: img.width, height: img.height)
  bm.draw(img, in: CGRect(x: 0, y: 0, width: img.width, height: img.height))
  return bm
}

func resized(_ img: CGImage, to size: Int, inset: CGFloat = 0) -> Bitmap {
  let bm = Bitmap(width: size, height: size)
  let s = CGFloat(size) - 2 * inset
  bm.draw(img, in: CGRect(x: inset, y: inset, width: s, height: s))
  return bm
}

// ---------------------------------------------------------------------------
// Outline
// ---------------------------------------------------------------------------

let art = load(srcPath)
let W = art.width, H = art.height

// A pixel belongs to the icon where it is dark or colored; the halo is a light
// neutral gray and the background white. Transparent pixels never count.
func isIcon(_ x: Int, _ y: Int) -> Bool {
  let (r, g, b, a) = art.rgba(x, y)
  if a < 128 { return false }
  let mx = max(r, g, b), mn = min(r, g, b)
  return mx < 150 || mx - mn > 25
}

func firstIcon(row y: Int, from x0: Int, to x1: Int) -> Int? {
  let step = x1 >= x0 ? 1 : -1
  var x = x0
  while x != x1 { if isIcon(x, y) { return x }; x += step }
  return nil
}
func firstIcon(col x: Int, from y0: Int, to y1: Int) -> Int? {
  let step = y1 >= y0 ? 1 : -1
  var y = y0
  while y != y1 { if isIcon(x, y) { return y }; y += step }
  return nil
}

// Edges: the left side at mid height, top and bottom on the blue left half,
// the right side where the frame is dark red (lower third).
let probeX = W * 39 / 100, probeY = H * 71 / 100
guard let left = firstIcon(row: H / 2, from: 0, to: W / 2),
      let top = firstIcon(col: probeX, from: 0, to: H / 2),
      let bottom = firstIcon(col: probeX, from: H - 1, to: H / 2),
      let right = firstIcon(row: probeY, from: W - 1, to: W / 2)
else { fail("cannot find the icon's edges") }

// Corner profile, measured at the bottom-left corner where the frame is dark
// blue: leftmost icon pixel per row above the bottom edge, until it reaches
// the left edge. Forced monotonic so noise cannot dent the mask.
var profile: [Int] = []
var run = W
for y in stride(from: bottom, through: H / 2, by: -1) {
  let x = firstIcon(row: y, from: 0, to: W / 2) ?? W
  run = min(run, x)
  if run <= left { break }
  profile.append(run)
}
let radius = profile.count

// Sanity check against the bottom-right corner, which is dark red.
var mismatch = 0
for (i, xl) in profile.enumerated() {
  let xr = firstIcon(row: bottom - i, from: W - 1, to: W / 2) ?? -1
  mismatch = max(mismatch, abs((right - xr) - (xl - left)))
}
print("outline: x \(left)...\(right), y \(top)...\(bottom), corner \(radius)px, left/right corner mismatch \(mismatch)px")
if mismatch > 6 { fail("the top corners differ too much; the artwork is not symmetric") }

let cw = right - left + 1, ch = bottom - top + 1

// Inset of the outline from the box edge for each row, after a 1px erosion.
func inset(row y: Int) -> Int? {
  let dy = min(y, ch - 1 - y)
  if dy < 1 { return nil }
  let d = dy - 1
  return (d < radius ? profile[d] - left : 0) + 1
}

var hard = [Float](repeating: 0, count: cw * ch)
for y in 0..<ch {
  guard let ins = inset(row: y) else { continue }
  if cw - 2 * ins <= 0 { continue }
  for x in ins..<(cw - ins) { hard[y * cw + x] = 1 }
}
// 3x3 average softens the stepped outline into a one pixel ramp.
var alpha = [Float](repeating: 0, count: cw * ch)
for y in 0..<ch {
  for x in 0..<cw {
    var sum: Float = 0
    for dy in -1...1 { for dx in -1...1 {
      let xx = x + dx, yy = y + dy
      if xx >= 0, xx < cw, yy >= 0, yy < ch { sum += hard[yy * cw + xx] }
    } }
    alpha[y * cw + x] = sum / 9
  }
}

// ---------------------------------------------------------------------------
// Master: the cut-out centered on a square canvas
// ---------------------------------------------------------------------------

let side = max(cw, ch)
let cut = Bitmap(width: side, height: side)
let ox = (side - cw) / 2, oy = (side - ch) / 2
for y in 0..<ch {
  for x in 0..<cw {
    let a = alpha[y * cw + x]
    if a <= 0 { continue }
    let (r, g, b, _) = art.rgba(left + x, top + y)
    let i = cut.offset(ox + x, oy + y)
    cut.data[i] = UInt8(Float(r) * a + 0.5)
    cut.data[i + 1] = UInt8(Float(g) * a + 0.5)
    cut.data[i + 2] = UInt8(Float(b) * a + 0.5)
    cut.data[i + 3] = UInt8(a * 255 + 0.5)
  }
}
let cutImage = cut.image

let fm = FileManager.default
try? fm.createDirectory(atPath: outDir + "/png", withIntermediateDirectories: true)

func write(_ data: Data, _ path: String) {
  do { try data.write(to: URL(fileURLWithPath: path)) } catch { fail("cannot write \(path): \(error)") }
}

let master = resized(cutImage, to: 1024)
write(master.pngData(), outDir + "/gittan.png")
let masterImage = master.image

for n in [16, 22, 24, 32, 48, 64, 128, 256, 512] {
  write(resized(masterImage, to: n).pngData(), outDir + "/png/gittan-\(n).png")
}

// ---------------------------------------------------------------------------
// Windows .ico: BMP entries up to 128, PNG at 256
// ---------------------------------------------------------------------------

func bmpEntry(_ bm: Bitmap) -> Data {
  let w = bm.width, h = bm.height
  var d = Data()
  func u32(_ v: Int) { var x = UInt32(v).littleEndian; d.append(Data(bytes: &x, count: 4)) }
  func u16(_ v: Int) { var x = UInt16(v).littleEndian; d.append(Data(bytes: &x, count: 2)) }
  let maskRow = ((w + 31) / 32) * 4
  u32(40); u32(w); u32(h * 2); u16(1); u16(32); u32(0)
  u32(w * h * 4 + maskRow * h); u32(0); u32(0); u32(0); u32(0)
  var xor = [UInt8](repeating: 0, count: w * h * 4)
  var and = [UInt8](repeating: 0, count: maskRow * h)
  for y in 0..<h {  // bottom-up
    let sy = h - 1 - y
    for x in 0..<w {
      let (r, g, b, a) = bm.rgba(x, sy)
      let o = (y * w + x) * 4
      if a == 0 {
        and[y * maskRow + x / 8] |= 0x80 >> (x % 8)
      } else {
        // CoreGraphics keeps colors premultiplied; the DIB wants straight alpha.
        xor[o] = UInt8(min(255, (b * 255 + a / 2) / a))
        xor[o + 1] = UInt8(min(255, (g * 255 + a / 2) / a))
        xor[o + 2] = UInt8(min(255, (r * 255 + a / 2) / a))
        xor[o + 3] = UInt8(a)
      }
    }
  }
  d.append(contentsOf: xor); d.append(contentsOf: and)
  return d
}

let icoSizes = [16, 24, 32, 48, 64, 128, 256]
var entries: [(size: Int, data: Data)] = icoSizes.map { n in
  let bm = resized(masterImage, to: n)
  return (n, n >= 256 ? bm.pngData() : bmpEntry(bm))
}
var ico = Data()
func icoU16(_ v: Int) { var x = UInt16(v).littleEndian; ico.append(Data(bytes: &x, count: 2)) }
func icoU32(_ v: Int) { var x = UInt32(v).littleEndian; ico.append(Data(bytes: &x, count: 4)) }
icoU16(0); icoU16(1); icoU16(entries.count)
var offset = 6 + 16 * entries.count
for e in entries {
  ico.append(UInt8(e.size & 0xff)); ico.append(UInt8(e.size & 0xff))  // 256 becomes 0
  ico.append(0); ico.append(0); icoU16(1); icoU16(32)
  icoU32(e.data.count); icoU32(offset)
  offset += e.data.count
}
for e in entries { ico.append(e.data) }
write(ico, icoPath)

// ---------------------------------------------------------------------------
// macOS .icns through iconutil, artwork inset to Apple's 824/1024 grid
// ---------------------------------------------------------------------------

let tmp = NSTemporaryDirectory() + "gittan-\(getpid()).iconset"
try? fm.removeItem(atPath: tmp)
do { try fm.createDirectory(atPath: tmp, withIntermediateDirectories: true) } catch { fail("cannot create \(tmp)") }
let macInset: CGFloat = 100.0 / 1024.0
for n in [16, 32, 128, 256, 512] {
  for scale in [1, 2] {
    let px = n * scale
    let bm = resized(cutImage, to: px, inset: macInset * CGFloat(px))
    let name = scale == 1 ? "icon_\(n)x\(n).png" : "icon_\(n)x\(n)@2x.png"
    write(bm.pngData(), tmp + "/" + name)
  }
}
let p = Process()
p.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
p.arguments = ["-c", "icns", tmp, "-o", outDir + "/Gittan.icns"]
do { try p.run() } catch { fail("cannot run iconutil") }
p.waitUntilExit()
try? fm.removeItem(atPath: tmp)
if p.terminationStatus != 0 { fail("iconutil failed") }
print("wrote \(outDir)/gittan.png, \(outDir)/png/, \(outDir)/Gittan.icns, \(icoPath)")
