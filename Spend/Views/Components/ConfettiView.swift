import SwiftUI

/// A short burst of brand-coloured confetti for a real win: the first Apple
/// Pay tap, a month closed under budget. No third-party packages — a
/// `Canvas` redrawn by `TimelineView`, with each piece's position computed
/// straight from elapsed time rather than accumulated frame to frame.
///
/// Increment `trigger` to fire. Renders nothing while Reduce Motion is on
/// (checked here too, as a safety net for any call site that forgets).
struct ConfettiView: View {
    var trigger: Int

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var pieces: [Piece] = []
    @State private var startDate: Date?

    private static let duration: TimeInterval = 1.5
    /// Extra time after the fall so the fade-out finishes before pieces stop drawing.
    private static let tail: TimeInterval = 0.3
    private static let pieceCount = 46

    private struct Piece {
        let x: CGFloat          // start x, as a fraction of width
        let color: Color
        let width: CGFloat
        let height: CGFloat
        let fallDelay: TimeInterval   // small stagger so the burst isn't one flat row
        let driftAmplitude: CGFloat
        let driftPhase: Double
        let rotationStart: Double
        let rotationSpeed: Double     // radians/sec
        let isCapsule: Bool
    }

    var body: some View {
        GeometryReader { geo in
            if !reduceMotion, let startDate {
                TimelineView(.animation) { context in
                    Canvas { ctx, size in
                        let elapsed = context.date.timeIntervalSince(startDate)
                        guard elapsed < Self.duration + Self.tail else { return }
                        for piece in pieces {
                            draw(piece, elapsed: elapsed, size: size, into: ctx)
                        }
                    }
                }
                .allowsHitTesting(false)
                .accessibilityHidden(true)
                .task(id: startDate) {
                    try? await Task.sleep(for: .seconds(Self.duration + Self.tail))
                    guard !Task.isCancelled else { return }
                    self.startDate = nil
                }
            }
        }
        .allowsHitTesting(false)
        .onChange(of: trigger) { _, _ in
            guard !reduceMotion else { return }
            pieces = Self.makePieces()
            startDate = .now
        }
    }

    private func draw(_ piece: Piece, elapsed: TimeInterval, size: CGSize, into ctx: GraphicsContext) {
        let t = max(0, elapsed - piece.fallDelay)
        guard t > 0 else { return }
        let progress = t / Self.duration
        guard progress < 1.2 else { return }

        let startY = -20.0
        let endY = size.height + 40
        let y = startY + progress * (endY - startY)
        let x = piece.x * size.width + sin(t * 2.4 + piece.driftPhase) * piece.driftAmplitude
        let rotation = piece.rotationStart + t * piece.rotationSpeed

        // Fade in fast, hold, then fade out over the last fifth of the fall.
        let opacity: Double
        if progress < 0.06 { opacity = progress / 0.06 }
        else if progress > 0.8 { opacity = max(0, 1 - (progress - 0.8) / 0.4) }
        else { opacity = 1 }
        guard opacity > 0.01 else { return }

        ctx.drawLayer { layer in
            layer.translateBy(x: x, y: y)
            layer.rotate(by: .radians(rotation))
            layer.opacity = opacity
            let rect = CGRect(x: -piece.width / 2, y: -piece.height / 2, width: piece.width, height: piece.height)
            let shape = piece.isCapsule ? Path(roundedRect: rect, cornerRadius: piece.height / 2)
                                         : Path(roundedRect: rect, cornerRadius: 1.5)
            layer.fill(shape, with: .color(piece.color))
        }
    }

    private static func makePieces() -> [Piece] {
        (0..<pieceCount).map { i in
            Piece(x: .random(in: 0...1),
                  color: Color.brandPalette[i % Color.brandPalette.count],
                  width: .random(in: 5...9),
                  height: .random(in: 10...16),
                  fallDelay: .random(in: 0...0.35),
                  driftAmplitude: .random(in: 10...34),
                  driftPhase: .random(in: 0...(2 * .pi)),
                  rotationStart: .random(in: 0...(2 * .pi)),
                  rotationSpeed: .random(in: -4...4),
                  isCapsule: Bool.random())
        }
    }
}
