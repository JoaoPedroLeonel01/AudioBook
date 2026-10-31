import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

// Ícone do AudioBook: livro aberto com barras de equalizador saindo das páginas.
// Uso: swift Scripts/make_icon.swift AudioBook/Assets.xcassets/AppIcon.appiconset

enum Variant: String, CaseIterable { case light, dark, tinted }

func color(_ hex: UInt32, _ alpha: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255, alpha: alpha)
}

func gray(_ white: CGFloat, _ alpha: CGFloat = 1) -> CGColor { CGColor(gray: white, alpha: alpha) }

func render(_ variant: Variant, size: Int = 1024) -> Data {
    // Sem canal alfa: a App Store recusa ícones com transparência.
    let ctx = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
                        space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
    let s = CGFloat(size) / 1024
    ctx.scaleBy(x: s, y: s)
    // Coordenadas com origem no canto superior esquerdo.
    ctx.translateBy(x: 0, y: 1024)
    ctx.scaleBy(x: 1, y: -1)

    // Fundo
    let background: [CGColor] = switch variant {
    case .light: [color(0x4B3AC9), color(0x1A1458)]
    case .dark: [color(0x1D1840), color(0x08061A)]
    case .tinted: [gray(0.0), gray(0.0)]
    }
    let gradient = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB), colors: background as CFArray, locations: [0, 1])!
    ctx.drawLinearGradient(gradient, start: CGPoint(x: 200, y: 0), end: CGPoint(x: 824, y: 1024),
                           options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])

    let pageColor: CGColor = switch variant {
    case .light: color(0xFFF7E8)
    case .dark: color(0xF2E6CF)
    case .tinted: gray(0.92)
    }
    let lineColor: CGColor = switch variant {
    case .light, .dark: color(0x1A1458, 0.18)
    case .tinted: gray(0.0, 0.22)
    }
    let waveColor: CGColor = switch variant {
    case .light: color(0xFFB547)
    case .dark: color(0xFFA62B)
    case .tinted: gray(1.0)
    }

    // Barras de equalizador acima da lombada.
    ctx.setFillColor(waveColor)
    let heights: [CGFloat] = [96, 176, 250, 176, 96]
    let barWidth: CGFloat = 50, gap: CGFloat = 30, baseline: CGFloat = 462
    let totalWidth = CGFloat(heights.count) * barWidth + CGFloat(heights.count - 1) * gap
    for (index, height) in heights.enumerated() {
        let x = 512 - totalWidth / 2 + CGFloat(index) * (barWidth + gap)
        let bar = CGRect(x: x, y: baseline - height, width: barWidth, height: height)
        ctx.addPath(CGPath(roundedRect: bar, cornerWidth: barWidth / 2, cornerHeight: barWidth / 2, transform: nil))
        ctx.fillPath()
    }

    // Livro aberto: duas páginas curvas com um vão na lombada.
    func page(mirrored: Bool) -> CGPath {
        let x: (CGFloat) -> CGFloat = { mirrored ? 1024 - $0 : $0 }
        let path = CGMutablePath()
        path.move(to: CGPoint(x: x(498), y: 548))
        path.addCurve(to: CGPoint(x: x(206), y: 516), control1: CGPoint(x: x(420), y: 500), control2: CGPoint(x: x(300), y: 492))
        path.addLine(to: CGPoint(x: x(206), y: 792))
        path.addCurve(to: CGPoint(x: x(498), y: 828), control1: CGPoint(x: x(300), y: 770), control2: CGPoint(x: x(420), y: 776))
        path.closeSubpath()
        return path
    }
    for mirrored in [false, true] {
        ctx.addPath(page(mirrored: mirrored))
        ctx.setFillColor(pageColor)
        ctx.fillPath()
        // Linhas de texto acompanhando a curvatura da página.
        ctx.setStrokeColor(lineColor)
        ctx.setLineWidth(14)
        ctx.setLineCap(.round)
        let x: (CGFloat) -> CGFloat = { mirrored ? 1024 - $0 : $0 }
        // Mesma Bézier do topo da página, deslocada para baixo e encurtada nas pontas.
        func top(_ t: CGFloat) -> CGPoint {
            let p0 = CGPoint(x: 498, y: 548), p1 = CGPoint(x: 420, y: 500), p2 = CGPoint(x: 300, y: 492), p3 = CGPoint(x: 206, y: 516)
            let u = 1 - t
            let px = u * u * u * p0.x + 3 * u * u * t * p1.x + 3 * u * t * t * p2.x + t * t * t * p3.x
            let py = u * u * u * p0.y + 3 * u * u * t * p1.y + 3 * u * t * t * p2.y + t * t * t * p3.y
            return CGPoint(x: x(px), y: py)
        }
        ctx.setLineJoin(.round)
        for offset in stride(from: CGFloat(70), through: 214, by: 48) {
            let steps = 24
            for step in 0...steps {
                let t = 0.14 + 0.72 * CGFloat(step) / CGFloat(steps)
                let point = top(t)
                let shifted = CGPoint(x: point.x, y: point.y + offset)
                if step == 0 { ctx.move(to: shifted) } else { ctx.addLine(to: shifted) }
            }
            ctx.strokePath()
        }
    }

    let data = NSMutableData()
    let destination = CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(destination, ctx.makeImage()!, nil)
    CGImageDestinationFinalize(destination)
    return data as Data
}

let output = URL(fileURLWithPath: CommandLine.arguments[1])
for variant in Variant.allCases {
    try render(variant).write(to: output.appendingPathComponent("AppIcon-\(variant.rawValue).png"))
}
print("ok")
