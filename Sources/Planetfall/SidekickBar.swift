import PlanetfallEngine
import SwiftUI

/// The sidekick's live commentary, in its own strip above the command line so it never
/// covers game text. Their line types in as Claude streams it.
struct SidekickBar: View {
    let sidekick: Sidekick
    /// Called when the avatar is clicked, to show it close up.
    var onShowAvatar: () -> Void = {}

    /// Big enough to make out SNARK-9's face, like a streamer's facecam.
    static let avatarSize: CGFloat = 80

    var body: some View {
        // Centered so the caption sits beside the avatar's face rather than its top edge.
        HStack(alignment: .center, spacing: 16) {
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
        .padding(.vertical, 12)
        .background(Color.white.opacity(0.04))
        .animation(.easeOut(duration: 0.15), value: sidekick.line)
    }

    /// Only what SNARK-9 is saying right now (or an error). Blank while it waits, thinks,
    /// or passes; the avatar's pulse shows when it's thinking.
    @ViewBuilder
    private var caption: some View {
        if let error = sidekick.errorMessage, !sidekick.isThinking, sidekick.line.isEmpty {
            Text(verbatim: error).foregroundStyle(Theme.dim).italic()
        } else {
            Text(verbatim: sidekick.line).foregroundStyle(Theme.text)
        }
    }

    @ViewBuilder
    private var avatar: some View {
        if Artwork.character(sidekick.persona.artID) != nil {
            Button(action: onShowAvatar) { avatarImage }
                .buttonStyle(.plain)
                .help("Show \(sidekick.persona.name) close up")
        } else {
            avatarImage
        }
    }

    private var avatarImage: some View {
        Group {
            if let image = Artwork.character(sidekick.persona.artID) {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                Image(systemName: "eye.trianglebadge.exclamationmark")
                    .font(.system(size: 36))
                    .foregroundStyle(Theme.background)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Theme.accent)
            }
        }
        .frame(width: Self.avatarSize, height: Self.avatarSize)
        .clipShape(Circle())
        .overlay(Circle().strokeBorder(Theme.accent, lineWidth: 2))
        .contentShape(Circle())
        // A pulse while thinking, like a streamer's mic light.
        .opacity(sidekick.isThinking ? 0.7 : 1)
        .animation(sidekick.isThinking ? .easeInOut(duration: 0.6).repeatForever() : .default,
                   value: sidekick.isThinking)
        .accessibilityLabel(sidekick.persona.name)
    }
}
