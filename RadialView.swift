import SwiftUI

/* ============================================================
   THE RADIAL · mobile edition, Carl's spec (10/11/2026)
   Always: a blue-green orb at the centre.
   speaking   blue pulse — a ring bursts out on every spoken word
   thinking   rotating brown/orange gear rings
   listening  (waiting for Carl) a white satellite orbiting, with a
              faded white ring pulsing outward; it brightens as the
              microphone hears him
   asleep     the orb alone, dimmed, breathing slowly
   Every layer is driven by JarvisEngine's real state, never a timer.
   ============================================================ */

struct RadialView: View {
    @ObservedObject var engine: JarvisEngine

    var body: some View {
        TimelineView(.animation) { timeline in
            // Snapshot the engine's state here, on the main thread, then draw.
            let now = timeline.date
            let mode = engine.mode
            let fadeIn = min(1, now.timeIntervalSince(engine.modeSince) / 0.35)
            let sinceWord = now.timeIntervalSince(engine.lastWordAt)
            let mic = Double(engine.micLevel)

            Canvas { ctx, size in
                let t = now.timeIntervalSinceReferenceDate
                let c = CGPoint(x: size.width / 2, y: size.height / 2)
                let R = min(size.width, size.height) / 2
                let orbR = R * 0.30

                // How hard the last spoken word hit, fading fast (0...1).
                let wordHit = mode == .speaking ? exp(-sinceWord * 4) : 0

                switch mode {
                case .listening:
                    drawWaiting(ctx, c: c, orbR: orbR, t: t, alpha: fadeIn, mic: mic)
                case .thinking:
                    drawGears(ctx, c: c, orbR: orbR, t: t, alpha: fadeIn)
                case .speaking:
                    drawSpeaking(ctx, c: c, orbR: orbR, hit: wordHit, alpha: fadeIn)
                case .asleep:
                    break
                }

                drawOrb(ctx, c: c, orbR: orbR, t: t,
                        dim: mode == .asleep ? 0.55 : 1, swell: wordHit)
            }
        }
    }

    // MARK: - The orb

