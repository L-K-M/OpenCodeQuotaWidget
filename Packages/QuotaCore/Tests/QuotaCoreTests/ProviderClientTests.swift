import XCTest
@testable import QuotaCore

private struct MockHTTPClient: HTTPClient {
  let handler: @Sendable (URLRequest) throws -> (Data, HTTPURLResponse)

  func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
    try handler(request)
  }
}

private func httpResponse(url: URL, statusCode: Int) -> HTTPURLResponse {
  HTTPURLResponse(url: url, statusCode: statusCode, httpVersion: "HTTP/1.1", headerFields: nil)!
}

final class OpenAIClientTests: XCTestCase {
  private let now = Date(timeIntervalSince1970: 1_700_000_000)

  private func makeClient(statusCode: Int = 200, body: String) -> OpenAIClient {
    OpenAIClient(
      httpClient: MockHTTPClient { request in
        let url = request.url!
        return (Data(body.utf8), httpResponse(url: url, statusCode: statusCode))
      }
    )
  }

  private var configuration: ProviderRuntimeConfiguration {
    ProviderRuntimeConfiguration(
      provider: .openAI,
      isEnabled: true,
      credentials: [CredentialField.openAIAccessToken: "token-123"]
    )
  }

  func testParsesPrimaryAndSecondaryWindows() async throws {
    let body = """
    {
      "plan_type": "plus",
      "rate_limit": {
        "limit_reached": false,
        "primary_window": {
          "used_percent": 28.0,
          "limit_window_seconds": 10800,
          "reset_after_seconds": 6120
        },
        "secondary_window": {
          "used_percent": 39.0,
          "limit_window_seconds": 604800,
          "reset_after_seconds": 183600
        }
      }
    }
    """

    let usage = try await makeClient(body: body).fetchUsage(configuration: configuration, now: now)

    XCTAssertEqual(usage.subtitle, "plus")
    XCTAssertEqual(usage.metrics.count, 2)
    XCTAssertEqual(usage.metrics[0].label, "3-hour limit")
    XCTAssertEqual(usage.metrics[0].remainingPercent, 72)
    XCTAssertEqual(usage.metrics[1].label, "7-day limit")
    XCTAssertEqual(usage.metrics[1].remainingPercent, 61)
    XCTAssertEqual(usage.maxUsagePercent, 39)
    XCTAssertNil(usage.warning)
  }

  func testToleratesMissingPlanType() async throws {
    let body = """
    {
      "rate_limit": {
        "limit_reached": true,
        "primary_window": {
          "used_percent": 100.0,
          "limit_window_seconds": 10800,
          "reset_after_seconds": 600
        }
      }
    }
    """

    let usage = try await makeClient(body: body).fetchUsage(configuration: configuration, now: now)

    XCTAssertNil(usage.subtitle)
    XCTAssertEqual(usage.metrics.first?.remainingPercent, 0)
    XCTAssertEqual(usage.warning, "Rate limit reached")
  }

  func testUnauthorizedMapsToAuthError() async {
    do {
      _ = try await makeClient(statusCode: 401, body: "{}")
        .fetchUsage(configuration: configuration, now: now)
      XCTFail("Expected ProviderClientError")
    } catch let error as ProviderClientError {
      XCTAssertEqual(error.kind, .auth)
    } catch {
      XCTFail("Unexpected error type: \(error)")
    }
  }

  func testMissingTokenMapsToNotConfigured() async {
    let configuration = ProviderRuntimeConfiguration(provider: .openAI, isEnabled: true, credentials: [:])

    do {
      _ = try await makeClient(body: "{}").fetchUsage(configuration: configuration, now: now)
      XCTFail("Expected ProviderClientError")
    } catch let error as ProviderClientError {
      XCTAssertEqual(error.kind, .notConfigured)
    } catch {
      XCTFail("Unexpected error type: \(error)")
    }
  }
}

final class ZhipuQuotaClientTests: XCTestCase {
  private let now = Date(timeIntervalSince1970: 1_700_000_000)

  private func makeClient(statusCode: Int = 200, body: String) -> ZhipuQuotaClient {
    ZhipuQuotaClient(
      provider: .zhipu,
      endpoint: URL(string: "https://example.com/quota")!,
      accountLabel: "Coding Plan",
      httpClient: MockHTTPClient { request in
        let url = request.url!
        return (Data(body.utf8), httpResponse(url: url, statusCode: statusCode))
      }
    )
  }

