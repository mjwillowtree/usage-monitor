import AppKit
import SwiftUI
import QuartzCore

/// The clickover effect. When the monthly total crosses a tier floor we
/// rain confetti (and bananas) over the whole screen and flash a
/// promotion card. Click-through, all-spaces, self-dismissing.
/// Always called from the main thread (menu/timer callbacks).
final class Celebration {
    private static var activeWindow: NSWindow?

    static func show(tierIndex: Int) {
        guard tierIndex >= 0, tierIndex < TierLadder.tiers.count else { return }
        let tier = TierLadder.tiers[tierIndex]
        let style = tier.celebration
        guard style != .none else { return }
        guard let screen = NSScreen.main else { return }

        activeWindow?.orderOut(nil)

        let window = NSWindow(
            contentRect: screen.frame,
            styleMask: .borderless,
            backing: .buffered,
            defer: false)
        window.level = .statusBar
        window.isOpaque = false
        window.backgroundColor = .clear
        window.ignoresMouseEvents = true
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        window.isReleasedWhenClosed = false

        let container = NSView(frame: screen.frame)
        container.wantsLayer = true
        window.contentView = container

        window.orderFrontRegardless()
        activeWindow = window

        // Load-Bearing Customer bricks the screen over before the party
        // starts; everything below waits for the wall to blow.
        let reveal: Double
        if style == .ridiculous {
            NSSound(named: "Tink")?.play()
            reveal = runTetris(in: container)
        } else {
            reveal = 0
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + reveal) {
            let emitter = makeEmitter(tier: tier, bounds: container.bounds)
            container.layer?.addSublayer(emitter)

            if style == .insanity || style == .eventHorizon {
                addLightning(to: container, color: style == .eventHorizon ? .black : .white)
            }

            let card = NSHostingView(rootView: PromotionCard(tier: tier))
            card.frame.size = card.fittingSize
            card.frame.origin = NSPoint(
                x: (container.bounds.width - card.frame.width) / 2,
                y: (container.bounds.height - card.frame.height) / 2)
            container.addSubview(card)

            switch style {
            case .insanity: NSSound(named: "Hero")?.play()
            case .eventHorizon: NSSound(named: "Basso")?.play()
            case .ridiculous: break  // the wall explosion is the fanfare
            default: NSSound(named: "Glass")?.play()
            }

            // Stop emitting after the initial burst, let stragglers fall,
            // then fade the whole thing out.
            let (emitFor, fadeAt) = timing(for: style)
            DispatchQueue.main.asyncAfter(deadline: .now() + emitFor) {
                emitter.birthRate = 0
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + fadeAt) {
                NSAnimationContext.runAnimationGroup({ context in
                    context.duration = 0.8
                    window.animator().alphaValue = 0
                }, completionHandler: {
                    window.orderOut(nil)
                    if activeWindow === window { activeWindow = nil }
                })
            }
        }
    }

    // MARK: - Tetris (Load-Bearing Customer)

