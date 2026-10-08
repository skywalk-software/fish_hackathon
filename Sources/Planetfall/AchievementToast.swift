import PlanetfallEngine
import SwiftUI

/// "Achievement unlocked" banner over the top-left of the room art. Shown for every new
/// achievement, whether or not SNARK-9's commentary is on. Click to dismiss.
struct AchievementToast: View {
    let achievement: Achievement
    let onDismiss: () -> Void

    var body: some View {
        Button(action: onDismiss) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "rosette")
                    .font(.system(size: 28, weight: .semibold))
                    .foregroundStyle(Theme.accent)
                VStack(alignment: .leading, spacing: 4) {
                    Text(verbatim: "ACHIEVEMENT UNLOCKED")
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .foregroundStyle(Theme.accent)
                    Text(verbatim: achievement.title)
                        .font(.system(size: 17, weight: .semibold, design: .monospaced))
                        .foregroundStyle(Theme.text)
                    Text(verbatim: achievement.description)
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(Theme.text.opacity(0.8))
                        .fixedSize(horizontal: false, vertical: true)
                    if let iconID = achievement.unlocksIcon {
                        HStack(spacing: 8) {
                            if let icon = Artwork.dockIcon(iconID) {
                                Image(nsImage: icon)
                                    .resizable()
                                    .frame(width: 36, height: 36)
                            }
                            Text(verbatim: "New Dock icon unlocked. Choose it in Settings (⌘,).")
                                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                                .foregroundStyle(Theme.accent)
                        }
                        .padding(.top, 4)
                    }
                }
            }
            .padding(14)
            .frame(width: 340, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 12).fill(Theme.background.opacity(0.92)))
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Theme.accent, lineWidth: 2))
            .shadow(color: .black.opacity(0.6), radius: 12, y: 4)
        }
        .buttonStyle(.plain)
        .help("Dismiss")
        .accessibilityElement(children: .combine)
    }
}
