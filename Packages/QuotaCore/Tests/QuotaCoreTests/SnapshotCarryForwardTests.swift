import XCTest
@testable import QuotaCore

final class SnapshotCarryForwardTests: XCTestCase {
  private let earlier = Date(timeIntervalSince1970: 1_700_000_000)
  private let later = Date(timeIntervalSince1970: 1_700_003_600)

  private func usage(_ provider: QuotaProvider, fetchedAt: Date) -> ProviderUsage {
    ProviderUsage(
      provider: provider,
      title: provider.displayName,
      metrics: [UsageMetric(id: "primary", label: "primary", remainingPercent: 50)],
      maxUsagePercent: 50,
      fetchedAt: fetchedAt
    )
  }

  func testCarriesForwardUsageForFailedProvider() {
    let previous = QuotaSnapshot(
      generatedAt: earlier,
      providers: [usage(.openAI, fetchedAt: earlier), usage(.zhipu, fetchedAt: earlier)],
      failures: []
    )
    let fresh = QuotaSnapshot(
      generatedAt: later,
      providers: [usage(.zhipu, fetchedAt: later)],
      failures: [ProviderFailure(provider: .openAI, kind: .network, message: "offline")]
    )

    let merged = fresh.carryingForward(previous: previous)

    XCTAssertEqual(merged.providers.count, 2)
    let carried = merged.providers.first(where: { $0.provider == .openAI })
    XCTAssertEqual(carried?.fetchedAt, earlier)
    XCTAssertEqual(merged.failures.count, 1)
    XCTAssertEqual(merged.generatedAt, later)
  }

  func testDoesNotCarryForwardNotConfiguredFailures() {
    let previous = QuotaSnapshot(
      generatedAt: earlier,
      providers: [usage(.openAI, fetchedAt: earlier)],
      failures: []
    )
    let fresh = QuotaSnapshot(
      generatedAt: later,
      providers: [],
      failures: [ProviderFailure(provider: .openAI, kind: .notConfigured, message: "logged out")]
    )

    let merged = fresh.carryingForward(previous: previous)

    XCTAssertTrue(merged.providers.isEmpty)
  }

  func testFreshDataWinsOverPrevious() {
    let previous = QuotaSnapshot(
      generatedAt: earlier,
      providers: [usage(.openAI, fetchedAt: earlier)],
      failures: []
    )
    let fresh = QuotaSnapshot(
      generatedAt: later,
      providers: [usage(.openAI, fetchedAt: later)],
      failures: []
    )

    let merged = fresh.carryingForward(previous: previous)

    XCTAssertEqual(merged.providers.count, 1)
    XCTAssertEqual(merged.providers.first?.fetchedAt, later)
  }

  func testNilPreviousReturnsSelf() {
    let fresh = QuotaSnapshot(
      generatedAt: later,
      providers: [],
      failures: [ProviderFailure(provider: .openAI, kind: .network, message: "offline")]
    )

    let merged = fresh.carryingForward(previous: nil)

    XCTAssertEqual(merged, fresh)
  }
}