    /// Rapidly bricks the whole screen over with tetrominoes, bottom band
    /// first, then blows the wall apart from the center. Returns the time
    /// offset of the explosion, when the card and confetti should appear.
    private static func runTetris(in container: NSView) -> Double {
        guard let root = container.layer else { return 0 }
        let bounds = container.bounds
        let cell: CGFloat = 36
        let cols = Int((bounds.width / cell).rounded(.up))
        let rows = Int((bounds.height / cell).rounded(.up))
        let bands = (rows + 1) / 2

        let wall = CALayer()
        wall.frame = bounds
        root.addSublayer(wall)

        let palette: [NSColor] = [
            .systemCyan, .systemYellow, .systemPurple, .systemGreen,
            .systemRed, .systemBlue, .systemOrange,
        ]

        var pieces: [CALayer] = []
        var lastDrop: Double = 0

        for band in 0..<bands {
            let bandDelay = Double(band) * 0.11
            var x = 0
            while x < cols {
                for shape in tetrominoPair() {
                    let color = palette.randomElement()!
                    let minX = shape.map(\.x).min()!, maxX = shape.map(\.x).max()!
                    let minY = shape.map(\.y).min()!, maxY = shape.map(\.y).max()!
                    let piece = CALayer()
                    piece.frame = CGRect(
                        x: CGFloat(x + minX) * cell,
                        y: CGFloat(band * 2 + minY) * cell,
                        width: CGFloat(maxX - minX + 1) * cell,
                        height: CGFloat(maxY - minY + 1) * cell)
                    for c in shape {
                        let square = CALayer()
                        square.frame = CGRect(
                            x: CGFloat(c.x - minX) * cell + 1,
                            y: CGFloat(c.y - minY) * cell + 1,
                            width: cell - 2, height: cell - 2)
                        square.backgroundColor = color.cgColor
                        square.borderColor = NSColor.black.withAlphaComponent(0.3).cgColor
                        square.borderWidth = 2
                        square.cornerRadius = 3
                        piece.addSublayer(square)
                    }

                    let delay = bandDelay + Double.random(in: 0...0.06)
                    lastDrop = max(lastDrop, delay)
                    let drop = CABasicAnimation(keyPath: "position.y")
                    drop.fromValue = piece.position.y + bounds.height
                    drop.toValue = piece.position.y
                    drop.duration = 0.22
                    drop.timingFunction = CAMediaTimingFunction(name: .easeIn)
                    drop.beginTime = CACurrentMediaTime() + delay
                    drop.fillMode = .backwards
                    piece.add(drop, forKey: "drop")

                    wall.addSublayer(piece)
                    pieces.append(piece)
                }
                x += 4
            }
        }

        // A beat to admire the wall, then demolition.
        let explodeAt = lastDrop + 0.22 + 0.5
        DispatchQueue.main.asyncAfter(deadline: .now() + explodeAt) {
            NSSound(named: "Blow")?.play()
            let center = CGPoint(x: bounds.midX, y: bounds.midY)
            for piece in pieces {
                let p = piece.position
                var dx = p.x - center.x + .random(in: -80...80)
                var dy = p.y - center.y + .random(in: -80...80)
                let length = max(1, sqrt(dx * dx + dy * dy))
                dx /= length; dy /= length
                let distance = CGFloat.random(in: 600...1400)

                let move = CABasicAnimation(keyPath: "position")
                move.toValue = NSValue(point: NSPoint(
                    x: p.x + dx * distance,
                    y: p.y + dy * distance - 200))
                let spin = CABasicAnimation(keyPath: "transform.rotation.z")
                spin.toValue = CGFloat.random(in: -6...6)
                let fade = CABasicAnimation(keyPath: "opacity")
                fade.toValue = 0

                let blast = CAAnimationGroup()
                blast.animations = [move, spin, fade]
                blast.duration = 1.1
                blast.timingFunction = CAMediaTimingFunction(name: .easeOut)
                blast.fillMode = .forwards
                blast.isRemovedOnCompletion = false
                piece.add(blast, forKey: "explode")
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                wall.removeFromSuperlayer()
            }
        }
        return explodeAt
    }

    /// Two tetrominoes that together tile a 4×2 block, as (x, y) cells.
    private static func tetrominoPair() -> [[(x: Int, y: Int)]] {
        switch Int.random(in: 0..<4) {
        case 0:  // two O pieces
            return [[(0, 0), (1, 0), (0, 1), (1, 1)], [(2, 0), (3, 0), (2, 1), (3, 1)]]
        case 1:  // two I pieces
            return [[(0, 0), (1, 0), (2, 0), (3, 0)], [(0, 1), (1, 1), (2, 1), (3, 1)]]
        case 2:  // L + J interlocked
            return [[(0, 0), (1, 0), (2, 0), (0, 1)], [(3, 0), (1, 1), (2, 1), (3, 1)]]
        default: // mirrored L + J
            return [[(1, 0), (2, 0), (3, 0), (3, 1)], [(0, 0), (0, 1), (1, 1), (2, 1)]]
        }
    }

    // MARK: - Confetti

    private static func timing(for style: CelebrationStyle) -> (emitFor: Double, fadeAt: Double) {
        switch style {
        case .modest: return (1.6, 4.0)
        case .ridiculous: return (3.2, 6.5)
        case .insanity, .eventHorizon: return (3.8, 8.0)
        default: return (2.4, 5.2)
        }
    }

