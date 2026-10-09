import AppKit
import SwiftUI

/// Where a character's jaw is in their portrait, as fractions of the image (origin top-left):
/// from the line between the lips (traced, so it can curve and slope) straight down to the
/// chin. While they talk, that piece of the portrait drops like a nutcracker's jaw.
struct PortraitJaw {
    /// The line between the lips, from the viewer's left corner to the right, traced along the
    /// top of the lower lip so the whole lower lip moves with the jaw.
    var lipLine: [CGPoint]
    /// The bottom of the chin.
    var chinY: CGFloat
    /// How far the jaw drops when fully open, as a fraction of the image height.
    var maxDrop: CGFloat
    /// The jaw's left side, top to bottom, when it isn't straight down from the lip line (the
    /// ambassador's runs along the celery so no celery is in the moving piece).
    var leftEdge: [CGPoint]? = nil
    /// Something in front of the mouth that shouldn't move with the jaw (the ambassador's
    /// celery): this part of the portrait is drawn again on top, in place.
    var foreground: [CGPoint]? = nil

    /// The right edge of the ambassador's celery stalk, top to bottom.
    static let ambassadorCeleryEdge: [CGPoint] = [
        CGPoint(x: 0.517, y: 0.530), CGPoint(x: 0.514, y: 0.537), CGPoint(x: 0.511, y: 0.542),
        CGPoint(x: 0.505, y: 0.555), CGPoint(x: 0.497, y: 0.567), CGPoint(x: 0.492, y: 0.580),
        CGPoint(x: 0.486, y: 0.592), CGPoint(x: 0.486, y: 0.605), CGPoint(x: 0.480, y: 0.617),
        CGPoint(x: 0.474, y: 0.630), CGPoint(x: 0.465, y: 0.642), CGPoint(x: 0.461, y: 0.655),
        CGPoint(x: 0.457, y: 0.667), CGPoint(x: 0.453, y: 0.680), CGPoint(x: 0.450, y: 0.692),
        CGPoint(x: 0.448, y: 0.700), CGPoint(x: 0.444, y: 0.720), CGPoint(x: 0.440, y: 0.740),
    ]

    static let byCharacter: [String: PortraitJaw] = [
        "blather": PortraitJaw(
            lipLine: [
                CGPoint(x: 0.394, y: 0.4660), CGPoint(x: 0.407, y: 0.4615), CGPoint(x: 0.418, y: 0.4540),
                CGPoint(x: 0.440, y: 0.4525), CGPoint(x: 0.457, y: 0.4530), CGPoint(x: 0.470, y: 0.4508),
                CGPoint(x: 0.485, y: 0.4502), CGPoint(x: 0.500, y: 0.4508), CGPoint(x: 0.515, y: 0.4520),
                CGPoint(x: 0.526, y: 0.4560), CGPoint(x: 0.540, y: 0.4610), CGPoint(x: 0.544, y: 0.4635),
            ],
            chinY: 0.578, maxDrop: 0.045),
        // His mouth already hangs open; the jaw is the tongue and lower lip. The celery stalk
        // he's munching stays put in front of it.
        "ambassador": PortraitJaw(
            lipLine: [
                CGPoint(x: 0.514, y: 0.537), CGPoint(x: 0.533, y: 0.537), CGPoint(x: 0.580, y: 0.5335),
                CGPoint(x: 0.627, y: 0.532), CGPoint(x: 0.650, y: 0.535), CGPoint(x: 0.669, y: 0.530),
            ],
            chinY: 0.700, maxDrop: 0.05,
            // Traced along the celery's right edge (detected from its green pixels).
            leftEdge: Self.ambassadorCeleryEdge.filter { $0.y >= 0.537 && $0.y <= 0.700 },
            foreground: [
                CGPoint(x: 0.400, y: 0.505), CGPoint(x: 0.445, y: 0.509), CGPoint(x: 0.452, y: 0.513),
                CGPoint(x: 0.463, y: 0.530), CGPoint(x: 0.472, y: 0.537), CGPoint(x: 0.487, y: 0.535),
                CGPoint(x: 0.500, y: 0.530), CGPoint(x: 0.517, y: 0.524),
            ] + Self.ambassadorCeleryEdge + [CGPoint(x: 0.400, y: 0.740)]),
    ]

