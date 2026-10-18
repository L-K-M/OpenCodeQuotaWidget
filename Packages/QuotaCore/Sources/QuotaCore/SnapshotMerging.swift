import Foundation

public extension QuotaSnapshot {
  /// Returns a snapshot where providers that failed this refresh keep their
  /// last known usage from `previous`, so consumers can show stale data
  /// instead of nothing when a provider API is temporarily unreachable.
  ///
  /// The failure stays recorded and the carried usage keeps its original
  /// `fetchedAt`, so staleness remains visible. Failures of kind
  /// `.notConfigured` are not carried forward: losing credentials is treated
  /// as an intentional removal rather than a transient outage.
  func carryingForward(previous: QuotaSnapshot?) -> QuotaSnapshot {
    guard let previous else {
      return self
    }

    let currentProviders = Set(providers.map(\.provider))

    let carried = failures.compactMap { failure -> ProviderUsage? in
      guard
        failure.kind != .notConfigured,
        !currentProviders.contains(failure.provider)
      else {
        return nil
      }

      return previous.providers.first(where: { $0.provider == failure.provider })
    }

    guard !carried.isEmpty else {
      return self
    }

    var merged = self
    merged.providers = (providers + carried).sorted { lhs, rhs in
      lhs.provider.rawValue < rhs.provider.rawValue
    }
    return merged
  }
}
