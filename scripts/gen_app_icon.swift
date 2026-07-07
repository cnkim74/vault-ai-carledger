import AppKit

let S: CGFloat = 1024

// 정확히 1024×1024, 알파 없는(불투명) 비트맵
let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 1024, pixelsHigh: 1024,
                           bitsPerSample: 8, samplesPerPixel: 3, hasAlpha: false, isPlanar: false,
                           colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

func col(_ hex: UInt32, _ a: CGFloat = 1) -> NSColor {
    NSColor(red: CGFloat((hex>>16)&0xFF)/255, green: CGFloat((hex>>8)&0xFF)/255, blue: CGFloat(hex&0xFF)/255, alpha: a)
}
let goldLight = col(0xE9CD8D), goldDark = col(0xB78F3E), gold = col(0xD4B36A)

// 배경: 어두운 세로 그라데이션
NSGradient(colors: [col(0x1B1B20), col(0x0A0A0C)])!.draw(in: NSRect(x: 0, y: 0, width: S, height: S), angle: -90)

let c = CGPoint(x: S/2, y: S/2)

// 중앙 골드 글로우
NSGradient(colors: [col(0xD4B36A, 0.20), col(0xD4B36A, 0.0)])!
    .draw(in: NSBezierPath(ovalIn: NSRect(x: c.x-430, y: c.y-430, width: 860, height: 860)),
          relativeCenterPosition: NSPoint(x: 0, y: 0))

func fillGold(_ path: NSBezierPath) {
    NSGraphicsContext.saveGraphicsState()
    path.addClip()
    NSGradient(colors: [goldLight, goldDark])!.draw(in: path.bounds, angle: -60)
    NSGraphicsContext.restoreGraphicsState()
}

let rimOuter: CGFloat = 340, rimInner: CGFloat = 292

// 스포크 (6개)
gold.setStroke()
for i in 0..<6 {
    let a = CGFloat(i) * .pi / 3.0
    let p = NSBezierPath()
    p.lineWidth = 40; p.lineCapStyle = .round
    p.move(to: NSPoint(x: c.x + cos(a)*90, y: c.y + sin(a)*90))
    p.line(to: NSPoint(x: c.x + cos(a)*rimInner, y: c.y + sin(a)*rimInner))
    p.stroke()
}

// 바깥 림 (도넛)
let ring = NSBezierPath(ovalIn: NSRect(x: c.x-rimOuter, y: c.y-rimOuter, width: rimOuter*2, height: rimOuter*2))
ring.append(NSBezierPath(ovalIn: NSRect(x: c.x-rimInner, y: c.y-rimInner, width: rimInner*2, height: rimInner*2)))
ring.windingRule = .evenOdd
fillGold(ring)

// 중앙 허브
fillGold(NSBezierPath(ovalIn: NSRect(x: c.x-118, y: c.y-118, width: 236, height: 236)))
col(0x0E0E11).setFill()
NSBezierPath(ovalIn: NSRect(x: c.x-82, y: c.y-82, width: 164, height: 164)).fill()

// 중앙 'W'
let w = "W" as NSString
let para = NSMutableParagraphStyle(); para.alignment = .center
let attrs: [NSAttributedString.Key: Any] = [
    .font: NSFont.systemFont(ofSize: 138, weight: .heavy),
    .foregroundColor: gold, .paragraphStyle: para,
]
let size = w.size(withAttributes: attrs)
w.draw(at: NSPoint(x: c.x - size.width/2, y: c.y - size.height/2), withAttributes: attrs)

NSGraphicsContext.restoreGraphicsState()

let png = rep.representation(using: .png, properties: [:])!
let out = "/Users/kimchannyeon/Documents/Claude/vault/ios/Vault/Assets.xcassets/AppIcon.appiconset/AppIcon-1024.png"
try! png.write(to: URL(fileURLWithPath: out))
print("icon written \(rep.pixelsWide)x\(rep.pixelsHigh) alpha=\(rep.hasAlpha)")