    /// The jaw's outline in a portrait of `size`: along the lips on top, flat under the chin.
    func outline(in size: CGSize) -> Path {
        Path { path in
            guard let first = lipLine.first, let last = lipLine.last else { return }
            func point(_ p: CGPoint) -> CGPoint { CGPoint(x: p.x * size.width, y: p.y * size.height) }
            path.move(to: point(first))
            for p in lipLine.dropFirst() { path.addLine(to: point(p)) }
            path.addLine(to: point(CGPoint(x: last.x, y: chinY)))
            if let leftEdge {
                for p in leftEdge.reversed() { path.addLine(to: point(p)) }
            } else {
                path.addLine(to: point(CGPoint(x: first.x, y: chinY)))
            }
            path.closeSubpath()
        }
    }

    /// The mouth the jaw opens when it has dropped `drop` points: the strip between the lip line
    /// and where it has moved to, plus the wedge a slanted left edge leaves beside it (beside the
    /// ambassador's celery, you see into his mouth).
    func mouth(in size: CGSize, drop: CGFloat) -> Path {
        let shift = CGSize(width: 0, height: drop)
        var path = Path { path in
            let top = lipLine.map { CGPoint(x: $0.x * size.width, y: $0.y * size.height) }
            guard let first = top.first else { return }
            path.move(to: first)
            for p in top.dropFirst() { path.addLine(to: p) }
            for p in top.reversed() { path.addLine(to: CGPoint(x: p.x + shift.width, y: p.y + shift.height)) }
            path.closeSubpath()
        }
        if let leftEdge {
            let edge = leftEdge.map { CGPoint(x: $0.x * size.width, y: $0.y * size.height) }
            path.addPath(Path { wedge in
                guard let first = edge.first else { return }
                wedge.move(to: first)
                for p in edge.dropFirst() { wedge.addLine(to: p) }
                for p in edge.reversed() { wedge.addLine(to: CGPoint(x: p.x + shift.width, y: p.y + shift.height)) }
                wedge.closeSubpath()
            })
        }
        return path
    }

    static func polygon(_ points: [CGPoint], in size: CGSize) -> Path {
        Path { path in
            guard let first = points.first else { return }
            path.move(to: CGPoint(x: first.x * size.width, y: first.y * size.height))
            for p in points.dropFirst() { path.addLine(to: CGPoint(x: p.x * size.width, y: p.y * size.height)) }
            path.closeSubpath()
        }
    }
}

/// A glowing part of a portrait (SNARK-9's amber lens) that brightens as they speak.
struct PortraitGlow {
    var center: CGPoint
    var radius: CGFloat

    static let byCharacter: [String: PortraitGlow] = [
        "sidekick": PortraitGlow(center: CGPoint(x: 0.578, y: 0.517), radius: 0.10),
    ]
}

/// A robot that talks through a speaker (Floyd): as they speak, the speaker grille shakes and
/// their eyes flicker brighter, both following the loudness of their voice.
struct PortraitSpeaker {
    /// The perforated grille's outline, as fractions of the image. Only this part shakes.
    var grille: [CGPoint]
    /// Glowing eyes: centers and radii, as fractions of the image.
    var eyes: [(center: CGPoint, radius: CGFloat)]

    static let byCharacter: [String: PortraitSpeaker] = [
        // A half moon, flat edge on top, tilted with his head.
        "floyd": PortraitSpeaker(grille: [(0.4667, 0.4125), (0.5833, 0.3817), (0.5847, 0.3917), (0.5825, 0.4017),
                                          (0.5783, 0.4100), (0.5700, 0.4175), (0.5567, 0.4250), (0.5400, 0.4308),
                                          (0.5200, 0.4350), (0.4983, 0.4370), (0.4817, 0.4353), (0.4725, 0.4300),
                                          (0.4675, 0.4217)].map { CGPoint(x: $0.0, y: $0.1) },
                                 eyes: [(CGPoint(x: 0.400, y: 0.324), 0.028), (CGPoint(x: 0.592, y: 0.272), 0.027)]),
    ]
}

/// A square portrait whose jaw (if the character has one mapped) drops by `openness` (0 to 1),
/// or whose glow (if it has one) brightens by it.
struct TalkingPortrait: View {
    let image: NSImage
    let jaw: PortraitJaw?
    var glow: PortraitGlow? = nil
    var speaker: PortraitSpeaker? = nil
    var openness: Double = 0

    /// Inside of the mouth: very dark red-brown, since pure black looks like a hole in the image.
    static let mouthColor = Color(red: 0.17, green: 0.06, blue: 0.05)
    static let glowColor = Color(red: 1.0, green: 0.62, blue: 0.18)

