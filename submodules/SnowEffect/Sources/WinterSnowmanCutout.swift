import Foundation
import CoreGraphics

/// Derives independent, cached accessories from the existing fixed reference, not from stage snapshots.
/// No body pixels enter these sprites. The immutable source is always the same red knitted preset.
enum WinterSnowmanCutout {
    enum Part: String { case arms, scarf, nose, eyes, smile, buttons }

    static func image(from source: CGImage, part: Part, tint: [CGFloat]? = nil) -> CGImage? {
        let side = 512
        guard source.width == side, source.height == side else { return nil }
        let bitmapInfo = CGBitmapInfo.byteOrder32Big.union(CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue))
        var input = [UInt8](repeating: 0, count: side * side * 4)
        var drawn = false
        input.withUnsafeMutableBytes { buffer in
            guard let c = CGContext(data: buffer.baseAddress, width: side, height: side, bitsPerComponent: 8, bytesPerRow: side * 4, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: bitmapInfo.rawValue) else { return }
            c.draw(source, in: CGRect(x: 0, y: 0, width: side, height: side)); drawn = true
        }
        guard drawn else { return nil }
        let bounds: (left: Int, top: Int, right: Int, bottom: Int)
        switch part {
        case .arms: bounds = (90, 198, 422, 294)
        case .scarf: bounds = (140, 198, 368, 390)
        case .nose: bounds = (238, 163, 292, 208)
        case .eyes: bounds = (212, 150, 300, 180)
        case .smile: bounds = (218, 180, 289, 206)
        case .buttons: bounds = (235, 262, 276, 390)
        }
        // Flood-fill the exterior of the material mask. Enclosed white embroidery and
        // highlights belong to the cloth/wood; the surrounding white snow stays transparent.
        var mask = [UInt8](repeating: 0, count: side * side)
        for y in bounds.top..<bounds.bottom { for x in bounds.left..<bounds.right {
            let index = y * side + x, pixel = index * 4
            guard input[pixel + 3] > 32 else { continue }
            let r = Double(input[pixel]), g = Double(input[pixel + 1]), b = Double(input[pixel + 2])
            let belongs: Bool
            switch part {
            case .arms: belongs = r > g * 1.18 && g > b * 1.16 && g > 18
            case .scarf: belongs = r > g * 1.45 && r > b * 1.45 && g <= b * 1.45 && r > 45
            case .nose: belongs = r > g * 1.2 && g > b * 1.5 && g > 35
            case .eyes, .smile, .buttons: belongs = max(r, g, b) < 140 && max(r, g, b) - min(r, g, b) < 40
            }
            if belongs { mask[index] = 1 }
        } }
        // Shadows on red yarn can be brown, and dark wood can be reddish.
        // Keep the material's actual connected objects, not unrelated colour matches.
        var components: [[Int]] = []
        for y in bounds.top..<bounds.bottom { for x in bounds.left..<bounds.right {
            let start = y * side + x
            guard mask[start] == 1 else { continue }
            var component = [start]; mask[start] = 3
            var cursor = 0
            while cursor < component.count {
                let index = component[cursor]; cursor += 1
                let px = index % side, py = index / side
                for next in [px > bounds.left ? index - 1 : -1, px + 1 < bounds.right ? index + 1 : -1, py > bounds.top ? index - side : -1, py + 1 < bounds.bottom ? index + side : -1] where next >= 0 && mask[next] == 1 {
                    mask[next] = 3; component.append(next)
                }
            }
            components.append(component)
        } }
        mask = [UInt8](repeating: 0, count: mask.count)
        let componentCount = part == .buttons ? 3 : ((part == .arms || part == .eyes) ? 2 : 1)
        for component in components.sorted(by: { $0.count > $1.count }).prefix(componentCount) {
            for index in component { mask[index] = 1 }
        }
        var exterior: [Int] = []
        func seed(_ index: Int) {
            if mask[index] == 0 { mask[index] = 2; exterior.append(index) }
        }
        for x in bounds.left..<bounds.right {
            seed(bounds.top * side + x); seed((bounds.bottom - 1) * side + x)
        }
        for y in bounds.top..<bounds.bottom {
            seed(y * side + bounds.left); seed(y * side + bounds.right - 1)
        }
        var cursor = 0
        while cursor < exterior.count {
            let index = exterior[cursor]; cursor += 1
            let x = index % side, y = index / side
            if x > bounds.left { seed(index - 1) }
            if x + 1 < bounds.right { seed(index + 1) }
            if y > bounds.top { seed(index - side) }
            if y + 1 < bounds.bottom { seed(index + side) }
        }
        var output = [UInt8](repeating: 0, count: input.count)
        var count = 0
        let tint = tint.flatMap { $0.count == 3 && $0.allSatisfy({ $0.isFinite && (0...1).contains($0) }) ? $0 : nil }
        let peak = max(0.01, tint?.max() ?? 1)
        for y in bounds.top..<bounds.bottom { for x in bounds.left..<bounds.right {
            let index = y * side + x, pixel = index * 4
            guard mask[index] != 2, input[pixel + 3] > 0 else { continue }
            if let tint {
                let floor = min(input[pixel], input[pixel + 1], input[pixel + 2])
                let chroma = max(input[pixel], input[pixel + 1], input[pixel + 2]) - floor
                for channel in 0..<3 {
                    output[pixel + channel] = UInt8(clamping: Int(CGFloat(floor) + CGFloat(chroma) * tint[channel] / peak))
                }
            } else {
                for channel in 0..<3 { output[pixel + channel] = input[pixel + channel] }
            }
            output[pixel + 3] = input[pixel + 3]; count += 1
        } }
        guard count > 16, let provider = CGDataProvider(data: Data(output) as CFData) else { return nil }
        return CGImage(width: side, height: side, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: side * 4, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: bitmapInfo, provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent)
    }
}
