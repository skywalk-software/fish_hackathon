import PlanetfallEngine
import SwiftUI

/// The sidekick's live commentary, in its own strip above the command line so it never
/// covers game text. Their line types in as Claude streams it.
struct SidekickBar: View {
    let sidekick: Sidekick

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            avatar
            VStack(alignment: .leading, spacing: 3) {
                Text(verbatim: sidekick.persona.name)
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundStyle(Theme.accent)
                caption
                    .font(.system(size: 14, design: .monospaced))
                    // Quips are a sentence or two. A cap (instead of fixedSize) also keeps a
                    // long quip from inflating the window's minimum height.
                    .lineLimit(4)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color.white.opacity(0.04))
        .animation(.easeOut(duration: 0.15), value: sidekick.line)
    }

    @ViewBuilder
    private var caption: some View {
        if let error = sidekick.errorMessage, !sidekick.isThinking {
            Text(verbatim: error).foregroundStyle(Theme.dim).italic()
        } else if sidekick.line.isEmpty {
            Text(verbatim: sidekick.isThinking ? "…" : "Watching. Judging.")
                .foregroundStyle(Theme.dim)
        } else {
            Text(verbatim: sidekick.line)
                .foregroundStyle(Theme.text)
                // Dim the previous quip while the next one is being written.
                .opacity(sidekick.isThinking ? 0.55 : 1)
        }
    }

    @ViewBuilder
    private var avatar: some View {
        Group {
            if let image = Artwork.character(sidekick.persona.artID) {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                Image(systemName: "eye.trianglebadge.exclamationmark")
                    .font(.system(size: 18))
                    .foregroundStyle(Theme.background)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Theme.accent)
            }
        }
        .frame(width: 40, height: 40)
        .clipShape(Circle())
        .overlay(Circle().strokeBorder(Theme.accent, lineWidth: 1.5))
        // A pulse while thinking, like a streamer's mic light.
        .opacity(sidekick.isThinking ? 0.7 : 1)
        .animation(sidekick.isThinking ? .easeInOut(duration: 0.6).repeatForever() : .default,
                   value: sidekick.isThinking)
        .accessibilityLabel(sidekick.persona.name)
    }
}
