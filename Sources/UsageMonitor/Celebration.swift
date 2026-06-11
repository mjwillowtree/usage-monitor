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

        let emitter = makeEmitter(tier: tier, bounds: container.bounds)
        container.layer?.addSublayer(emitter)

        let card = NSHostingView(rootView: PromotionCard(tier: tier))
        card.frame.size = card.fittingSize
        card.frame.origin = NSPoint(
            x: (container.bounds.width - card.frame.width) / 2,
            y: (container.bounds.height - card.frame.height) / 2)
        container.addSubview(card)

        window.orderFrontRegardless()
        activeWindow = window

        NSSound(named: "Glass")?.play()

        // Stop emitting after the initial burst, let stragglers fall,
        // then fade the whole thing out.
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.4) {
            emitter.birthRate = 0
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 5.2) {
            NSAnimationContext.runAnimationGroup({ context in
                context.duration = 0.8
                window.animator().alphaValue = 0
            }, completionHandler: {
                window.orderOut(nil)
                if activeWindow === window { activeWindow = nil }
            })
        }
    }

    // MARK: - Confetti

    private static func makeEmitter(tier: Tier, bounds: CGRect) -> CAEmitterLayer {
        let emitter = CAEmitterLayer()
        emitter.frame = bounds
        emitter.emitterPosition = CGPoint(x: bounds.midX, y: bounds.maxY + 10)
        emitter.emitterSize = CGSize(width: bounds.width, height: 1)
        emitter.emitterShape = .line
        emitter.beginTime = CACurrentMediaTime()

        var cells: [CAEmitterCell] = []
        let confettiColors: [NSColor] = [
            .systemPink, .systemOrange, .systemYellow,
            .systemGreen, .systemTeal, .systemPurple,
        ]
        for color in confettiColors {
            cells.append(confettiCell(image: rectImage(color: color), birthRate: 7, scale: 1))
        }
        // The load-bearing bananas.
        cells.append(confettiCell(image: emojiImage("🍌", size: 30), birthRate: 5, scale: 1))
        cells.append(confettiCell(image: emojiImage(tier.emoji, size: 30), birthRate: 4, scale: 1))
        cells.append(confettiCell(image: emojiImage("✳️", size: 22), birthRate: 2, scale: 0.8))

        emitter.emitterCells = cells
        return emitter
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
