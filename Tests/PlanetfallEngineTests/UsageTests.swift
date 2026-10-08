import Foundation
import Testing
@testable import PlanetfallEngine

struct GameTextNarrationTests {
    @Test func dropsTheBannerAndCharacterMarkers() {
        let narration = """
        PLANETFALL
        Infocom interactive fiction - a science fiction story
        Copyright (c) 1983 by Infocom, Inc. All rights reserved.
        PLANETFALL is a registered trademark of Infocom, Inc.
        Release 39 / Serial number 880501

        Another routine day of drudgery aboard the Stellar Patrol Ship Feinstein. This
        morning's assignment: scrubbing the deck.

        [Blather speaks] He glares at you, his arms crossed.
        """
        #expect(GameTextNarration.spokenParagraphs(from: narration) == [
            "Another routine day of drudgery aboard the Stellar Patrol Ship Feinstein. This morning's assignment: scrubbing the deck.",
            "He glares at you, his arms crossed.",
        ])
        #expect(GameTextNarration.spokenParagraphs(from: "[Floyd speaks]").isEmpty)
    }
}

struct ClaudeUsageTests {
    private func defaults() -> UserDefaults {
        UserDefaults(suiteName: "usage-\(UUID().uuidString)")!
    }

    @Test func tallyPersistsAndPricesTokens() {
        let store = defaults()
        let ledger = ClaudeUsageLedger(defaults: store)
        ledger.record(.commentary, TokenUsage(input: 2_000, cacheRead: 1_000, output: 100))
        ledger.record(.commentary, TokenUsage(input: 1_000, output: 50))
        ledger.record(.narration, TokenUsage())  // nothing used: not counted
        let totals = ClaudeUsageLedger(defaults: store).snapshot().totals
        #expect(totals[.commentary]?.requests == 2)
        #expect(totals[.commentary]?.usage == TokenUsage(input: 3_000, cacheRead: 1_000, output: 150))
        #expect(totals[.narration] == nil)
        // 3,000 x $4 + 1,000 x $0.20 + 150 x $20, per million.
        #expect(abs((totals[.commentary]?.usage.estimatedCost ?? 0) - 0.0152) < 1e-9)
    }

    @Test func readsUsageFromTheStream() throws {
        let start = #"data: {"type":"message_start","message":{"id":"m","usage":{"input_tokens":2452,"cache_read_input_tokens":0,"cache_creation_input_tokens":0,"output_tokens":1}}}"#
        let end = #"data: {"type":"message_delta","delta":{"stop_reason":"end_turn"},"usage":{"output_tokens":87}}"#
        #expect(try Commentator.parseEvent(start) == .usage(TokenUsage(input: 2452, output: 1)))
        #expect(Commentator.outputTokens(in: end) == 87)
        #expect(try Commentator.parseEvent(end) == .stop(reason: "end_turn"))
    }
}

struct FishCreditHistoryTests {
    @Test func estimatesWhenCreditRunsOut() throws {
        let history = FishCreditHistory(defaults: UserDefaults(suiteName: "fish-\(UUID().uuidString)")!)
        let now = Date()
        history.add(FishCredit(balance: 5.00, totalTopUp: 5, readAt: now.addingTimeInterval(-2 * 86_400)))
        #expect(history.dailySpend == nil)  // one reading: no rate yet
        history.add(FishCredit(balance: 4.80, totalTopUp: 5, readAt: now))
        let rate = try #require(history.dailySpend)
        #expect(abs(rate - 0.10) < 1e-9)
        let runsOut = try #require(history.runsOutAround)
        #expect(abs(runsOut.timeIntervalSince(now) - 48 * 86_400) < 1)

        // A top-up starts the history over.
        history.add(FishCredit(balance: 10.00, totalTopUp: 15, readAt: now.addingTimeInterval(60)))
        #expect(history.dailySpend == nil)
    }
}