  private var configuration: ProviderRuntimeConfiguration {
    ProviderRuntimeConfiguration(
      provider: .zhipu,
      isEnabled: true,
      credentials: [CredentialField.zhipuAPIKey: "key-123"]
    )
  }

  func testParsesTokenAndTimeLimits() async throws {
    let body = """
    {
      "success": true,
      "code": 200,
      "data": {
        "limits": [
          {
            "type": "TOKENS_LIMIT",
            "percentage": 45.0,
            "currentValue": 4500000,
            "usage": 10000000,
            "nextResetTime": 1700003600000
          },
          {
            "type": "TIME_LIMIT",
            "percentage": 19.0
          }
        ]
      }
    }
    """

    let usage = try await makeClient(body: body).fetchUsage(configuration: configuration, now: now)

    XCTAssertEqual(usage.metrics.count, 2)

    let tokens = usage.metrics[0]
    XCTAssertEqual(tokens.id, "tokens")
    XCTAssertEqual(tokens.remainingPercent, 55)
    XCTAssertEqual(tokens.usedDisplay, "4.5M")
    XCTAssertEqual(tokens.totalDisplay, "10.0M")
    XCTAssertEqual(tokens.resetAt?.timeIntervalSince1970 ?? 0, 1_700_003_600, accuracy: 1)

    let mcp = usage.metrics[1]
    XCTAssertEqual(mcp.id, "mcp")
    XCTAssertEqual(mcp.remainingPercent, 81)

    XCTAssertEqual(usage.maxUsagePercent, 45)
  }

  func testNonSuccessPayloadMapsToAPIError() async {
    let body = """
    {"success": false, "code": 500, "msg": "boom"}
    """

    do {
      _ = try await makeClient(body: body).fetchUsage(configuration: configuration, now: now)
      XCTFail("Expected ProviderClientError")
    } catch let error as ProviderClientError {
      XCTAssertEqual(error.kind, .api)
      XCTAssertTrue(error.message.contains("boom"))
    } catch {
      XCTFail("Unexpected error type: \(error)")
    }
  }
}

final class CopilotClientTests: XCTestCase {
  private let now = Date(timeIntervalSince1970: 1_700_000_000)

  func testBillingAPIComputesRemainingFromTierLimit() async throws {
    let body = """
    {
      "timePeriod": {"year": 2026, "month": 6},
      "user": "octocat",
      "usageItems": [
        {
          "product": "copilot",
          "sku": "Copilot Premium Request",
          "model": "default",
          "unitType": "requests",
          "grossQuantity": 126,
          "netQuantity": 126,
          "limit": 300
        }
      ]
    }
    """

    let client = CopilotClient(
      httpClient: MockHTTPClient { request in
        let url = request.url!
        XCTAssertTrue(url.path.contains("users/octocat/settings/billing"))
        return (Data(body.utf8), httpResponse(url: url, statusCode: 200))
      }
    )

    let configuration = ProviderRuntimeConfiguration(
      provider: .gitHubCopilot,
      isEnabled: true,
      credentials: [
        CredentialField.copilotPATToken: "pat-123",
        CredentialField.copilotUsername: "octocat",
        CredentialField.copilotTier: "pro"
      ]
    )

    let usage = try await client.fetchUsage(configuration: configuration, now: now)

    XCTAssertEqual(usage.subtitle, "@octocat (pro)")
    let metric = try XCTUnwrap(usage.metrics.first)
    XCTAssertEqual(metric.usedDisplay, "126")
    XCTAssertEqual(metric.totalDisplay, "300")
    XCTAssertEqual(metric.remainingPercent, 58)
    XCTAssertEqual(usage.maxUsagePercent, 42)
  }

  func testMissingCredentialsMapsToNotConfigured() async {
    let client = CopilotClient(
      httpClient: MockHTTPClient { request in
        (Data(), httpResponse(url: request.url!, statusCode: 200))
      }
    )

    let configuration = ProviderRuntimeConfiguration(provider: .gitHubCopilot, isEnabled: true, credentials: [:])

    do {
      _ = try await client.fetchUsage(configuration: configuration, now: now)
      XCTFail("Expected ProviderClientError")
    } catch let error as ProviderClientError {
      XCTAssertEqual(error.kind, .notConfigured)
    } catch {
      XCTFail("Unexpected error type: \(error)")
    }
  }
}