    private static func makeEmitter(tier: Tier, bounds: CGRect) -> CAEmitterLayer {
        let emitter = CAEmitterLayer()
        emitter.frame = bounds
        emitter.emitterPosition = CGPoint(x: bounds.midX, y: bounds.maxY + 10)
        emitter.emitterSize = CGSize(width: bounds.width, height: 1)
        emitter.emitterShape = .line
        emitter.beginTime = CACurrentMediaTime()

        let style = tier.celebration
        let intensity: Float
        switch style {
        case .modest: intensity = 0.3
        case .ridiculous: intensity = 2
        case .insanity, .eventHorizon: intensity = 3
        default: intensity = 1
        }

        var cells: [CAEmitterCell] = []
        let confettiColors: [NSColor] = [
            .systemPink, .systemOrange, .systemYellow,
            .systemGreen, .systemTeal, .systemPurple,
        ]
        for color in confettiColors {
            cells.append(confettiCell(image: rectImage(color: color), birthRate: 7 * intensity, scale: 1))
        }
        // The load-bearing bananas. Ridiculous tier upgrades to a banana storm.
        let bananaRate: Float = style == .ridiculous ? 16 : 5 * intensity
        cells.append(confettiCell(image: emojiImage("🍌", size: 30), birthRate: bananaRate, scale: 1))
        cells.append(confettiCell(image: emojiImage(tier.emoji, size: 30), birthRate: 4 * intensity, scale: 1))
        cells.append(confettiCell(image: emojiImage("✳️", size: 22), birthRate: 2 * intensity, scale: 0.8))

        if style == .insanity || style == .eventHorizon {
            cells.append(confettiCell(image: emojiImage("⚡", size: 44), birthRate: 10, scale: 1.1))
            cells.append(confettiCell(image: emojiImage("⚡", size: 24), birthRate: 8, scale: 0.9))
        }

        emitter.emitterCells = cells
        return emitter
    }

    /// Full-screen strobe flashes — lightning strikes over the confetti.
    /// Post-Scarcity gets white; Singularity's lightning is black.
    private static func addLightning(to container: NSView, color: NSColor) {
        guard let layer = container.layer else { return }
        for delay in [0.3, 0.9, 1.6, 2.4, 3.3] {
            let flash = CALayer()
            flash.frame = layer.bounds
            flash.backgroundColor = color.cgColor
            flash.opacity = 0
            layer.addSublayer(flash)

            let strike = CAKeyframeAnimation(keyPath: "opacity")
            strike.values = [0, 0.85, 0.1, 0.5, 0]
            strike.keyTimes = [0, 0.15, 0.4, 0.6, 1]
            strike.duration = 0.45
            strike.beginTime = CACurrentMediaTime() + delay
            flash.add(strike, forKey: "strike")
        }
    }

    private static func confettiCell(image: NSImage, birthRate: Float, scale: CGFloat) -> CAEmitterCell {
        let cell = CAEmitterCell()
        cell.contents = image.cgImage(forProposedRect: nil, context: nil, hints: nil)
        cell.birthRate = birthRate
        cell.lifetime = 7
        cell.velocity = -420
        cell.velocityRange = 160
        cell.emissionLongitude = .pi / 2
        cell.emissionRange = .pi / 7
        cell.yAcceleration = -240
        cell.spin = 3.2
        cell.spinRange = 4.5
        cell.scale = scale
        cell.scaleRange = 0.4
        return cell
    }

    private static func rectImage(color: NSColor) -> NSImage {
        let size = NSSize(width: 12, height: 7)
        let image = NSImage(size: size)
        image.lockFocus()
        color.setFill()
        NSBezierPath(roundedRect: NSRect(origin: .zero, size: size),
                     xRadius: 3, yRadius: 3).fill()
        image.unlockFocus()
        return image
    }

    private static func emojiImage(_ emoji: String, size: CGFloat) -> NSImage {
        let attributed = NSAttributedString(
            string: emoji,
            attributes: [.font: NSFont.systemFont(ofSize: size)])
        let bounds = attributed.boundingRect(
            with: NSSize(width: 100, height: 100), options: .usesLineFragmentOrigin)
        let image = NSImage(size: bounds.size)
        image.lockFocus()
        attributed.draw(at: .zero)
        image.unlockFocus()
        return image
    }
}

// MARK: - Promotion card

private struct PromotionCard: View {
    let tier: Tier

    @State private var appeared = false

    var body: some View {
        VStack(spacing: 10) {
            Text(tier.emoji)
                .font(.system(size: 72))
            Text("TIER UNLOCKED")
                .font(.system(size: 13, weight: .heavy))
                .tracking(4)
                .foregroundStyle(.secondary)
            Text(tier.name.uppercased())
                .font(.system(size: 40, weight: .black))
                .foregroundStyle(LinearGradient(
                    colors: tier.colors, startPoint: .leading, endPoint: .trailing))
            Text(tier.promotionLine)
                .font(.system(size: 14, weight: .medium).italic())
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 48)
        .padding(.vertical, 36)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 28))
        .overlay(
            RoundedRectangle(cornerRadius: 28)
                .strokeBorder(LinearGradient(
                    colors: tier.colors, startPoint: .topLeading, endPoint: .bottomTrailing),
                    lineWidth: 2))
        .scaleEffect(appeared ? 1 : 0.5)
        .opacity(appeared ? 1 : 0)
        .rotationEffect(.degrees(appeared ? 0 : -4))
        .onAppear {
            withAnimation(.spring(response: 0.45, dampingFraction: 0.55)) {
                appeared = true
            }
        }
    }
}
