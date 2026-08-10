import Foundation
import QuotaCore

struct RefreshService {
  let coordinator: QuotaCoordinator
  let snapshotStore: SnapshotStore

  func refresh(configurations: [ProviderRuntimeConfiguration]) async throws -> QuotaSnapshot {
    let previous = try? snapshotStore.load()
    let fresh = await coordinator.refresh(configurations: configurations)
    let snapshot = fresh.carryingForward(previous: previous)
    try snapshotStore.save(snapshot)
    return snapshot
  }
}
