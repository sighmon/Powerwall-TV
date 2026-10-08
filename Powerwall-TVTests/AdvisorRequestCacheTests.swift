import Foundation
import Testing
@testable import Powerwall_TV

struct AdvisorRequestCacheTests {
    private actor Counter {
        var count = 0
        func next() -> Int { count += 1; return count }
    }

    @Test func reusesFreshResultsExpiresAndSeparatesLocations() async throws {
        let cache = AdvisorRequestCache<String, Int>()
        let counter = Counter()
        let now = Date(timeIntervalSince1970: 1000)
        let first = try await cache.value(for: "site-a/location-a", now: now) { await counter.next() }
        let reused = try await cache.value(for: "site-a/location-a", now: now.addingTimeInterval(899)) { await counter.next() }
        let other = try await cache.value(for: "site-a/location-b", now: now.addingTimeInterval(899)) { await counter.next() }
        let expired = try await cache.value(for: "site-a/location-a", now: now.addingTimeInterval(900)) { await counter.next() }
        #expect(first == 1 && reused == 1 && other == 2 && expired == 3)
    }

    @Test func simultaneousRequestsShareOneFetch() async throws {
        let cache = AdvisorRequestCache<String, Int>()
        let counter = Counter()
        let values = try await withThrowingTaskGroup(of: Int.self) { group in
            for _ in 0..<20 {
                group.addTask {
                    try await cache.value(for: "same-forecast") {
                        let result = await counter.next()
                        try await Task.sleep(for: .milliseconds(30))
                        return result
                    }
                }
            }
            var values: [Int] = []
            for try await value in group { values.append(value) }
            return values
        }
        #expect(values.count == 20)
        #expect(values.allSatisfy { $0 == 1 })
        #expect(await counter.count == 1)
    }

    @Test func failedPrefetchCanBeRetried() async throws {
        let cache = AdvisorRequestCache<String, Int>()
        do {
            _ = try await cache.value(for: "forecast") { throw URLError(.notConnectedToInternet) }
            Issue.record("Expected failed prefetch")
        } catch {}
        let result = try await cache.value(for: "forecast") { 42 }
        #expect(result == 42)
    }
}
