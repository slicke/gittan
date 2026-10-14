// makeicons.swift - builds Gittan's application icons from the artwork.
//
//   swift tools/makeicons.swift <artwork.png> <outdir> <Gittan.ico>
//
// The artwork is a square image of a light blue document on a white background,
// with a neutral gray drop shadow. The document is cut out: it is told from the
// background by its blue tint, the background turns transparent and the shadow
// becomes black with the alpha of its gray, so it stays soft on any background.
// Windows and Linux get the document alone; macOS gets it on a dark rounded
// square (a superellipse, like the continuous corners of macOS app icons)
// with a gradient and a light outline.
//
// Writes:
//   <outdir>/gittan.png          1024x1024 master, the document alone
//   <outdir>/png/gittan-<n>.png  16..512 for Linux desktop files
//   <outdir>/Gittan.icns         macOS, dark rounded square inset to Apple's 824/1024 grid
//   <Gittan.ico>                 Windows/Linux LCL icon, 16..256, the document alone
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

let art = load(srcPath)
if art.width != art.height { fail("the artwork must be square, it is \(art.width)x\(art.height)") }

// ---------------------------------------------------------------------------
// Windows and Linux: the document without its background
// ---------------------------------------------------------------------------

let W = art.width, H = art.height

// The document is tinted blue; the background and shadow are neutral gray.
var tinted = [Bool](repeating: false, count: W * H)
for y in 0..<H {
  for x in 0..<W {
    let (r, _, b, _) = art.rgba(x, y)
    tinted[y * W + x] = b - r >= 3
  }
}
// The background is what an untinted path reaches from the border; the
// document is everything else, so its green, red and gray bars are kept.
var outside = [Bool](repeating: false, count: W * H)
var stack: [Int] = []
for x in 0..<W { stack.append(x); stack.append((H - 1) * W + x) }
for y in 0..<H { stack.append(y * W); stack.append(y * W + W - 1) }
while let i = stack.popLast() {
  if outside[i] || tinted[i] { continue }
  outside[i] = true
  let x = i % W, y = i / W
  if x > 0 { stack.append(i - 1) }
  if x < W - 1 { stack.append(i + 1) }
  if y > 0 { stack.append(i - W) }
  if y < H - 1 { stack.append(i + W) }
}
// The tint leaves the outline ragged: the fold's diagonal is nearly white and
// the shadow has stray tinted specks along the edge. An opening (erode, then
// dilate, 3 pixels) removes the specks before a closing (dilate, then erode,
// 5 pixels) could join them to the edge; the closing fills the notches. Two
// 13x13 averages smooth the outline, and a steep ramp around three quarters
// (a pixel inside the tint, past the gray antialiased rim) turns the blur
// back into an edge about two pixels wide.
// Combines the (2r+1)x(2r+1) neighborhood of every pixel, a row pass then a
// column pass, with pick starting from first.
func spread(_ src: [Float], _ r: Int, _ first: Float, _ pick: (Float, Float) -> Float) -> [Float] {
  var tmp = src, out = src
  for y in 0..<H { for x in 0..<W {
    var v = first
    for d in -r...r { v = pick(v, src[y * W + min(max(x + d, 0), W - 1)]) }
    tmp[y * W + x] = v
  } }
  for y in 0..<H { for x in 0..<W {
    var v = first
    for d in -r...r { v = pick(v, tmp[min(max(y + d, 0), H - 1) * W + x]) }
    out[y * W + x] = v
  } }
  return out
}
var mask = outside.map { $0 ? Float(0) : 1 }
mask = spread(spread(mask, 3, 1, min), 3, 0, max)
mask = spread(spread(mask, 5, 0, max), 5, 1, min)
mask = spread(spread(mask, 6, 0, +).map { $0 / 169 }, 6, 0, +).map { $0 / 169 }
mask = mask.map { min(1, max(0, ($0 - 0.75) * 7 + 0.5)) }
let loose = Bitmap(width: W, height: H)
for y in 0..<H {
  for x in 0..<W {
    let m = mask[y * W + x]
    let (r, g, b, _) = art.rgba(x, y)
    // The shadow's gray becomes black with that much alpha; the near white
    // background (252 and up) disappears.
    let shade = max(0, Float(252 - min(r, g, b)) / 252)
    let a = m + (1 - m) * shade
    let i = loose.offset(x, y)
    loose.data[i] = UInt8(Float(r) * m + 0.5)
    loose.data[i + 1] = UInt8(Float(g) * m + 0.5)
    loose.data[i + 2] = UInt8(Float(b) * m + 0.5)
    loose.data[i + 3] = UInt8(a * 255 + 0.5)
  }
}
let looseImage = loose.image

// ---------------------------------------------------------------------------
// macOS: the document on a black rounded square
// ---------------------------------------------------------------------------

// The outline is a superellipse |x|^5 + |y|^5 = 1, close to the continuous
// corners of macOS app icons, filled with antialiasing through a clip path.
let side = 1024
let cut = Bitmap(width: side, height: side)
let path = CGMutablePath()
let half = CGFloat(side) / 2, exponent = 5.0, steps = 2048
for i in 0..<steps {
  let t = Double(i) / Double(steps) * 2 * Double.pi
  let c = cos(t), s = sin(t)
  let x = copysign(pow(abs(c), 2 / exponent), c), y = copysign(pow(abs(s), 2 / exponent), s)
  let p = CGPoint(x: half + half * CGFloat(x), y: half + half * CGFloat(y))
  if i == 0 { path.move(to: p) } else { path.addLine(to: p) }
}
path.closeSubpath()
// Context coordinates count from the bottom: a gradient from y = side to 0
// runs from the top down.
let rgb = CGColorSpaceCreateDeviceRGB()
func gradient(_ top: [CGFloat], _ bottom: [CGFloat]) -> CGGradient {
  CGGradient(colorSpace: rgb, colorComponents: top + bottom, locations: [0, 1], count: 2)!
}
let top = CGPoint(x: 0, y: CGFloat(side)), bottom = CGPoint(x: 0, y: 0)
cut.ctx.saveGState()
cut.ctx.addPath(path)
cut.ctx.clip()
// The plate: graphite at the top, nearly black at the bottom.
cut.ctx.drawLinearGradient(gradient([0.23, 0.24, 0.27, 1], [0.03, 0.03, 0.04, 1]),
                           start: top, end: bottom, options: [])
// The document shrinks to 84% so the plate shows around it.
let docInset = CGFloat(side) * 0.08
cut.draw(looseImage, in: CGRect(x: 0, y: 0, width: side, height: side).insetBy(dx: docInset, dy: docInset))
// The outline: a 6 pixel stroke on the outline, clipped to its inner half,
// lit from above like the rims of macOS icons.
cut.ctx.addPath(path)
cut.ctx.setLineWidth(12)
cut.ctx.replacePathWithStrokedPath()
cut.ctx.clip()
cut.ctx.drawLinearGradient(gradient([1, 1, 1, 0.45], [1, 1, 1, 0.12]), start: top, end: bottom, options: [])
cut.ctx.restoreGState()
let cutImage = cut.image

let fm = FileManager.default
try? fm.createDirectory(atPath: outDir + "/png", withIntermediateDirectories: true)

func write(_ data: Data, _ path: String) {
  do { try data.write(to: URL(fileURLWithPath: path)) } catch { fail("cannot write \(path): \(error)") }
}

let master = resized(looseImage, to: 1024)
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
