import Foundation

/// Bounded pruning for watcher-side dictionaries that would otherwise grow
/// for the lifetime of the process.
public enum WatcherCachePruning {
    /// Drops entries older than `maxAge`, then keeps only the `maxCount` most
    /// recently seen of what remains.
    public static func prunedByAge<Value>(
        _ entries: [String: Value],
        lastSeenAt: (Value) -> Date,
        now: Date = Date(),
        maxAge: TimeInterval = 3600,
        maxCount: Int = 500
    ) -> [String: Value] {
        var pruned = entries.filter { now.timeIntervalSince(lastSeenAt($0.value)) <= maxAge }
        guard pruned.count > maxCount else {
            return pruned
        }

        let excessKeys = pruned
            .sorted { lastSeenAt($0.value) > lastSeenAt($1.value) }
            .dropFirst(maxCount)
            .map(\.key)
        for key in excessKeys {
            pruned.removeValue(forKey: key)
        }
        return pruned
    }
}
