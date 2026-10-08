import PlanetfallEngine
import SwiftUI

/// Planetfall ▸ Settings… (⌘,): the Dock icon and achievements.
struct SettingsView: View {
    let dockIcons: DockIconSettings
    let achievements: AchievementStore

    var body: some View {
        TabView {
            DockIconTab(dockIcons: dockIcons)
                .tabItem { Label("Dock Icon", systemImage: "app.dashed") }
            AchievementsTab(achievements: achievements)
                .tabItem { Label("Achievements", systemImage: "rosette") }
            UsageTab()
                .tabItem { Label("Usage", systemImage: "gauge.with.dots.needle.33percent") }
        }
        .frame(width: 620, height: 520)
    }
}

// MARK: - Dock icon

private struct DockIconTab: View {
    let dockIcons: DockIconSettings
    @State private var previewing: DockIcon?

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Choose the icon Planetfall shows in the Dock. Click an icon to see it full size.")
                .foregroundStyle(.secondary)
            HStack(alignment: .top, spacing: 28) {
                ForEach(DockIcon.all) { icon in
                    Button { previewing = icon } label: {
                        DockIconCard(icon: icon,
                                     isUnlocked: dockIcons.isUnlocked(icon),
                                     isCurrent: dockIcons.current == icon)
                    }
                    .buttonStyle(.plain)
                }
            }
            Spacer()
            Text("Only the Dock icon changes; the app's icon in Finder stays the same.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .sheet(item: $previewing) { icon in
            DockIconPreview(icon: icon, dockIcons: dockIcons) { previewing = nil }
        }
    }
}

private struct DockIconCard: View {
    let icon: DockIcon
    let isUnlocked: Bool
    let isCurrent: Bool

    var body: some View {
        VStack(spacing: 10) {
            ZStack {
                if let image = Artwork.dockIcon(icon.id) {
                    Image(nsImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .saturation(isUnlocked ? 1 : 0)
                        .opacity(isUnlocked ? 1 : 0.45)
                }
                if !isUnlocked {
                    Image(systemName: "lock.fill")
                        .font(.system(size: 30))
                        .foregroundStyle(.white)
                        .shadow(radius: 4)
                }
            }
            .frame(width: 160, height: 160)
            .padding(6)
            .background(RoundedRectangle(cornerRadius: 14)
                .strokeBorder(isCurrent ? Theme.accent : .clear, lineWidth: 3))

            Text(icon.name).font(.headline)
            status.font(.caption)
        }
        .frame(width: 180)
        .contentShape(Rectangle())
        .help(isUnlocked ? "Preview \(icon.name)" : "Preview this locked icon")
    }

    @ViewBuilder
    private var status: some View {
        if isCurrent {
            Label("In the Dock", systemImage: "checkmark.circle.fill").foregroundStyle(Theme.accent)
        } else if isUnlocked {
            Text("Unlocked").foregroundStyle(.secondary)
        } else if let achievement = icon.unlockedBy {
            Text("Earn “\(achievement.title)” to unlock")
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
    }
}

/// The icon at full size, with a button to put it in the Dock.
private struct DockIconPreview: View {
    let icon: DockIcon
    let dockIcons: DockIconSettings
    let onClose: () -> Void

    var body: some View {
        let isUnlocked = dockIcons.isUnlocked(icon)
        VStack(spacing: 16) {
            if let image = Artwork.dockIcon(icon.id) {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 512, height: 512)
            }
            Text(icon.name).font(.title2.weight(.semibold))
            if !isUnlocked, let achievement = icon.unlockedBy {
                Label("Locked. Earn the “\(achievement.title)” achievement to use this icon.",
                      systemImage: "lock.fill")
                    .foregroundStyle(.secondary)
            }
            HStack {
                Button("Close", action: onClose)
                    .keyboardShortcut(.cancelAction)
                Button(dockIcons.current == icon ? "In the Dock" : "Use as Dock Icon") {
                    dockIcons.select(icon)
                    onClose()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!isUnlocked || dockIcons.current == icon)
            }
        }
        .padding(24)
    }
}

// MARK: - Achievements

private struct AchievementsTab: View {
    let achievements: AchievementStore
    @State private var confirmingReset = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            List(Achievement.all) { achievement in
                AchievementRow(achievement: achievement, earnedAt: achievements.earned[achievement.id])
            }
            .listStyle(.inset)
            HStack {
                Text("\(achievements.earned.count) of \(Achievement.all.count) earned")
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Reset Achievements…") { confirmingReset = true }
                    .disabled(achievements.earned.isEmpty)
            }
        }
        .padding(24)
        .confirmationDialog("Reset all achievements?", isPresented: $confirmingReset) {
            Button("Reset", role: .destructive) { achievements.reset() }
        } message: {
            Text("Earned achievements and the icons they unlocked will be locked again. Useful for demos.")
        }
    }
}

private struct AchievementRow: View {
    let achievement: Achievement
    let earnedAt: Date?

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "rosette")
                .font(.system(size: 22))
                .foregroundStyle(earnedAt == nil ? Color.secondary : Theme.accent)
                .opacity(earnedAt == nil ? 0.5 : 1)
            VStack(alignment: .leading, spacing: 3) {
                Text(achievement.title).font(.headline)
                // Locked achievements stay mysterious, so the list doesn't spoil the story.
                Text(earnedAt == nil ? "???" : achievement.description)
                    .foregroundStyle(.secondary)
                if let earnedAt {
                    Text("Earned \(earnedAt.formatted(date: .abbreviated, time: .shortened))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if achievement.unlocksIcon != nil {
                    Label(earnedAt == nil ? "Unlocks a Dock icon" : "Unlocked a Dock icon", systemImage: "app.badge")
                        .font(.caption)
                        .foregroundStyle(earnedAt == nil ? Color.secondary : Theme.accent)
                }
            }
        }
        .padding(.vertical, 4)
    }
}
