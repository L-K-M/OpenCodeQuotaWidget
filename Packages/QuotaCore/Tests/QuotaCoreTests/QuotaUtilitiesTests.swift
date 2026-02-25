import XCTest
@testable import QuotaCore

final class QuotaUtilitiesTests: XCTestCase {
  func testParseNumericParsesDifferentShapes() {
    XCTAssertEqual(parseNumeric(42), 42)
    XCTAssertEqual(parseNumeric("1,024"), 1024)
    XCTAssertEqual(parseNumeric("83.5%"), 83.5)
    XCTAssertNil(parseNumeric("abc"))
  }

  func testFormatShortDuration() {
    XCTAssertEqual(formatShortDuration(seconds: 65), "1m")
    XCTAssertEqual(formatShortDuration(seconds: 3661), "1h 1m")
    XCTAssertEqual(formatShortDuration(seconds: 90061), "1d 1h 1m")
  }

  func testResetCountdownHandlesPastAndFuture() {
    let now = Date(timeIntervalSince1970: 1_700_000_000)
    let past = now.addingTimeInterval(-1)
    let future = now.addingTimeInterval(3_700)

    XCTAssertEqual(formatResetCountdown(to: past, now: now), "reset")
    XCTAssertEqual(formatResetCountdown(to: future, now: now), "1h 1m")
  }
}
