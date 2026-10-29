// makeicons.swift - packs Gittan's finished application icons.
//
//   swift tools/makeicons.swift <mac.png> <pngdir> <outdir> <Gittan.ico>
//
// The artwork comes finished. <mac.png> is the macOS icon at 1024 pixels, the
// tile already on Apple's 824/1024 grid with its own shadow. <pngdir> holds
// gittan-<n>.png for Windows and Linux, each drawn for its size (16 to 512),
// the small ones from a simpler drawing.
//
// Writes:
//   <outdir>/Gittan.icns         macOS, <mac.png> scaled to each size
//   <Gittan.ico>                 Windows/Linux LCL icon, 16..256 from <pngdir>
//
// macOS only (CoreGraphics, ImageIO, iconutil).

import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

let args = CommandLine.arguments
guard args.count == 5 else {
  FileHandle.standardError.write("usage: makeicons.swift <mac.png> <pngdir> <outdir> <Gittan.ico>\n".data(using: .utf8)!)
  exit(2)
}
let macPath = args[1], pngDir = args[2], outDir = args[3], icoPath = args[4]

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

func resized(_ img: CGImage, to size: Int) -> Bitmap {
  let bm = Bitmap(width: size, height: size)
  bm.draw(img, in: CGRect(x: 0, y: 0, width: size, height: size))
  return bm
}

func loadSquare(_ path: String, size: Int? = nil) -> Bitmap {
  let art = load(path)
  if art.width != art.height { fail("\(path) must be square, it is \(art.width)x\(art.height)") }
  if let n = size, art.width != n { fail("\(path) must be \(n) pixels, it is \(art.width)") }
  return art
}
let macImage = loadSquare(macPath).image

let fm = FileManager.default

func write(_ data: Data, _ path: String) {
  do { try data.write(to: URL(fileURLWithPath: path)) } catch { fail("cannot write \(path): \(error)") }
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
  let bm = loadSquare(pngDir + "/gittan-\(n).png", size: n)
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
// macOS .icns through iconutil
// ---------------------------------------------------------------------------

let tmp = NSTemporaryDirectory() + "gittan-\(getpid()).iconset"
try? fm.removeItem(atPath: tmp)
do { try fm.createDirectory(atPath: tmp, withIntermediateDirectories: true) } catch { fail("cannot create \(tmp)") }
for n in [16, 32, 128, 256, 512] {
  for scale in [1, 2] {
    let px = n * scale
    let bm = resized(macImage, to: px)
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
print("wrote \(outDir)/Gittan.icns, \(icoPath)")
