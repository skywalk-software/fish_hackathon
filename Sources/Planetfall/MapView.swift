import AppKit
import PDFKit
import PlanetfallEngine
import SwiftUI

/// The full map ("cheat: map"), over the whole window. Zoom with a pinch, ⌘-scroll, the buttons,
/// or ⌘+ / ⌘- / ⌘0; drag or scroll to move around. A red star marks the player's room, and the
/// map opens centered on it.
struct MapOverlay: View {
    let map: GameMap
    let document: PDFDocument
    /// The map room the player is in, if known.
    let here: String?
    let onClose: () -> Void

    @State private var zoom = MapZoom()

    var body: some View {
        ZStack {
            Color.black.opacity(0.92)
                .ignoresSafeArea()
            ZoomableMap(map: map, document: document, here: here, zoom: zoom)
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Theme.accent, lineWidth: 2))
                .overlay(alignment: .bottomTrailing) { zoomButtons.padding(12) }
                .overlay(alignment: .bottomLeading) {
                    Text("Pinch or ⌘-scroll to zoom · drag to move")
                        .font(.system(size: 11))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Capsule().fill(.black.opacity(0.55)))
                        .padding(12)
                }
                .padding(.horizontal, 32)
                .padding(.vertical, 28)
        }
        .overlay(alignment: .topTrailing) {
            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(Theme.text)
                    .frame(width: 26, height: 26)
                    .background(Circle().fill(.white.opacity(0.15)))
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.cancelAction)
            .help("Close the map")
            .accessibilityLabel("Close the map")
            .padding(6)
        }
    }

    private var zoomButtons: some View {
        HStack(spacing: 0) {
            zoomButton("minus", help: "Zoom out (⌘-)", key: "-") { zoom.zoom(by: 1 / 1.4) }
            Divider().frame(height: 18)
            zoomButton("plus", help: "Zoom in (⌘+)", key: "=") { zoom.zoom(by: 1.4) }
            Divider().frame(height: 18)
            zoomButton("arrow.up.left.and.arrow.down.right", help: "Show the whole map (⌘0)", key: "0") { zoom.fit() }
        }
        .background(RoundedRectangle(cornerRadius: 8).fill(.black.opacity(0.55)))
    }

    private func zoomButton(_ symbol: String, help: String, key: KeyEquivalent,
                            action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 34, height: 30)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .keyboardShortcut(key, modifiers: .command)
        .help(help)
        .accessibilityLabel(help)
    }

    /// The map's PDF and room data, from Art/Map (written by scripts/map/render.sh).
    @MainActor
    static func load() -> (GameMap, PDFDocument)? {
        guard let json = Artwork.url("Map/planetfall-map.json"), let pdf = Artwork.url("Map/planetfall-map.pdf"),
              let map = GameMap.load(from: json), let document = PDFDocument(url: pdf) else { return nil }
        return (map, document)
    }
}

/// Lets the SwiftUI buttons drive the scroll view's zoom.
@MainActor
final class MapZoom {
    fileprivate weak var scrollView: MapScrollView?

    func zoom(by factor: CGFloat) { scrollView?.zoom(by: factor) }
    func fit() { scrollView?.fitWholeMap() }
}

private struct ZoomableMap: NSViewRepresentable {
    let map: GameMap
    let document: PDFDocument
    let here: String?
    let zoom: MapZoom

    func makeNSView(context: Context) -> MapScrollView {
        let canvas = MapCanvas(map: map, page: document.page(at: 0))
        canvas.here = here
        let scrollView = MapScrollView(canvas: canvas)
        zoom.scrollView = scrollView
        return scrollView
    }

    func updateNSView(_ scrollView: MapScrollView, context: Context) {
        scrollView.canvas.here = here
    }
}

/// Scrolls and magnifies the map. Magnifying redraws the vector map, so it stays sharp.
fileprivate final class MapScrollView: NSScrollView {
    let canvas: MapCanvas
    private var placedInitially = false

    init(canvas: MapCanvas) {
        self.canvas = canvas
        super.init(frame: .zero)
        documentView = canvas
        hasVerticalScroller = true
        hasHorizontalScroller = true
        autohidesScrollers = true
        allowsMagnification = true
        maxMagnification = 4
        backgroundColor = MapCanvas.paper
        drawsBackground = true
    }

    required init?(coder: NSCoder) { nil }

    /// Small enough to see the whole map, but never larger than actual size.
    private var fitMagnification: CGFloat {
        guard canvas.frame.width > 0, bounds.width > 0 else { return 1 }
        return min(bounds.width / canvas.frame.width, bounds.height / canvas.frame.height, 1)
    }

    override func layout() {
        super.layout()
        minMagnification = fitMagnification
        guard !placedInitially, bounds.width > 0 else { return }
        placedInitially = true
        // Open at a readable size, centered on the player.
        magnification = max(fitMagnification, 1.4)
        center(on: canvas.markerCenter ?? CGPoint(x: canvas.frame.midX, y: canvas.frame.midY))
    }

    func zoom(by factor: CGFloat) {
        let visible = contentView.bounds
        setMagnification(magnification * factor, centeredAt: CGPoint(x: visible.midX, y: visible.midY))
    }

    func fitWholeMap() {
        magnification = fitMagnification
        center(on: CGPoint(x: canvas.frame.midX, y: canvas.frame.midY))
    }

    /// Scrolls so `point` (in map coordinates) is in the middle of the view.
    func center(on point: CGPoint) {
        let size = contentView.bounds.size
        contentView.scroll(to: CGPoint(x: point.x - size.width / 2, y: point.y - size.height / 2))
        reflectScrolledClipView(contentView)
    }

    /// ⌘- or ⌥-scrolling zooms around the pointer (for a mouse, which can't pinch); plain
    /// scrolling moves around.
    override func scrollWheel(with event: NSEvent) {
        guard !event.modifierFlags.intersection([.command, .option]).isEmpty else { return super.scrollWheel(with: event) }
        let delta = event.hasPreciseScrollingDeltas ? event.scrollingDeltaY * 0.01 : event.scrollingDeltaY * 0.1
        let point = canvas.convert(event.locationInWindow, from: nil)
        setMagnification(magnification * exp(delta), centeredAt: point)
    }
}

