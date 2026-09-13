import Foundation

/// Shares in-flight work and caches only successful results. Caller cancellation does not
/// cancel work that another caller (such as the advisor sheet) may still need.
actor AdvisorRequestCache<Key: Hashable, Value> {
    private var entries: [Key: (date: Date, value: Value)] = [:]
    private var pending: [Key: Task<Value, Error>] = [:]
    private let lifetime: TimeInterval

    init(lifetime: TimeInterval = 900) { self.lifetime = lifetime }

    func value(for key: Key, now: Date = Date(), load: @escaping () async throws -> Value) async throws -> Value {
        entries = entries.filter { now.timeIntervalSince($0.value.date) >= 0 && now.timeIntervalSince($0.value.date) < lifetime }
        if let entry = entries[key] { return entry.value }
        if let task = pending[key] { return try await task.value }
        let task = Task { try await load() }
        pending[key] = task
        defer { pending[key] = nil }
        let value = try await task.value
        if entries.count >= 8, let oldest = entries.min(by: { $0.value.date < $1.value.date })?.key {
            entries[oldest] = nil
        }
        entries[key] = (now, value)
        return value
    }
}
