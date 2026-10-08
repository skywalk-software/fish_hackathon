import AppKit
import PlanetfallEngine
import SwiftUI

/// The transcript as one selectable NSTextView. SwiftUI's `.textSelection` can't change
/// highlight colors, and its system highlight made amber text hard to read; this one
/// inverts selected text (dark on amber). Selection can also span several entries.
struct TranscriptTextView: NSViewRepresentable {
    let entries: [TranscriptEntry]

    final class Coordinator {
        var renderedIDs: [Int] = []
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> BottomPinnedScrollView {
        // A TextKit 1 stack so we can draw the selection ourselves (see InvertedSelectionTextView).
        let storage = NSTextStorage()
        let layoutManager = InvertedSelectionLayoutManager()
        storage.addLayoutManager(layoutManager)
        let container = NSTextContainer(size: NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude))
        layoutManager.addTextContainer(container)
        let textView = InvertedSelectionTextView(frame: .zero, textContainer: container)
        textView.isEditable = false
        textView.isSelectable = true
        textView.drawsBackground = false
        textView.textContainerInset = NSSize(width: 12, height: 16)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: .greatestFiniteMagnitude)
        textView.textContainer?.widthTracksTextView = true
        textView.selectedTextAttributes = Theme.invertedSelection

        let scrollView = BottomPinnedScrollView()
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.documentView = textView
        return scrollView
    }

    func updateNSView(_ scrollView: BottomPinnedScrollView, context: Context) {
        guard let textView = scrollView.documentView as? NSTextView,
              let storage = textView.textStorage else { return }
        let ids = entries.map(\.id)
        let rendered = context.coordinator.renderedIDs
        guard ids != rendered else { return }

        // Usually entries were only appended, so append just those to keep the
        // reader's selection. Anything else (a restart) redraws everything.
        if ids.starts(with: rendered), !rendered.isEmpty {
            storage.append(Self.render(entries.dropFirst(rendered.count), leadingSeparator: true))
        } else {
            storage.setAttributedString(Self.render(entries[...], leadingSeparator: false))
        }
        context.coordinator.renderedIDs = ids
        scrollView.scrollToBottom()
    }

    private static func render(_ entries: ArraySlice<TranscriptEntry>, leadingSeparator: Bool) -> NSAttributedString {
        let result = NSMutableAttributedString()
        for (index, entry) in entries.enumerated() {
            // A blank line between entries, like the game's own paragraph breaks.
            if leadingSeparator || index > 0 {
                result.append(NSAttributedString(string: "\n\n", attributes: Theme.narrationAttributes))
            }
            switch entry {
            case .narration(_, let text):
                result.append(NSAttributedString(string: text, attributes: Theme.narrationAttributes))
            case .command(_, let text):
                result.append(NSAttributedString(string: "> \(text)", attributes: Theme.commandAttributes))
            case .system(_, let text):
                result.append(NSAttributedString(string: text, attributes: Theme.systemAttributes))
            }
        }
        return result
    }
}

/// Draws selected text inverted (dark on amber) whether or not the view has focus.
/// By default an unfocused NSTextView draws selections light grey and keeps the text's
/// own color, which made cream-on-grey unreadable.
final class InvertedSelectionTextView: NSTextView {
    /// Only a click focuses the transcript (to select text). Otherwise AppKit would make it the
    /// window's first focused view at launch, and typing or space wouldn't reach the command line.
    override var acceptsFirstResponder: Bool {
        guard let event = NSApp.currentEvent else { return false }
        return [.leftMouseDown, .rightMouseDown, .otherMouseDown].contains(event.type)
    }

    override func setSelectedRanges(_ ranges: [NSValue], affinity: NSSelectionAffinity, stillSelecting: Bool) {
        super.setSelectedRanges(ranges, affinity: affinity, stillSelecting: stillSelecting)
        guard let layoutManager, let length = textStorage?.length else { return }
        // Temporary attributes recolor the selected text without touching the transcript.
        layoutManager.removeTemporaryAttribute(.foregroundColor, forCharacterRange: NSRange(location: 0, length: length))
        for range in selectedRanges.map(\.rangeValue) where range.length > 0 {
            layoutManager.addTemporaryAttribute(.foregroundColor, value: NSColor(Theme.background), forCharacterRange: range)
        }
    }
}

