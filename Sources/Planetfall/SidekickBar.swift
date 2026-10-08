import PlanetfallEngine
import SwiftUI

/// The sidekick's live commentary, in its own strip above the command line so it never
/// covers game text. Their line types in as Claude streams it.
struct SidekickBar: View {
    let sidekick: Sidekick
    /// How bright his lens glows (follows the loudness of his voice), 0 when he's quiet.
    var glow: Double = 0
    /// Called when the avatar is clicked, to show it close up.
    var onShowAvatar: () -> Void = {}

    /// Big enough to make out SNARK-9's face, like a streamer's facecam.
    static let avatarSize: CGFloat = 80

    @State private var showingChat = false

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
            Button { showingChat.toggle() } label: {
                Image(systemName: "bubble.left.and.text.bubble.right")
                    .font(.system(size: 18))
                    .foregroundStyle(Theme.accent)
                    .padding(6)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Show \(sidekick.persona.name)'s earlier comments")
            .accessibilityLabel("\(sidekick.persona.name)'s comments")
            .popover(isPresented: $showingChat, arrowEdge: .top) {
                SidekickChatView(sidekick: sidekick)
            }
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
                TalkingPortrait(image: image, jaw: nil,
                                glow: PortraitGlow.byCharacter[sidekick.persona.artID], openness: glow)
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

/// SNARK-9's earlier comments as a chat: the player's commands on the right, SNARK-9's quips
/// on the left, oldest at the top. Opens scrolled to the latest.
struct SidekickChatView: View {
    let sidekick: Sidekick

    var body: some View {
        VStack(spacing: 0) {
            Text(verbatim: "\(sidekick.persona.name)'s commentary")
                .font(.system(size: 13, weight: .bold, design: .monospaced))
                .foregroundStyle(Theme.accent)
                .padding(.vertical, 10)
            Divider()
            if sidekick.chat.isEmpty {
                Text(verbatim: "Nothing yet. Make a move.")
                    .font(.system(size: 13, design: .monospaced))
                    .foregroundStyle(Theme.dim)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 10) {
                            ForEach(sidekick.chat) { entry in
                                ChatBubble(entry: entry, avatar: Artwork.character(sidekick.persona.artID))
                                    .id(entry.id)
                            }
                        }
                        .padding(14)
                    }
                    .defaultScrollAnchor(.bottom)
                    .onAppear { proxy.scrollTo(sidekick.chat.last?.id, anchor: .bottom) }
                    .onChange(of: sidekick.chat.last?.id) { _, last in
                        withAnimation { proxy.scrollTo(last, anchor: .bottom) }
                    }
                }
            }
        }
        .frame(width: 440, height: 520)
        .background(Theme.background)
        .preferredColorScheme(.dark)
    }
}

private struct ChatBubble: View {
    let entry: SidekickChatEntry
    let avatar: NSImage?

    var body: some View {
        HStack(alignment: .bottom, spacing: 8) {
            if entry.speaker == .player {
                Spacer(minLength: 60)
                bubble
            } else {
                Group {
                    if let avatar {
                        Image(nsImage: avatar).resizable().aspectRatio(contentMode: .fill)
                    } else {
                        Theme.accent
                    }
                }
                .frame(width: 26, height: 26)
                .clipShape(Circle())
                bubble
                Spacer(minLength: 60)
            }
        }
    }

    private var bubble: some View {
        Text(verbatim: entry.speaker == .player ? "> \(entry.text)" : entry.text)
            .font(.system(size: 13, design: .monospaced))
            .foregroundStyle(entry.speaker == .player ? Theme.background : Theme.text)
            .textSelection(.enabled)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(RoundedRectangle(cornerRadius: 12)
                .fill(entry.speaker == .player ? Theme.accent : Color.white.opacity(0.08)))
    }
}