    var body: some View {
        GeometryReader { geometry in
            let size = geometry.size
            ZStack(alignment: .topLeading) {
                Image(nsImage: image)
                    .resizable()
                    .frame(width: size.width, height: size.height)
                let drop = CGFloat(openness) * (jaw?.maxDrop ?? 0) * size.height
                // Below about half a point there's nothing to see, so draw nothing extra (no seams).
                if let jaw, drop >= 0.5 {
                    let outline = jaw.outline(in: size)
                    // The open mouth between the lips.
                    jaw.mouth(in: size, drop: drop).fill(Self.mouthColor)
                    // The jaw itself: that piece of the portrait, moved down.
                    Image(nsImage: image)
                        .resizable()
                        .frame(width: size.width, height: size.height)
                        .mask { outline }
                        // A soft shadow so it reads as hinging inward rather than floating.
                        .shadow(color: .black.opacity(0.55), radius: size.width * 0.006, y: -size.width * 0.003)
                        .offset(y: drop)
                    // Anything in front of the mouth, back on top where it was.
                    if let foreground = jaw.foreground {
                        Image(nsImage: image)
                            .resizable()
                            .frame(width: size.width, height: size.height)
                            .mask { PortraitJaw.polygon(foreground, in: size) }
                    }
                }
                if let speaker, openness > 0.02 {
                    TimelineView(.animation(minimumInterval: 1.0 / 30)) { timeline in
                        speakerEffects(speaker, size: size, time: timeline.date.timeIntervalSinceReferenceDate)
                    }
                    .allowsHitTesting(false)
                }
                if let glow, openness > 0.02 {
                    let center = CGPoint(x: glow.center.x * size.width, y: glow.center.y * size.height)
                    let radius = glow.radius * size.width
                    RadialGradient(colors: [Self.glowColor.opacity(0.85), Self.glowColor.opacity(0.35), .clear],
                                   center: .center, startRadius: 0, endRadius: radius * 1.6)
                        .frame(width: radius * 3.2, height: radius * 3.2)
                        .position(center)
                        .blendMode(.screen)
                        .opacity(openness)
                        .allowsHitTesting(false)
                }
            }
        }
        .aspectRatio(1, contentMode: .fit)
    }

    /// The grille buzzing in place, and the eyes flickering, at this moment.
    @ViewBuilder
    private func speakerEffects(_ speaker: PortraitSpeaker, size: CGSize, time: Double) -> some View {
        let loudness = CGFloat(openness)
        let noise = { (seed: Double) in Self.noise(time, seed) }
        let grille = speaker.grille.map { CGPoint(x: $0.x * size.width, y: $0.y * size.height) }
        let xs = speaker.grille.map(\.x), ys = speaker.grille.map(\.y)
        let middle = UnitPoint(x: (xs.min()! + xs.max()!) / 2, y: (ys.min()! + ys.max()!) / 2)
        // Stronger in small portraits, where the closeup's amount would barely show.
        let boost = min(3, max(1, 600 / size.width))
        let shake = size.width * 0.0035 * boost * loudness
        ZStack(alignment: .topLeading) {
            // The perforated grille, jiggled and pulsed inside its rim, which stays put.
            Image(nsImage: image)
                .resizable()
                .frame(width: size.width, height: size.height)
                .scaleEffect(1 + 0.03 * boost * loudness * (0.5 + noise(5) / 2),
                             anchor: middle)
                .offset(x: shake * noise(1), y: shake * noise(3))
                .mask {
                    Path { $0.addLines(grille); $0.closeSubpath() }
                        .blur(radius: size.width * 0.0015)
                }
            // Eyes flaring and flickering.
            ForEach(Array(speaker.eyes.enumerated()), id: \.offset) { index, eye in
                let radius = eye.radius * size.width
                let flicker = max(0, 0.55 + 0.45 * noise(Double(index) * 11 + 7))
                RadialGradient(colors: [Color.white.opacity(0.95), Color(red: 1, green: 0.75, blue: 0.9).opacity(0.5), .clear],
                               center: .center, startRadius: 0, endRadius: radius * 2.2)
                    .frame(width: radius * 4.4, height: radius * 4.4)
                    .position(x: eye.center.x * size.width, y: eye.center.y * size.height)
                    .blendMode(.screen)
                    .opacity(Double(loudness * flicker))
            }
        }
    }

    /// Cheap repeatable jitter in -1...1: a few sines at unrelated rates.
    private static func noise(_ time: Double, _ seed: Double) -> CGFloat {
        CGFloat((sin(time * 47 + seed) + sin(time * 83 + seed * 1.7) + sin(time * 131 + seed * 2.3)) / 3)
    }
}