/// Paints the selection highlight amber in every state. The transcript has no other
/// background colors, so every background fill here is the selection.
final class InvertedSelectionLayoutManager: NSLayoutManager {
    override func fillBackgroundRectArray(_ rectArray: UnsafePointer<NSRect>, count rectCount: Int,
                                          forCharacterRange charRange: NSRange, color: NSColor) {
        // AppKit fills with the current graphics color; `color` is only informational.
        let amber = NSColor(Theme.accent)
        amber.setFill()
        super.fillBackgroundRectArray(rectArray, count: rectCount, forCharacterRange: charRange, color: amber)
    }
}

/// Keeps the newest text in view: new entries scroll to the end, and so does a resize
/// (e.g. the room art panel appearing) unless the reader has scrolled up to read back.
final class BottomPinnedScrollView: NSScrollView {
    /// Whether to stay at the bottom. Starts true; follows the reader's scrolling.
    private var sticksToBottom = true

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        contentView.postsBoundsChangedNotifications = true
        NotificationCenter.default.addObserver(
            self, selector: #selector(contentBoundsDidChange),
            name: NSView.boundsDidChangeNotification, object: contentView)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    private var isAtBottom: Bool {
        guard let documentView else { return true }
        return contentView.bounds.maxY >= documentView.frame.height - 4
    }

    @objc private func contentBoundsDidChange() {
        sticksToBottom = isAtBottom
    }

    override func setFrameSize(_ newSize: NSSize) {
        let stick = sticksToBottom
        super.setFrameSize(newSize)
        if stick { scrollToBottom() }
    }

    func scrollToBottom() {
        guard let textView = documentView as? NSTextView else { return }
        if let container = textView.textContainer {
            textView.layoutManager?.ensureLayout(for: container)
        }
        textView.scrollToEndOfDocument(nil)
        sticksToBottom = true
    }
}

/// Gives the command box the same inverted selection. SwiftUI text fields edit with
/// their own field editor (not the window's shared one), so we restyle whichever
/// field editor in this window reports a selection change.
struct InvertedFieldSelection: NSViewRepresentable {
    final class Probe: NSView {
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            NotificationCenter.default.removeObserver(self, name: NSTextView.didChangeSelectionNotification, object: nil)
            guard window != nil else { return }
            NotificationCenter.default.addObserver(
                self, selector: #selector(selectionDidChange(_:)),
                name: NSTextView.didChangeSelectionNotification, object: nil)
        }

        @objc private func selectionDidChange(_ note: Notification) {
            guard let editor = note.object as? NSTextView, editor.isFieldEditor,
                  editor.window === window else { return }
            editor.selectedTextAttributes = Theme.invertedSelection
        }
    }

    func makeNSView(context: Context) -> Probe { Probe() }
    func updateNSView(_ nsView: Probe, context: Context) {}
}

@MainActor
extension Theme {
    static let nsFont = NSFont.monospacedSystemFont(ofSize: 14, weight: .regular)

    static let narrationAttributes: [NSAttributedString.Key: Any] = [
        .font: nsFont, .foregroundColor: NSColor(text),
    ]
    static let commandAttributes: [NSAttributedString.Key: Any] = [
        .font: nsFont, .foregroundColor: NSColor(accent),
    ]
    static let systemAttributes: [NSAttributedString.Key: Any] = [
        .font: NSFontManager.shared.convert(nsFont, toHaveTrait: .italicFontMask),
        .foregroundColor: NSColor(dim),
    ]

    /// Selected text: the background color on amber, the reverse of normal text.
    static let invertedSelection: [NSAttributedString.Key: Any] = [
        .backgroundColor: NSColor(accent),
        .foregroundColor: NSColor(background),
    ]
}
