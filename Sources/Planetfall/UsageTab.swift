import PlanetfallEngine
import SwiftUI

/// Settings > Usage: the Fish Audio credit left (read from Fish) and when it might run out, and
/// the app's own tally of Claude tokens (Anthropic doesn't let a key read its balance).
struct UsageTab: View {
    @State private var fish = FishCreditHistory.shared.latest
    @State private var fishError: String?
    @State private var loadingFish = false
    @State private var claude = ClaudeUsageLedger.shared.snapshot()
    @State private var confirmingReset = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                fishSection
                Divider()
                claudeSection
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .task { await refreshFish() }
        .onAppear { claude = ClaudeUsageLedger.shared.snapshot() }
        .confirmationDialog("Reset the Claude usage tally?", isPresented: $confirmingReset) {
            Button("Reset", role: .destructive) {
                ClaudeUsageLedger.shared.reset()
                claude = ClaudeUsageLedger.shared.snapshot()
            }
        }
    }

    // MARK: Fish

    private var fishSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Fish Audio credit").font(.headline)
                Spacer()
                if loadingFish { ProgressView().controlSize(.small) }
                Button("Refresh") { Task { await refreshFish() } }
                    .disabled(loadingFish)
            }
            if let fish {
                Text(verbatim: String(format: "$%.2f left of $%.2f", fish.balance, fish.totalTopUp))
                    .font(.system(size: 22, weight: .semibold, design: .rounded))
                ProgressView(value: fish.totalTopUp > 0 ? fish.balance / fish.totalTopUp : 0)
                    .tint(Theme.accent)
                Text(verbatim: "Checked \(fish.readAt.formatted(date: .abbreviated, time: .shortened))")
                    .font(.caption).foregroundStyle(.secondary)
                Text(verbatim: runOutText(fish))
                Text(verbatim: String(format: "That's about %.0f hours of push-to-talk speech recognition, at $0.36 an hour.",
                                      fish.balance / FishCredit.speechToTextPerHour))
                    .foregroundStyle(.secondary)
                Text(verbatim: "The voices use Fish's free text-to-speech model (no charge through Nov 30, 2026), so only push-to-talk and designing voices spend credit for now.")
                    .font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else if fishError == nil {
                Text(verbatim: "Checking…").foregroundStyle(.secondary)
            }
            if let fishError {
                Text(verbatim: fishError).foregroundStyle(.red)
            }
        }
    }

    private func runOutText(_ credit: FishCredit) -> String {
        let history = FishCreditHistory.shared
        guard let rate = history.dailySpend, let date = history.runsOutAround else {
            return "Not enough history yet to estimate when it runs out. The estimate appears once the balance has been checked over at least an hour of use."
        }
        return String(format: "Spending about $%.2f a day, so it should last until around %@.",
                      rate, date.formatted(date: .abbreviated, time: .omitted))
    }

    private func refreshFish() async {
        guard let key = FishAPIKey.load() else {
            fishError = "No FISH_API_KEY in .env."
            return
        }
        loadingFish = true
        defer { loadingFish = false }
        do {
            let credit = try await FishCredit.fetch(apiKey: key)
            FishCreditHistory.shared.add(credit)
            fish = credit
            fishError = nil
        } catch {
            fishError = "Couldn't read the Fish balance: \(error.localizedDescription)"
        }
    }

    // MARK: Claude

    private var claudeSection: some View {
        let total = claude.totals.values.reduce(TokenUsage()) { $0 + $1.usage }
        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Claude usage").font(.headline)
                Spacer()
                Button("Reset…") { confirmingReset = true }
                    .disabled(claude.totals.isEmpty)
            }
            Text(verbatim: String(format: "About $%.2f since %@", total.estimatedCost,
                                  claude.since.formatted(date: .abbreviated, time: .shortened)))
                .font(.system(size: 22, weight: .semibold, design: .rounded))
            Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 6) {
                GridRow {
                    Text("Feature"); Text("Requests"); Text("Input"); Text("Output"); Text("Cost")
                }
                .font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                ForEach(ClaudeUsageLedger.Feature.allCases, id: \.self) { feature in
                    let entry = claude.totals[feature] ?? ClaudeUsageLedger.Totals()
                    GridRow {
                        Text(verbatim: feature.title)
                        Text(verbatim: "\(entry.requests)")
                        Text(verbatim: (entry.usage.input + entry.usage.cacheRead + entry.usage.cacheWrite).formatted())
                        Text(verbatim: entry.usage.output.formatted())
                        Text(verbatim: String(format: "$%.3f", entry.usage.estimatedCost))
                    }
                    .monospacedDigit()
                }
            }
            Text(verbatim: "Estimated from the token counts in each response, at Claude Opus 5.5 rates. Anthropic doesn't let an API key read its remaining credit; check the Billing page in the Anthropic Console for that.")
                .font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .task {
            // Keep the tally current while the tab is open.
            while !Task.isCancelled {
                claude = ClaudeUsageLedger.shared.snapshot()
                try? await Task.sleep(for: .seconds(2))
            }
        }
    }
}
