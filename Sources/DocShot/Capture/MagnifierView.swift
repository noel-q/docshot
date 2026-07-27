import SwiftUI

/// Renders a fixed 11x11 nearest-neighbour pixel matrix with a center reticle at (5,5).
///
/// Out-of-bounds cells render a checkerboard tile, preserving the 11x11 grid layout.
public struct MagnifierView: View {
    public let grid: MagnifierGrid

    /// Each source pixel is deliberately enlarged to a 12 pt square; the view never
    /// interpolates pixels from the captured image.
    public static let cellSize: CGFloat = 12
    public static let cellSpacing: CGFloat = 1
    public static let outerPadding: CGFloat = 4
    public static let renderedSize: CGFloat =
        CGFloat(MagnifierGrid.dimension) * cellSize
        + CGFloat(MagnifierGrid.dimension - 1) * cellSpacing
        + outerPadding * 2

    public init(grid: MagnifierGrid) {
        self.grid = grid
    }

    public var body: some View {
        VStack(spacing: Self.cellSpacing) {
            ForEach(0..<MagnifierGrid.dimension, id: \.self) { row in
                HStack(spacing: Self.cellSpacing) {
                    ForEach(0..<MagnifierGrid.dimension, id: \.self) { col in
                        let sample = grid.pixels[row][col]
                        let isCenter = (row == MagnifierGrid.centerIndex && col == MagnifierGrid.centerIndex)

                        ZStack {
                            if let sample {
                                Rectangle()
                                    .fill(Color(
                                        .sRGB,
                                        red: Double(sample.red) / 255.0,
                                        green: Double(sample.green) / 255.0,
                                        blue: Double(sample.blue) / 255.0,
                                        opacity: 1.0
                                    ))
                            } else {
                                // Checkerboard / empty edge padding for out-of-bounds pixels
                                Rectangle()
                                    .fill((row + col) % 2 == 0 ? Color.black.opacity(0.6) : Color.gray.opacity(0.3))
                            }

                            if isCenter {
                                Rectangle()
                                    .stroke(Color.white, lineWidth: 1.5)
                                    .shadow(color: .black.opacity(0.8), radius: 1)
                            }
                        }
                        .frame(width: Self.cellSize, height: Self.cellSize)
                    }
                }
            }
        }
        .padding(Self.outerPadding)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(Color.black.opacity(0.85))
                .shadow(color: .black.opacity(0.5), radius: 6, x: 0, y: 3)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(Color.white.opacity(0.2), lineWidth: 1)
        )
    }
}