/// Draws the map page and the "you are here" star. Dragging moves the map.
fileprivate final class MapCanvas: NSView {
    static let paper = NSColor(red: 0.965, green: 0.945, blue: 0.894, alpha: 1)
    private static let red = NSColor(red: 0.84, green: 0.165, blue: 0.118, alpha: 1)

    let map: GameMap
    let page: PDFPage?
    var here: String? {
        didSet { if here != oldValue { needsDisplay = true } }
    }
    private var dragStart: (mouse: CGPoint, origin: CGPoint)?

    init(map: GameMap, page: PDFPage?) {
        self.map = map
        self.page = page
        super.init(frame: CGRect(origin: .zero, size: page?.bounds(for: .mediaBox).size ?? CGSize(width: 1000, height: 500)))
    }

    required init?(coder: NSCoder) { nil }

    // Top-left origin, like the map's own coordinates.
    override var isFlipped: Bool { true }

    /// Points per map pixel (the PDF keeps the map's proportions).
    private var scale: CGFloat { bounds.width / map.width }

    /// The middle of the marker, in this view's coordinates.
    var markerCenter: CGPoint? {
        guard let here, let room = map.rooms[here] else { return nil }
        let inset = map.marker.inset * scale
        return CGPoint(x: (room.x + room.w) * map.width * scale - inset,
                       y: (room.y + room.h) * map.height * scale - inset)
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        Self.paper.setFill()
        dirtyRect.fill()
        if let page {
            context.saveGState()
            context.translateBy(x: 0, y: bounds.height)
            context.scaleBy(x: 1, y: -1)
            page.draw(with: .mediaBox, to: context)
            context.restoreGState()
        }
        if let center = markerCenter { drawMarker(at: center, radius: map.marker.radius * scale) }
    }

    /// A red disc with a white five-pointed star, matching the static map's.
    private func drawMarker(at center: CGPoint, radius r: CGFloat) {
        let disc = NSBezierPath(ovalIn: CGRect(x: center.x - r, y: center.y - r, width: 2 * r, height: 2 * r))
        Self.red.setFill()
        disc.fill()
        NSColor.white.setStroke()
        disc.lineWidth = 1.2 * scale
        disc.stroke()
        let star = NSBezierPath()
        for i in 0..<10 {
            let angle = (-90 + 36 * CGFloat(i)) * .pi / 180
            let radius = r * (i.isMultiple(of: 2) ? 0.66 : 0.27)
            let point = CGPoint(x: center.x + radius * cos(angle), y: center.y + radius * sin(angle) + r * 0.04)
            if i == 0 { star.move(to: point) } else { star.line(to: point) }
        }
        star.close()
        NSColor.white.setFill()
        star.fill()
    }

    override func resetCursorRects() {
        addCursorRect(visibleRect, cursor: dragStart == nil ? .openHand : .closedHand)
    }

    override func mouseDown(with event: NSEvent) {
        guard let clip = enclosingScrollView?.contentView else { return }
        dragStart = (event.locationInWindow, clip.bounds.origin)
        window?.invalidateCursorRects(for: self)
    }

    override func mouseDragged(with event: NSEvent) {
        guard let start = dragStart, let scrollView = enclosingScrollView else { return }
        let magnification = scrollView.magnification
        let dx = (event.locationInWindow.x - start.mouse.x) / magnification
        let dy = (event.locationInWindow.y - start.mouse.y) / magnification
        // The window's y grows upward; this view's grows downward.
        scrollView.contentView.scroll(to: CGPoint(x: start.origin.x - dx, y: start.origin.y + dy))
        scrollView.reflectScrolledClipView(scrollView.contentView)
    }

    override func mouseUp(with event: NSEvent) {
        dragStart = nil
        window?.invalidateCursorRects(for: self)
    }
}
