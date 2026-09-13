import Foundation
import Testing
@testable import Powerwall_TV

struct AdvisorEstimateFreshnessTests {
    let zone = TimeZone(secondsFromGMT: 0)!
    let generated = Date(timeIntervalSince1970: 43_200)

    @Test func expiresAtFifteenMinutes() {
        let end = generated.addingTimeInterval(86400)
        #expect(AdvisorEstimateFreshness.isFresh(generatedAt: generated, end: end, timeZone: zone, now: generated.addingTimeInterval(899)))
        for age in [900.0, 3600, 172800, -1] {
            #expect(!AdvisorEstimateFreshness.isFresh(generatedAt: generated, end: end, timeZone: zone, now: generated.addingTimeInterval(age)))
        }
    }

    @Test func expiresAtEndOfWindow() {
        let end = generated.addingTimeInterval(60)
        #expect(!AdvisorEstimateFreshness.isFresh(generatedAt: generated, end: end, timeZone: zone, now: end))
    }

    @Test func siteLocalMidnightExpiresRelativeForecast() {
        let siteZone = TimeZone(secondsFromGMT: 9 * 3600 + 1800)!
        let midnight = Date(timeIntervalSince1970: 86400 - Double(siteZone.secondsFromGMT()))
        #expect(!AdvisorEstimateFreshness.isFresh(generatedAt: midnight.addingTimeInterval(-60), end: midnight.addingTimeInterval(36000), timeZone: siteZone, now: midnight))
    }
}
