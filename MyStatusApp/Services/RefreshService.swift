import Foundation
import WidgetKit
import QuotaCore

struct RefreshService {
  let coordinator: QuotaCoordinator
  let snapshotStore: SnapshotStore

  func refresh(configurations: [ProviderRuntimeConfiguration]) async throws -> QuotaSnapshot {
    let snapshot = await coordinator.refresh(configurations: configurations)
    try snapshotStore.save(snapshot)
    WidgetCenter.shared.reloadTimelines(ofKind: SharedConstants.widgetKind)
    return snapshot
  }
}
