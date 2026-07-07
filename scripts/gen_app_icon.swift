import AppKit

let S: CGFloat = 1024

func col(_ hex: UInt32, _ a: CGFloat = 1) -> NSColor {
    NSColor(red: CGFloat((hex>>16)&0xFF)/255, green: CGFloat((hex>>8)&0xFF)/255, blue: CGFloat(hex&0xFF)/255, alpha: a)
}
let gold = col(0xD4B36A), goldLight = col(0xE9CD8D), goldDark = col(0xB78F3E), ink = col(0x0E0E11)

// SF Symbol → 골드 틴트 NSImage (중첩 lockFocus)
func goldSymbol(_ name: String, point: CGFloat, weight: NSFont.Weight = .semibold) -> NSImage {
    let cfg = NSImage.SymbolConfiguration(pointSize: point, weight: weight)
    let base = NSImage(systemSymbolName: name, accessibilityDescription: nil)!.withSymbolConfiguration(cfg)!
    let out = NSImage(size: base.size)
    out.lockFocus()
    base.draw(at: .zero, from: NSRect(origin: .zero, size: base.size), operation: .sourceOver, fraction: 1)
    gold.setFill()
    NSRect(origin: .zero, size: base.size).fill(using: .sourceAtop)
    out.unlockFocus()
    return out
}
func drawCentered(_ img: NSImage, cx: CGFloat, cy: CGFloat, w: CGFloat) {
    let h = w * img.size.height / img.size.width
    img.draw(in: NSRect(x: cx - w/2, y: cy - h/2, width: w, height: h),
             from: NSRect(origin: .zero, size: img.size), operation: .sourceOver, fraction: 1)
}

// ── 메인 렌더 (lockFocus) ──
let canvas = NSImage(size: NSSize(width: S, height: S))
canvas.lockFocus()

NSGradient(colors: [col(0x1B1B20), col(0x0A0A0C)])!.draw(in: NSRect(x: 0, y: 0, width: S, height: S), angle: -90)
NSGradient(colors: [col(0xD4B36A, 0.18), col(0xD4B36A, 0.0)])!
    .draw(in: NSBezierPath(ovalIn: NSRect(x: S/2-440, y: S/2-440, width: 880, height: 880)),
          relativeCenterPosition: .zero)

// 자동차 (측면) — 메인, 위쪽
drawCentered(goldSymbol("car.side.fill", point: 300), cx: S/2, cy: 610, w: 680)

// ₩ 코인 (지갑/돈) — 우하단 배지
let coinR: CGFloat = 172
let coinC = CGPoint(x: 675, y: 330)
let coinRect = NSRect(x: coinC.x-coinR, y: coinC.y-coinR, width: coinR*2, height: coinR*2)
// 코인 뒤 다크 테두리(분리감)
ink.setStroke()
let halo = NSBezierPath(ovalIn: coinRect.insetBy(dx: -16, dy: -16)); halo.lineWidth = 32; halo.stroke()
NSGraphicsContext.saveGraphicsState()
NSBezierPath(ovalIn: coinRect).addClip()
NSGradient(colors: [goldLight, goldDark])!.draw(in: coinRect, angle: -60)
NSGraphicsContext.restoreGraphicsState()
// ₩
let won = "₩" as NSString
let para = NSMutableParagraphStyle(); para.alignment = .center
let attrs: [NSAttributedString.Key: Any] = [
    .font: NSFont.systemFont(ofSize: 200, weight: .heavy), .foregroundColor: ink, .paragraphStyle: para,
]
let ws = won.size(withAttributes: attrs)
won.draw(at: NSPoint(x: coinC.x - ws.width/2, y: coinC.y - ws.height/2 - 6), withAttributes: attrs)

canvas.unlockFocus()

// ── 정확히 1024×1024로 래스터화 ──
let cg = canvas.cgImage(forProposedRect: nil, context: nil, hints: nil)!
let ctx = CGContext(data: nil, width: 1024, height: 1024, bitsPerComponent: 8, bytesPerRow: 0,
                    space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
ctx.interpolationQuality = .high
ctx.draw(cg, in: CGRect(x: 0, y: 0, width: 1024, height: 1024))
let final = ctx.makeImage()!
let rep = NSBitmapImageRep(cgImage: final)
let png = rep.representation(using: .png, properties: [:])!
try! png.write(to: URL(fileURLWithPath: "/Users/kimchannyeon/Documents/Claude/vault/ios/Vault/Assets.xcassets/AppIcon.appiconset/AppIcon-1024.png"))
print("icon written \(final.width)x\(final.height)")
