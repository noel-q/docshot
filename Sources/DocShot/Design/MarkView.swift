import SwiftUI
import AppKit

public struct MarkSVGView: View {
    public init() {}
    
    private var loadedNSImage: NSImage? {
        // 1. Check Bundle.main for standalone mark.svg resource (Xcode app build)
        if let url = Bundle.main.url(forResource: "mark", withExtension: "svg"),
           let data = try? Data(contentsOf: url),
           let img = NSImage(data: data) {
            return img
        }
        
        // 2. Check image named "mark" in main bundle
        if let img = NSImage(named: "mark") {
            return img
        }

        // 3. SwiftPM (`swift build`/`swift test`) fallback: Bundle.module
        #if SWIFT_PACKAGE
        if let url = Bundle.module.url(forResource: "mark", withExtension: "svg"),
           let data = try? Data(contentsOf: url),
           let img = NSImage(data: data) {
            return img
        }
        #endif

        return nil
    }
    
    public var body: some View {
        if let nsImage = loadedNSImage {
            Image(nsImage: nsImage)
                .resizable()
                .aspectRatio(contentRatio, contentMode: .fit)
        } else {
            // Precise Vector Fallback of Noel Quadri identity mark
            GeometryReader { geo in
                let w = geo.size.width
                let h = geo.size.height
                let s = min(w, h) / 1024.0
                let xOff = (w - 1024.0 * s) / 2.0
                let yOff = (h - 1024.0 * s) / 2.0
                
                ZStack {
                    // Segment 1
                    polygonPath(points: [(729.4, 543.3), (583.3, 689.4), (539.3, 583.2), (623.2, 499.3)], scale: s, offsetX: xOff, offsetY: yOff)
                        .fill(Color(red: 0xB5/255.0, green: 0x79/255.0, blue: 0x1E/255.0))
                    
                    // Segment 2
                    polygonPath(points: [(583.3, 689.4), (376.7, 689.4), (420.7, 583.2), (539.3, 583.2)], scale: s, offsetX: xOff, offsetY: yOff)
                        .fill(Color(red: 0xB5/255.0, green: 0x79/255.0, blue: 0x1E/255.0))
                    
                    // Segment 3
                    polygonPath(points: [(376.7, 689.4), (230.6, 543.3), (336.8, 499.3), (420.7, 583.2)], scale: s, offsetX: xOff, offsetY: yOff)
                        .fill(Color(red: 0xCB/255.0, green: 0x8B/255.0, blue: 0x2F/255.0))
                    
                    // Segment 4
                    polygonPath(points: [(230.6, 543.3), (230.6, 336.7), (336.8, 380.7), (336.8, 499.3)], scale: s, offsetX: xOff, offsetY: yOff)
                        .fill(DesignTokens.identityAccent)
                    
                    // Segment 5
                    polygonPath(points: [(230.6, 336.7), (376.7, 190.6), (420.7, 296.8), (336.8, 380.7)], scale: s, offsetX: xOff, offsetY: yOff)
                        .fill(DesignTokens.identityAccent)
                    
                    // Segment 6
                    polygonPath(points: [(376.7, 190.6), (583.3, 190.6), (539.3, 296.8), (420.7, 296.8)], scale: s, offsetX: xOff, offsetY: yOff)
                        .fill(DesignTokens.identityAccent)
                    
                    // Segment 7
                    polygonPath(points: [(583.3, 190.6), (729.4, 336.7), (623.2, 380.7), (539.3, 296.8)], scale: s, offsetX: xOff, offsetY: yOff)
                        .fill(Color(red: 0xCB/255.0, green: 0x8B/255.0, blue: 0x2F/255.0))
                    
                    // Segment 8
                    polygonPath(points: [(729.4, 336.7), (729.4, 543.3), (623.2, 499.3), (623.2, 380.7)], scale: s, offsetX: xOff, offsetY: yOff)
                        .fill(Color(red: 0xB5/255.0, green: 0x79/255.0, blue: 0x1E/255.0))
                    
                    // Tail Node Link
                    polygonPath(points: [(578.3, 603.3), (719.7, 744.8), (784.8, 679.7), (643.3, 538.3)], scale: s, offsetX: xOff, offsetY: yOff)
                        .fill(DesignTokens.identityAccent)
                    
                    // Tail Node Dot
                    Path { path in
                        let rect = CGRect(
                            x: xOff + 753.7 * s,
                            y: yOff + 719.4 * s,
                            width: 96.0 * s,
                            height: 96.0 * s
                        )
                        path.addRect(rect)
                    }
                    .fill(DesignTokens.identityAccent)
                }
            }
        }
    }
    
    private var contentRatio: CGFloat { 1.0 }
    
    private func polygonPath(points: [(CGFloat, CGFloat)], scale: CGFloat, offsetX: CGFloat, offsetY: CGFloat) -> Path {
        Path { path in
            guard let first = points.first else { return }
            path.move(to: CGPoint(x: offsetX + first.0 * scale, y: offsetY + first.1 * scale))
            for pt in points.dropFirst() {
                path.addLine(to: CGPoint(x: offsetX + pt.0 * scale, y: offsetY + pt.1 * scale))
            }
            path.closeSubpath()
        }
    }
}

public struct MarkTileView: View {
    public var size: CGFloat
    public var cornerRadius: CGFloat
    
    public init(size: CGFloat = 44, cornerRadius: CGFloat = 10) {
        self.size = size
        self.cornerRadius = cornerRadius
    }
    
    public var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: cornerRadius)
                .fill(DesignTokens.graphiteBase) // #1A1D20 dark tile as specified in brand system
                .overlay(
                    RoundedRectangle(cornerRadius: cornerRadius)
                        .stroke(DesignTokens.borderSubtle, lineWidth: 1)
                )
            
            MarkSVGView()
                .padding(size * 0.18)
        }
        .frame(width: size, height: size)
    }
}
