import AppKit
import PlanetfallEngine
import SwiftUI
import WebKit

/// The map, over everything but the command line (so the player can keep playing with it open):
/// what the player has explored ("map") or the whole map ("cheat: map"), both opening zoomed all
/// the way out. Zoom with a pinch, ⌘-scroll, the buttons,
/// or ⌘+ / ⌘- / ⌘0; drag or scroll to move around. A red star marks the player's room.
///
/// The map is Art/Map/planetfall-map.svg (from scripts/map), shown by WebKit so it looks exactly
/// like the printed map. Its rooms, links, and regions are tagged (`data-room`, `data-link`...),
/// so the explored map just hides what the player hasn't seen, plus every hint (`.clue`).
struct MapOverlay: View {
    let svg: String
    let mode: GameSession.MapMode
    let visited: Set<String>
    let here: String?
    let onClose: () -> Void

    @State private var zoom = MapZoom()

    var body: some View {
        ZStack {
            Color.black.opacity(0.92)
                .ignoresSafeArea()
            MapWebView(svg: svg, state: MapWebView.State(mode: mode, visited: visited, here: here), zoom: zoom)
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
            zoomButton("minus", help: "Zoom out (⌘-)", key: "-") { zoom.run("zoomBy(1 / 1.4)") }
            Divider().frame(height: 18)
            zoomButton("plus", help: "Zoom in (⌘+)", key: "=") { zoom.run("zoomBy(1.4)") }
            Divider().frame(height: 18)
            zoomButton("arrow.up.left.and.arrow.down.right", help: "Show the whole map (⌘0)", key: "0") {
                zoom.run("fitWholeMap()")
            }
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

    /// The tagged map SVG from Art/Map (written by scripts/map/render.sh).
    @MainActor
    static func loadSVG() -> String? {
        Artwork.url("Map/planetfall-map.svg").flatMap { try? String(contentsOf: $0, encoding: .utf8) }
    }
}

/// Lets the SwiftUI buttons drive the page's zoom.
@MainActor
final class MapZoom {
    fileprivate weak var webView: WKWebView?

    func run(_ script: String) { webView?.evaluateJavaScript(script) }
}

private struct MapWebView: NSViewRepresentable {
    let svg: String
    let state: State
    let zoom: MapZoom

    struct State: Equatable {
        var mode: GameSession.MapMode
        var visited: Set<String>
        var here: String?

        /// The page's `show(...)` call for this state.
        var script: String {
            let rooms = (try? JSONEncoder().encode(visited.sorted())).flatMap { String(data: $0, encoding: .utf8) } ?? "[]"
            let room = (try? JSONEncoder().encode(here)).flatMap { String(data: $0, encoding: .utf8) } ?? "null"
            return "show('\(mode == .full ? "full" : "explored")', \(rooms), \(room))"
        }
    }

    func makeNSView(context: Context) -> WKWebView {
        let webView = WKWebView(frame: .zero, configuration: WKWebViewConfiguration())
        webView.navigationDelegate = context.coordinator
        webView.underPageBackgroundColor = NSColor(red: 0.965, green: 0.945, blue: 0.894, alpha: 1)
        webView.setValue(false, forKey: "drawsBackground")
        webView.loadHTMLString(Self.page(svg: svg), baseURL: nil)
        zoom.webView = webView
        context.coordinator.pending = state
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        context.coordinator.apply(state, to: webView)
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    @MainActor
    final class Coordinator: NSObject, WKNavigationDelegate {
        var pending: State?
        private var loaded = false
        private var shown: State?

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            loaded = true
            if let pending { apply(pending, to: webView) }
            webView.evaluateJavaScript("openView()")
        }

        func apply(_ state: State, to webView: WKWebView) {
            guard loaded else { pending = state; return }
            guard state != shown else { return }
            shown = state
            webView.evaluateJavaScript(state.script)
        }
    }

    /// The SVG in a page that scales it (redrawn as vectors, so sharp at any zoom), pans by
    /// dragging, and shows or hides its tagged parts.
    static func page(svg: String) -> String {
        """
        <!doctype html><html><head><meta charset="utf-8"><style>
        html, body { margin: 0; background: #f6f1e4; -webkit-user-select: none; user-select: none; cursor: grab; }
        /* A map smaller than the window sits in the middle of it. */
        body { display: flex; min-width: 100vw; min-height: 100vh; }
        body.dragging { cursor: grabbing; }
        svg { display: block; margin: auto; flex: none; }
        .explored .clue, .explored .chrome { display: none; }
        /* Story-gated passages look like any other on the explored map (purple would be a hint). */
        .explored .story-line { stroke: #1f2a44; }
        .explored .story-line[marker-end] { marker-end: url(#arrow); }
        </style></head><body>
        \(svg)
        <script>
        const svg = document.querySelector('svg');
        const FULL_W = +svg.getAttribute('width'), FULL_H = +svg.getAttribute('height');
        // The size of the part being shown: all of it, or (explored) a crop around what's been seen.
        let W = FULL_W, H = FULL_H;
        const INSET = 11, RADIUS = 8.5, PAD = 40;
        // The rooms and links are drawn inside a translate(x, y) group.
        const [OX, OY] = (svg.querySelector('g[transform]').getAttribute('transform').match(/[-\\d.]+/g) || [0, 0]).map(Number);
        let scale = 1;
        const fitScale = () => Math.min(innerWidth / W, innerHeight / H, 1);

        // Zoom to s, keeping the map point under (cx, cy) in the window where it is.
        function setScale(s, cx, cy) {
          s = Math.max(fitScale(), Math.min(4, s));
          const x = (scrollX + cx) / scale, y = (scrollY + cy) / scale;
          scale = s;
          svg.setAttribute('width', W * s);
          svg.setAttribute('height', H * s);
          scrollTo(x * s - cx, y * s - cy);
        }
        function zoomBy(f) { setScale(scale * f, innerWidth / 2, innerHeight / 2); }
        function fitWholeMap() { setScale(fitScale(), 0, 0); scrollTo(0, 0); }
        // Both maps open zoomed all the way out: everything explored, or the whole map.
        function openView() { fitWholeMap(); }

        // Everything ("full"), or only explored rooms and the links, rides and regions between them.
        function show(mode, visited, room) {
          const seen = new Set(visited), explored = mode === 'explored';
          document.body.classList.toggle('explored', explored);
          const set = (el, on) => { el.style.display = on ? '' : 'none'; };
          document.querySelectorAll('[data-room]').forEach(el => set(el, !explored || seen.has(el.dataset.room)));
          document.querySelectorAll('[data-link]').forEach(el => {
            whole(el);
            if (!explored) return set(el, true);
            const [a, b] = el.dataset.link.split(' ');
            if (seen.has(a) && seen.has(b)) return set(el, true);
            // An exit from a room the player has seen, to one they haven't: just its start, so they
            // know they can go that way but not where it leads. (Rides only show once both ends are seen.)
            const from = seen.has(a) ? a : seen.has(b) ? b : null;
            set(el, from && !el.classList.contains('ride') && stub(el, from));
          });
          document.querySelectorAll('[data-region]').forEach(el =>
            set(el, !explored || el.dataset.rooms.split(' ').some(r => seen.has(r))));
          document.querySelectorAll('[data-any]').forEach(el => set(el, !explored || seen.has(el.dataset.any)));
          const here = document.getElementById('here');
          const box = room && document.querySelector(`[data-room="${room}"] rect`);
          let marker = null;
          if (box) {
            const x = +box.getAttribute('x') + +box.getAttribute('width') - INSET;
            const y = +box.getAttribute('y') + +box.getAttribute('height') - INSET;
            here.setAttribute('transform', `translate(${x} ${y})`);
            here.style.display = '';
            marker = { x: x - RADIUS, y: y - RADIUS, width: 2 * RADIUS, height: 2 * RADIUS };
          } else {
            here.style.display = 'none';
          }
          fitRegions(explored ? seen : null);
          crop(explored ? marker : null);
        }

        // How much of an exit's line shows before it fades into the unexplored.
        const STUB = 46;

        // Shows only the end of a link's line at `room`; false if it isn't an exit from there (a
        // one-way passage coming in). Remembers the visible part's box for cropping.
        function stub(el, room) {
          const path = el.querySelector('path');
          const len = path.getTotalLength(), box = roomBox(room);
          const c = { x: box.x + box.width / 2, y: box.y + box.height / 2 };
          const p0 = path.getPointAtLength(0), p1 = path.getPointAtLength(len);
          const fromStart = Math.hypot(p0.x - c.x, p0.y - c.y) <= Math.hypot(p1.x - c.x, p1.y - c.y);
          const oneWay = path.hasAttribute('marker-end') && !path.hasAttribute('marker-start');
          if (oneWay && !fromStart) return false;
          const shown = Math.min(len * 0.5, STUB);
          path.style.strokeDasharray = `${shown} ${len}`;
          path.style.strokeDashoffset = fromStart ? 0 : -(len - shown);
          path.style.markerEnd = path.style.markerStart = 'none';
          path.style.stroke = '#1f2a44';   // a locked (blue) or story (purple) color would be a hint
          // Keep an up/down tag at this end; hide the rest (gates, the far tag, labels).
          const near = fromStart ? p0 : p1;
          [...el.children].forEach(child => {
            if (child === path) return;
            const keep = child.tagName === 'text' &&
              Math.hypot(+child.getAttribute('x') - near.x, +child.getAttribute('y') - near.y) < shown + 12;
            if (!keep) child.style.display = 'none';
          });
          const points = [];
          for (let i = 0; i <= 8; i++) points.push(path.getPointAtLength(fromStart ? shown * i / 8 : len - shown * i / 8));
          el.stubBox = union(points.map(p => ({ x: p.x - 2, y: p.y - 2, width: 4, height: 4 })));
          el.stubFrom = room;
          return true;
        }
        // Undoes `stub`.
        function whole(el) {
          if (!el.stubBox) return;
          const path = el.querySelector('path');
          path.style.strokeDasharray = path.style.strokeDashoffset = path.style.markerEnd = path.style.markerStart = '';
          path.style.stroke = '';
          [...el.children].forEach(child => child.style.display = '');
          el.stubBox = el.stubFrom = null;
        }

        // A room's box, from its rect (in the translated group's coordinates).
        function roomBox(id) {
          const r = document.querySelector(`[data-room="${id}"] rect`);
          return r && { x: +r.getAttribute('x'), y: +r.getAttribute('y'), width: +r.getAttribute('width'), height: +r.getAttribute('height') };
        }
        function union(boxes) {
          boxes = boxes.filter(b => b && b.width + b.height > 0);
          if (!boxes.length) return null;
          const x0 = Math.min(...boxes.map(b => b.x)), y0 = Math.min(...boxes.map(b => b.y));
          const x1 = Math.max(...boxes.map(b => b.x + b.width)), y1 = Math.max(...boxes.map(b => b.y + b.height));
          return { x: x0, y: y0, width: x1 - x0, height: y1 - y0 };
        }

        // On the explored map each region's box hugs just the rooms seen in it; the full map
        // puts the boxes back.
        function fitRegions(seen) {
          document.querySelectorAll('[data-region]').forEach(g => {
            const rect = g.querySelector('rect'), title = g.querySelector('text');
            if (!g.dataset.box) g.dataset.box = JSON.stringify([rect.getAttribute('x'), rect.getAttribute('y'),
              rect.getAttribute('width'), rect.getAttribute('height'), title.getAttribute('x'), title.getAttribute('y')]);
            const [x, y, w, h, tx, ty] = JSON.parse(g.dataset.box);
            const inside = seen ? g.dataset.rooms.split(' ').filter(r => seen.has(r)) : [];
            const stubs = [...document.querySelectorAll('[data-link]')]
              .filter(el => el.stubBox && inside.includes(el.stubFrom)).map(el => el.stubBox);
            const rooms = inside.length ? union([...inside.map(roomBox), ...stubs]) : null;
            const b = rooms ? { x: rooms.x - 16, y: rooms.y - 30, w: rooms.width + 32, h: rooms.height + 46 }
                            : { x: +x, y: +y, w: +w, h: +h };
            rect.setAttribute('x', b.x); rect.setAttribute('y', b.y);
            rect.setAttribute('width', b.w); rect.setAttribute('height', b.h);
            title.setAttribute('x', rooms ? b.x + 12 : tx); title.setAttribute('y', rooms ? b.y + 19 : ty);
          });
        }

        // The explored map is only as big as what's been seen (plus a margin); the full map is all of it.
        function crop(marker) {
          let area = null;
          if (document.body.classList.contains('explored')) {
            const shown = [...document.querySelectorAll('[data-room], [data-link], [data-region], [data-any]')]
              .filter(el => el.style.display !== 'none').map(el => el.stubBox || el.getBBox());
            area = union(marker ? [...shown, marker] : shown);
          }
          if (area) {
            W = area.width + 2 * PAD; H = area.height + 2 * PAD;
            svg.setAttribute('viewBox', `${OX + area.x - PAD} ${OY + area.y - PAD} ${W} ${H}`);
          } else {
            W = FULL_W; H = FULL_H;
            svg.setAttribute('viewBox', `0 0 ${W} ${H}`);
          }
          setScale(scale, 0, 0);
        }

        // ⌘-, ⌥- or ctrl-scroll (and a pinch) zooms around the pointer; plain scrolling moves.
        addEventListener('wheel', e => {
          if (!(e.metaKey || e.altKey || e.ctrlKey)) return;
          e.preventDefault();
          setScale(scale * Math.exp(-e.deltaY * 0.01), e.clientX, e.clientY);
        }, { passive: false });
        let pinchFrom = 1;
        addEventListener('gesturestart', e => { e.preventDefault(); pinchFrom = scale; });
        addEventListener('gesturechange', e => { e.preventDefault(); setScale(pinchFrom * e.scale, e.clientX, e.clientY); });

        // Dragging moves the map.
        let drag = null;
        addEventListener('mousedown', e => { drag = { x: e.clientX, y: e.clientY }; document.body.classList.add('dragging'); });
        addEventListener('mousemove', e => {
          if (!drag) return;
          scrollBy(drag.x - e.clientX, drag.y - e.clientY);
          drag = { x: e.clientX, y: e.clientY };
        });
        addEventListener('mouseup', () => { drag = null; document.body.classList.remove('dragging'); });
        </script></body></html>
        """
    }
}