    private func drawOrb(_ ctx: GraphicsContext, c: CGPoint, orbR: CGFloat, t: Double,
                         dim: Double, swell: Double) {
        let breathe = 1 + 0.03 * sin(t * 1.5)
        let r = orbR * CGFloat(breathe * (1 + 0.12 * swell))

        // Soft glow behind it.
        let glowR = r * 2.1
        ctx.fill(Path(ellipseIn: CGRect(x: c.x - glowR, y: c.y - glowR, width: glowR * 2, height: glowR * 2)),
                 with: .radialGradient(Gradient(colors: [
                    Color(red: 0.1, green: 0.75, blue: 0.7).opacity(0.35 * dim + 0.25 * swell),
                    Color(red: 0.05, green: 0.4, blue: 0.6).opacity(0.12 * dim),
                    .clear]),
                                       center: c, startRadius: r * 0.6, endRadius: glowR))

        // The orb itself: bright aqua core to deep blue edge.
        ctx.fill(Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2)),
                 with: .radialGradient(Gradient(colors: [
                    Color(red: 0.75, green: 1.0, blue: 0.9).opacity(dim),
                    Color(red: 0.15, green: 0.75, blue: 0.7).opacity(dim),
                    Color(red: 0.03, green: 0.35, blue: 0.55).opacity(dim),
                    Color(red: 0.02, green: 0.12, blue: 0.3).opacity(dim)]),
                                       center: CGPoint(x: c.x - r * 0.25, y: c.y - r * 0.25),
                                       startRadius: 0, endRadius: r * 1.25))
    }

    // MARK: - Waiting for Carl: white satellite and a fading pulse ring

    private func drawWaiting(_ ctx: GraphicsContext, c: CGPoint, orbR: CGFloat, t: Double,
                             alpha: Double, mic: Double) {
        let orbit = orbR * 1.55

        // Faint orbit track, brighter while he's talking.
        ctx.stroke(circle(c, orbit), with: .color(.white.opacity((0.12 + 0.35 * mic) * alpha)),
                   lineWidth: CGFloat(1 + 2 * mic))

        // A faded white ring pulsing outward, every two seconds.
        let phase = (t / 2).truncatingRemainder(dividingBy: 1)
        let pulseR = orbR * CGFloat(1.2 + 0.9 * phase)
        ctx.stroke(circle(c, pulseR), with: .color(.white.opacity(0.35 * (1 - phase) * alpha)), lineWidth: 2)

        // The satellite, with a short fading trail.
        let speed = 1.4
        for i in 0..<14 {
            let lag = Double(i) * 0.045
            let a = (t - lag) * speed
            let p = CGPoint(x: c.x + CGFloat(cos(a)) * orbit, y: c.y + CGFloat(sin(a)) * orbit)
            let size = CGFloat(i == 0 ? 6.0 : 4.0 * (1 - Double(i) / 14))
            let op = (i == 0 ? 1.0 : 0.5 * (1 - Double(i) / 14)) * alpha
            ctx.fill(circle(p, size), with: .color(.white.opacity(op)))
        }
    }

    // MARK: - Thinking: brown and orange gear rings

    private func drawGears(_ ctx: GraphicsContext, c: CGPoint, orbR: CGFloat, t: Double, alpha: Double) {
        let brown = Color(red: 0.5, green: 0.27, blue: 0.1)
        let orange = Color(red: 1.0, green: 0.55, blue: 0.15)

        // Outer gear, turning clockwise.
        let outer = orbR * 1.62
        ctx.stroke(circle(c, outer), with: .color(brown.opacity(0.9 * alpha)), lineWidth: 7)
        drawTeeth(ctx, c: c, radius: outer + 7, count: 28, length: 11, width: 7,
                  angle: t * 0.7, color: orange.opacity(0.95 * alpha))

        // Inner gear, smaller and counter-rotating.
        let inner = orbR * 1.28
        ctx.stroke(circle(c, inner), with: .color(orange.opacity(0.55 * alpha)), lineWidth: 3)
        drawTeeth(ctx, c: c, radius: inner + 4, count: 18, length: 7, width: 4,
                  angle: -t * 1.1, color: brown.opacity(alpha))
    }

    private func drawTeeth(_ ctx: GraphicsContext, c: CGPoint, radius: CGFloat, count: Int,
                           length: CGFloat, width: CGFloat, angle: Double, color: Color) {
        var teeth = Path()
        let tooth = Path(roundedRect: CGRect(x: -length / 2, y: -width / 2, width: length, height: width),
                         cornerRadius: 1.5)
        for i in 0..<count {
            let a = angle + Double(i) / Double(count) * 2 * .pi
            let place = CGAffineTransform(translationX: c.x + CGFloat(cos(a)) * radius,
                                          y: c.y + CGFloat(sin(a)) * radius)
                .rotated(by: CGFloat(a))
            teeth.addPath(tooth, transform: place)
        }
        ctx.fill(teeth, with: .color(color))
    }

    // MARK: - Speaking: a blue pulse on every word

    private func drawSpeaking(_ ctx: GraphicsContext, c: CGPoint, orbR: CGFloat, hit: Double, alpha: Double) {
        let blue = Color(red: 0.3, green: 0.55, blue: 1.0)

        // Steady blue halo, brighter on each word.
        ctx.stroke(circle(c, orbR * 1.3), with: .color(blue.opacity((0.25 + 0.5 * hit) * alpha)),
                   lineWidth: CGFloat(4 + 6 * hit))

        // The pulse: a ring that bursts outward from the orb as each word lands.
        let burstR = orbR * CGFloat(1.2 + 0.8 * (1 - hit))
        ctx.stroke(circle(c, burstR), with: .color(blue.opacity(0.8 * hit * alpha)), lineWidth: 3)
    }

    private func circle(_ c: CGPoint, _ r: CGFloat) -> Path {
        Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2))
    }
}
