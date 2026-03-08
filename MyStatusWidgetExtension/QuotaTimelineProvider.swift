import Foundation
import Darwin
import WidgetKit
import QuotaCore

struct QuotaEntry: TimelineEntry {
  let date: Date
  let snapshot: QuotaSnapshot?
  let history: [QuotaSnapshot]
  let refreshIntervalMinutes: Int
  let settings: AppSettings
}

struct QuotaTimelineProvider: TimelineProvider {
  private static let refreshAttemptTimestampKey = "widget.refresh.lastAttemptAt"
  private static let minimumRefreshAttemptSpacingSeconds: TimeInterval = 90
  private static let providerRequestTimeoutSeconds: TimeInterval = 6
  private static let refreshWorkBudgetSeconds: TimeInterval = 12

  func placeholder(in context: Context) -> QuotaEntry {
    QuotaEntry(
      date: Date(),
      snapshot: SampleSnapshotFactory.make(now: Date()),
      history: SampleSnapshotFactory.makeHistory(now: Date()),
      refreshIntervalMinutes: 30,
      settings: .default
    )
  }

  func getSnapshot(in context: Context, completion: @escaping (QuotaEntry) -> Void) {
    if context.isPreview {
      completion(
        QuotaEntry(
          date: Date(),
          snapshot: SampleSnapshotFactory.make(now: Date()),
          history: SampleSnapshotFactory.makeHistory(now: Date()),
          refreshIntervalMinutes: 30,
          settings: .default
        )
      )
      return
    }

    completion(makeStoredEntry(now: Date()))
  }

  func getTimeline(in context: Context, completion: @escaping (Timeline<QuotaEntry>) -> Void) {
    Task {
      let now = Date()
      let entry = await makeTimelineEntry(now: now)
      let refreshMinutes = max(15, entry.refreshIntervalMinutes)
      let refreshIntervalSeconds = TimeInterval(refreshMinutes * 60)
      let entrySpacingSeconds: TimeInterval = 5 * 60

      var entries: [QuotaEntry] = []
      var offset: TimeInterval = 0
      while offset < refreshIntervalSeconds {
        let entryDate = now.addingTimeInterval(offset)
        entries.append(QuotaEntry(
          date: entryDate,
          snapshot: entry.snapshot,
          history: entry.history,
          refreshIntervalMinutes: entry.refreshIntervalMinutes,
          settings: entry.settings
        ))
        offset += entrySpacingSeconds
      }

      // Final entry at exactly the next refresh boundary
      let nextRefreshDate = now.addingTimeInterval(refreshIntervalSeconds)
      if let lastEntry = entries.last, lastEntry.date < nextRefreshDate {
        entries.append(QuotaEntry(
          date: nextRefreshDate,
          snapshot: entry.snapshot,
          history: entry.history,
          refreshIntervalMinutes: entry.refreshIntervalMinutes,
          settings: entry.settings
        ))
      }

      completion(Timeline(entries: entries, policy: .atEnd))
    }
  }

  private func makeStoredEntry(now: Date) -> QuotaEntry {
    let settings = loadSettings()
    let snapshot = loadSnapshot()
    let history = loadHistory(fallbackSnapshot: snapshot)
    let refreshInterval = max(15, settings.refreshIntervalMinutes)
    return QuotaEntry(
      date: now,
      snapshot: snapshot,
      history: history,
      refreshIntervalMinutes: refreshInterval,
      settings: settings
    )
  }

  private func makeTimelineEntry(now: Date) async -> QuotaEntry {
    let baseEntry = makeStoredEntry(now: now)
    guard shouldRefreshSnapshot(
      baseEntry.snapshot,
      now: now,
      refreshIntervalMinutes: baseEntry.refreshIntervalMinutes
    ) else {
      return baseEntry
    }

    guard let refreshedSnapshot = await refreshSnapshot(now: now, settings: baseEntry.settings) else {
      return baseEntry
    }

    return QuotaEntry(
      date: now,
      snapshot: refreshedSnapshot,
      history: loadHistory(fallbackSnapshot: refreshedSnapshot),
      refreshIntervalMinutes: baseEntry.refreshIntervalMinutes,
      settings: baseEntry.settings
    )
  }

  private func shouldRefreshSnapshot(
    _ snapshot: QuotaSnapshot?,
    now: Date,
    refreshIntervalMinutes: Int
  ) -> Bool {
    guard let snapshot else {
      return true
    }

    let maxAgeSeconds = TimeInterval(max(15, refreshIntervalMinutes) * 60)
    return now.timeIntervalSince(snapshot.generatedAt) >= maxAgeSeconds
  }

  private func refreshSnapshot(now: Date, settings: AppSettings) async -> QuotaSnapshot? {
    guard reserveRefreshAttempt(now: now) else {
      return loadSnapshot()
    }

    let enabledByProvider = Dictionary(uniqueKeysWithValues: settings.providers.map { ($0.provider, $0.isEnabled) })
    let loader = WidgetCredentialLoader()
    let configurations = loader.load(providerEnabled: enabledByProvider)
    let enabledConfigurations = configurations.filter(\.isEnabled)

    guard !enabledConfigurations.isEmpty else {
      print("[OpenCodeQuota Widget] No enabled providers with readable credentials")
      return nil
    }

    let coordinator = QuotaCoordinator.live(
      httpClient: URLSessionHTTPClient(timeoutSeconds: Self.providerRequestTimeoutSeconds)
    )

    guard let refreshedSnapshot = await refreshWithinBudget(
      coordinator: coordinator,
      configurations: enabledConfigurations,
      now: now
    ) else {
      print("[OpenCodeQuota Widget] Refresh budget exceeded before completion")
      return loadSnapshot()
    }

    do {
      let snapshotURL = try SharedPaths.snapshotFileURL()
      let snapshotStore = SnapshotStore(fileURL: snapshotURL, appGroupIdentifier: SharedConstants.appGroupIdentifier)
      try snapshotStore.save(refreshedSnapshot)
    } catch {
      print("[OpenCodeQuota Widget] Failed to save refreshed snapshot: \(error)")
    }

    do {
      let historyURL = try SharedPaths.historyFileURL()
      let historyStore = QuotaHistoryStore(fileURL: historyURL)
      try historyStore.append(refreshedSnapshot)
    } catch {
      print("[OpenCodeQuota Widget] Failed to append refreshed history: \(error)")
    }

    return refreshedSnapshot
  }

  private func reserveRefreshAttempt(now: Date) -> Bool {
    guard let defaults = UserDefaults(suiteName: SharedConstants.appGroupIdentifier) else {
      return true
    }

    if
      let lastAttempt = defaults.object(forKey: Self.refreshAttemptTimestampKey) as? Date,
      now.timeIntervalSince(lastAttempt) < Self.minimumRefreshAttemptSpacingSeconds
    {
      return false
    }

    defaults.set(now, forKey: Self.refreshAttemptTimestampKey)
    return true
  }

  private func refreshWithinBudget(
    coordinator: QuotaCoordinator,
    configurations: [ProviderRuntimeConfiguration],
    now: Date
  ) async -> QuotaSnapshot? {
    await withTaskGroup(of: QuotaSnapshot?.self) { group in
      group.addTask {
        await coordinator.refresh(configurations: configurations, now: now)
      }

      group.addTask {
        let budgetNanoseconds = UInt64(Self.refreshWorkBudgetSeconds * 1_000_000_000)
        try? await Task.sleep(nanoseconds: budgetNanoseconds)
        return nil
      }

      let firstCompleted = await group.next() ?? nil
      group.cancelAll()
      return firstCompleted
    }
  }

  private func loadSnapshot() -> QuotaSnapshot? {
    do {
      let fileURL = try SharedPaths.snapshotFileURL()
      print("[OpenCodeQuota Widget] Attempting to load snapshot from: \(fileURL.path)")

      let store = SnapshotStore(fileURL: fileURL, appGroupIdentifier: SharedConstants.appGroupIdentifier)
      print("[OpenCodeQuota Widget] Debug info:\n\(store.debugInfo())")

      if let snapshot = try store.load() {
        print("[OpenCodeQuota Widget] Successfully loaded snapshot with \(snapshot.providers.count) providers")
        return snapshot
      } else {
        print("[OpenCodeQuota Widget] Snapshot file does not exist")
        return nil
      }
    } catch {
      print("[OpenCodeQuota Widget] Failed to load snapshot: \(error)")
      return nil
    }
  }

  private func loadSettings() -> AppSettings {
    do {
      let settingsURL = try SharedPaths.settingsFileURL()
      let store = SettingsStore(fileURL: settingsURL)
      let settings = try store.load()
      print("[OpenCodeQuota Widget] Loaded settings from: \(settingsURL.path)")
      return settings
    } catch {
      print("[OpenCodeQuota Widget] Failed to load settings, using defaults: \(error)")
      return .default
    }
  }

  private func loadHistory(fallbackSnapshot: QuotaSnapshot?) -> [QuotaSnapshot] {
    do {
      let fileURL = try SharedPaths.historyFileURL()
      let store = QuotaHistoryStore(fileURL: fileURL)
      let history = try store.load().sorted { $0.generatedAt < $1.generatedAt }

      if !history.isEmpty {
        return history
      }

      if let fallbackSnapshot {
        return [fallbackSnapshot]
      }
    } catch {
      print("[OpenCodeQuota Widget] Failed to load history: \(error)")
    }

    if let fallbackSnapshot {
      return [fallbackSnapshot]
    }

    return []
  }
}

private struct WidgetCredentialLoader {
  private struct CandidateURL {
    let url: URL
    let requiresSecurityScope: Bool
  }

  private enum BookmarkKey: String {
    case authFile = "sandbox.bookmark.authFile"
    case antigravityFile = "sandbox.bookmark.antigravityFile"
    case copilotPATFile = "sandbox.bookmark.copilotPATFile"

    var pathKey: String {
      "\(rawValue).path"
    }

    func isAllowedFallbackPath(_ path: String) -> Bool {
      let normalized = path.lowercased()
      switch self {
      case .authFile:
        return normalized.hasSuffix("/.local/share/opencode/auth.json")
          || normalized.hasSuffix("/.config/opencode/auth.json")
      case .antigravityFile:
        return normalized.hasSuffix("/.config/opencode/antigravity-accounts.json")
      case .copilotPATFile:
        return normalized.hasSuffix("/.config/opencode/copilot-quota-token.json")
      }
    }
  }

  private let fileManager: FileManager
  private let sharedDefaults: UserDefaults?
  private let environment: [String: String]

  init(
    fileManager: FileManager = .default,
    sharedDefaults: UserDefaults? = UserDefaults(suiteName: SharedConstants.appGroupIdentifier),
    environment: [String: String] = ProcessInfo.processInfo.environment
  ) {
    self.fileManager = fileManager
    self.sharedDefaults = sharedDefaults
    self.environment = environment
  }

  func load(providerEnabled: [QuotaProvider: Bool]) -> [ProviderRuntimeConfiguration] {
    let authObject = loadJSONObject(from: authCandidates())
    let antigravityObject = loadJSONObject(from: antigravityCandidates())
    let copilotPATObject = loadJSONObject(from: copilotPATCandidates())

    return QuotaProvider.allCases.map { provider in
      let enabled = providerEnabled[provider] ?? true
      let credentials: [String: String]

      switch provider {
      case .openAI:
        credentials = parseOpenAICredentials(from: authObject)
      case .zhipu:
        credentials = parseAPIKeyCredentials(
          from: authObject,
          authKey: "zhipuai-coding-plan",
          credentialField: CredentialField.zhipuAPIKey
        )
      case .zai:
        credentials = parseAPIKeyCredentials(
          from: authObject,
          authKey: "zai-coding-plan",
          credentialField: CredentialField.zaiAPIKey
        )
      case .googleAntigravity:
        credentials = parseGoogleCredentials(from: antigravityObject)
      case .gitHubCopilot:
        credentials = parseCopilotCredentials(auth: authObject, pat: copilotPATObject)
      }

      return ProviderRuntimeConfiguration(
        provider: provider,
        isEnabled: enabled && !credentials.isEmpty,
        credentials: credentials
      )
    }
  }

  private func loadJSONObject(from candidates: [CandidateURL]) -> [String: Any]? {
    for candidate in uniqueCandidates(candidates) {
      let scoped = candidate.requiresSecurityScope && candidate.url.startAccessingSecurityScopedResource()
      defer {
        if scoped {
          candidate.url.stopAccessingSecurityScopedResource()
        }
      }

      do {
        if (try? candidate.url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true {
          continue
        }

        let data = try Data(contentsOf: candidate.url)
        let object = try JSONSerialization.jsonObject(with: data)
        if let dictionary = object as? [String: Any] {
          return dictionary
        }
      } catch {
        continue
      }
    }

    return nil
  }

  private func uniqueCandidates(_ candidates: [CandidateURL]) -> [CandidateURL] {
    var seen: Set<String> = []
    var output: [CandidateURL] = []

    for candidate in candidates {
      let key = "\(candidate.url.path)|\(candidate.requiresSecurityScope ? "scoped" : "direct")"
      if seen.insert(key).inserted {
        output.append(candidate)
      }
    }

    return output
  }

  private func authCandidates() -> [CandidateURL] {
    var candidates: [CandidateURL] = []

    candidates.append(contentsOf: allHomePaths(".local/share/opencode/auth.json").map {
      CandidateURL(url: $0, requiresSecurityScope: false)
    })
    candidates.append(contentsOf: allHomePaths(".config/opencode/auth.json").map {
      CandidateURL(url: $0, requiresSecurityScope: false)
    })

    if let xdgData = xdgPath(envKey: "XDG_DATA_HOME", tail: "opencode/auth.json") {
      candidates.append(CandidateURL(url: xdgData, requiresSecurityScope: false))
    }

    if let xdgConfig = xdgPath(envKey: "XDG_CONFIG_HOME", tail: "opencode/auth.json") {
      candidates.append(CandidateURL(url: xdgConfig, requiresSecurityScope: false))
    }

    appendDefaultsCandidates(for: .authFile, to: &candidates)
    return candidates
  }

  private func antigravityCandidates() -> [CandidateURL] {
    var candidates: [CandidateURL] = []

    candidates.append(contentsOf: allHomePaths(".config/opencode/antigravity-accounts.json").map {
      CandidateURL(url: $0, requiresSecurityScope: false)
    })

    if let xdgConfig = xdgPath(
      envKey: "XDG_CONFIG_HOME",
      tail: "opencode/antigravity-accounts.json"
    ) {
      candidates.append(CandidateURL(url: xdgConfig, requiresSecurityScope: false))
    }

    appendDefaultsCandidates(for: .antigravityFile, to: &candidates)
    return candidates
  }

  private func copilotPATCandidates() -> [CandidateURL] {
    var candidates: [CandidateURL] = []

    candidates.append(contentsOf: allHomePaths(".config/opencode/copilot-quota-token.json").map {
      CandidateURL(url: $0, requiresSecurityScope: false)
    })

    if let xdgConfig = xdgPath(
      envKey: "XDG_CONFIG_HOME",
      tail: "opencode/copilot-quota-token.json"
    ) {
      candidates.append(CandidateURL(url: xdgConfig, requiresSecurityScope: false))
    }

    appendDefaultsCandidates(for: .copilotPATFile, to: &candidates)
    return candidates
  }

  private func appendDefaultsCandidates(for key: BookmarkKey, to candidates: inout [CandidateURL]) {
    guard let sharedDefaults else {
      return
    }

    if
      let path = sharedDefaults.string(forKey: key.pathKey),
      key.isAllowedFallbackPath(path)
    {
      candidates.append(CandidateURL(url: URL(fileURLWithPath: path), requiresSecurityScope: false))
    }

    if let bookmarkData = sharedDefaults.data(forKey: key.rawValue) {
      var stale = false
      if
        let url = try? URL(
          resolvingBookmarkData: bookmarkData,
          options: [.withSecurityScope, .withoutUI],
          relativeTo: nil,
          bookmarkDataIsStale: &stale
        ),
        key.isAllowedFallbackPath(url.path)
      {
        candidates.append(CandidateURL(url: url, requiresSecurityScope: true))
      }
    }
  }

  private func xdgPath(envKey: String, tail: String) -> URL? {
    guard let root = environment[envKey], !root.isEmpty else {
      return nil
    }

    let rootURL = URL(fileURLWithPath: root, isDirectory: true)
    return append(path: tail, to: rootURL)
  }

  private func allHomePaths(_ suffix: String) -> [URL] {
    userHomeDirectories().map { append(path: suffix, to: $0) }
  }

  private func append(path suffix: String, to root: URL) -> URL {
    suffix
      .split(separator: "/")
      .reduce(root) { partial, component in
        partial.appendingPathComponent(String(component))
      }
  }

  private func userHomeDirectories() -> [URL] {
    var homes: [URL] = []

    if let posixHome = posixHomeDirectory() {
      homes.append(posixHome)
    }

    if let envHome = environment["HOME"], !envHome.isEmpty {
      homes.append(URL(fileURLWithPath: envHome, isDirectory: true))
    }

    homes.append(fileManager.homeDirectoryForCurrentUser)
    homes.append(URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true))

    let username = NSUserName()
    if !username.isEmpty {
      homes.append(URL(fileURLWithPath: "/Users/\(username)", isDirectory: true))
    }

    var seen: Set<String> = []
    var uniqueHomes: [URL] = []
    for home in homes {
      let path = home.path
      if seen.insert(path).inserted {
        uniqueHomes.append(home)
      }
    }

    return uniqueHomes
  }

  private func posixHomeDirectory() -> URL? {
    guard let passwd = getpwuid(getuid()) else {
      return nil
    }

    let path = String(cString: passwd.pointee.pw_dir)
    guard !path.isEmpty else {
      return nil
    }

    return URL(fileURLWithPath: path, isDirectory: true)
  }

  private func parseOpenAICredentials(from authObject: [String: Any]?) -> [String: String] {
    guard
      let authObject,
      let openAI = authObject["openai"] as? [String: Any],
      (openAI["type"] as? String) == "oauth",
      let access = openAI["access"] as? String,
      !access.isEmpty
    else {
      return [:]
    }

    var credentials: [String: String] = [
      CredentialField.openAIAccessToken: access
    ]

    if let accountID = extractOpenAIAccountID(from: access) {
      credentials[CredentialField.openAIAccountID] = accountID
    }

    return credentials
  }

  private func parseAPIKeyCredentials(
    from authObject: [String: Any]?,
    authKey: String,
    credentialField: String
  ) -> [String: String] {
    guard
      let authObject,
      let provider = authObject[authKey] as? [String: Any],
      (provider["type"] as? String) == "api",
      let key = provider["key"] as? String,
      !key.isEmpty
    else {
      return [:]
    }

    return [credentialField: key]
  }

  private func parseGoogleCredentials(from antigravityObject: [String: Any]?) -> [String: String] {
    guard
      let antigravityObject,
      let accounts = antigravityObject["accounts"] as? [[String: Any]],
      !accounts.isEmpty
    else {
      return [:]
    }

    let sortedAccounts = accounts.sorted { lhs, rhs in
      let lhsLastUsed = (lhs["lastUsed"] as? NSNumber)?.doubleValue ?? 0
      let rhsLastUsed = (rhs["lastUsed"] as? NSNumber)?.doubleValue ?? 0
      return lhsLastUsed > rhsLastUsed
    }

    guard
      let best = sortedAccounts.first(where: { account in
        let refresh = account["refreshToken"] as? String
        let project = (account["projectId"] as? String) ?? (account["managedProjectId"] as? String)
        return !(refresh ?? "").isEmpty && !(project ?? "").isEmpty
      })
    else {
      return [:]
    }

    let refreshToken = best["refreshToken"] as? String ?? ""
    let projectID = (best["projectId"] as? String) ?? (best["managedProjectId"] as? String) ?? ""

    var credentials: [String: String] = [
      CredentialField.googleRefreshToken: refreshToken,
      CredentialField.googleProjectID: projectID
    ]

    if let email = best["email"] as? String, !email.isEmpty {
      credentials[CredentialField.googleEmail] = email
    }

    return credentials
  }

  private func parseCopilotCredentials(auth: [String: Any]?, pat: [String: Any]?) -> [String: String] {
    var credentials: [String: String] = [:]

    if
      let pat,
      let token = pat["token"] as? String,
      !token.isEmpty,
      let username = pat["username"] as? String,
      !username.isEmpty
    {
      credentials[CredentialField.copilotPATToken] = token
      credentials[CredentialField.copilotUsername] = username

      if let tier = pat["tier"] as? String, !tier.isEmpty {
        credentials[CredentialField.copilotTier] = tier
      }
    }

    if
      let auth,
      let copilot = auth["github-copilot"] as? [String: Any],
      (copilot["type"] as? String) == "oauth"
    {
      let oauth = (copilot["refresh"] as? String) ?? (copilot["access"] as? String)
      if let oauth, !oauth.isEmpty {
        credentials[CredentialField.copilotOAuthToken] = oauth
      }
    }

    return credentials
  }

  private func extractOpenAIAccountID(from jwt: String) -> String? {
    let parts = jwt.split(separator: ".")
    guard parts.count == 3 else {
      return nil
    }

    var payload = String(parts[1])
      .replacingOccurrences(of: "-", with: "+")
      .replacingOccurrences(of: "_", with: "/")

    let remainder = payload.count % 4
    if remainder != 0 {
      payload += String(repeating: "=", count: 4 - remainder)
    }

    guard
      let data = Data(base64Encoded: payload),
      let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
      let auth = object["https://api.openai.com/auth"] as? [String: Any],
      let accountID = auth["chatgpt_account_id"] as? String,
      !accountID.isEmpty
    else {
      return nil
    }

    return accountID
  }
}

private enum SampleSnapshotFactory {
  static func make(now: Date) -> QuotaSnapshot {
    QuotaSnapshot(
      generatedAt: now,
      providers: [
        ProviderUsage(
          provider: .openAI,
          title: "OpenAI",
          subtitle: "plus",
          metrics: [
            UsageMetric(
              id: "primary",
              label: "3-hour limit",
              remainingPercent: 72,
              usedDisplay: "28",
              totalDisplay: "100",
              resetIn: "1h 42m"
            ),
            UsageMetric(
              id: "secondary",
              label: "7-day limit",
              remainingPercent: 61,
              usedDisplay: "39",
              totalDisplay: "100",
              resetIn: "2d 3h"
            )
          ],
          maxUsagePercent: 39,
          fetchedAt: now
        ),
        ProviderUsage(
          provider: .zhipu,
          title: "Zhipu AI",
          subtitle: "Coding Plan",
          metrics: [
            UsageMetric(
              id: "tokens",
              label: "5-hour token limit",
              remainingPercent: 55,
              usedDisplay: "4.5M",
              totalDisplay: "10.0M",
              resetIn: "2h 10m"
            ),
            UsageMetric(
              id: "mcp",
              label: "MCP monthly quota",
              remainingPercent: 81,
              usedDisplay: "19",
              totalDisplay: "100"
            )
          ],
          maxUsagePercent: 45,
          fetchedAt: now
        ),
        ProviderUsage(
          provider: .googleAntigravity,
          title: "Google Cloud",
          subtitle: "workspace@example.com",
          metrics: [
            UsageMetric(
              id: "g3-pro",
              label: "G3 Pro",
              remainingPercent: 63,
              resetIn: "10h"
            )
          ],
          maxUsagePercent: 37,
          fetchedAt: now
        ),
        ProviderUsage(
          provider: .gitHubCopilot,
          title: "GitHub Copilot",
          subtitle: "pro",
          metrics: [
            UsageMetric(
              id: "premium",
              label: "Premium requests",
              remainingPercent: 58,
              usedDisplay: "126",
              totalDisplay: "300",
              resetIn: "4d 6h"
            )
          ],
          maxUsagePercent: 42,
          fetchedAt: now
        )
      ],
      failures: []
    )
  }

  static func makeHistory(now: Date) -> [QuotaSnapshot] {
    let baseSnapshots = [
      makeSnapshot(now: now.addingTimeInterval(-6 * 86_400), usageOffset: -18),
      makeSnapshot(now: now.addingTimeInterval(-5 * 86_400), usageOffset: -14),
      makeSnapshot(now: now.addingTimeInterval(-4 * 86_400), usageOffset: -11),
      makeSnapshot(now: now.addingTimeInterval(-3 * 86_400), usageOffset: -8),
      makeSnapshot(now: now.addingTimeInterval(-2 * 86_400), usageOffset: -5),
      makeSnapshot(now: now.addingTimeInterval(-86_400), usageOffset: -2),
      makeSnapshot(now: now, usageOffset: 0)
    ]

    return baseSnapshots.sorted { $0.generatedAt < $1.generatedAt }
  }

  private static func makeSnapshot(now: Date, usageOffset: Int) -> QuotaSnapshot {
    let clamp = { (value: Int) in max(0, min(100, value)) }

    return QuotaSnapshot(
      generatedAt: now,
      providers: [
        ProviderUsage(
          provider: .openAI,
          title: "OpenAI",
          subtitle: "plus",
          metrics: [
            UsageMetric(
              id: "primary",
              label: "3-hour limit",
              remainingPercent: clamp(72 + usageOffset),
              usedDisplay: "28",
              totalDisplay: "100",
              resetIn: "1h 42m"
            ),
            UsageMetric(
              id: "secondary",
              label: "7-day limit",
              remainingPercent: clamp(61 + usageOffset),
              usedDisplay: "39",
              totalDisplay: "100",
              resetIn: "2d 3h"
            )
          ],
          maxUsagePercent: 39,
          fetchedAt: now
        ),
        ProviderUsage(
          provider: .zhipu,
          title: "Zhipu AI",
          subtitle: "Coding Plan",
          metrics: [
            UsageMetric(
              id: "tokens",
              label: "5-hour token limit",
              remainingPercent: clamp(55 + usageOffset),
              usedDisplay: "4.5M",
              totalDisplay: "10.0M",
              resetIn: "2h 10m"
            ),
            UsageMetric(
              id: "mcp",
              label: "MCP monthly quota",
              remainingPercent: clamp(81 + usageOffset),
              usedDisplay: "19",
              totalDisplay: "100"
            )
          ],
          maxUsagePercent: 45,
          fetchedAt: now
        ),
        ProviderUsage(
          provider: .googleAntigravity,
          title: "Google Cloud",
          subtitle: "workspace@example.com",
          metrics: [
            UsageMetric(
              id: "g3-pro",
              label: "G3 Pro",
              remainingPercent: clamp(63 + usageOffset),
              resetIn: "10h"
            )
          ],
          maxUsagePercent: 37,
          fetchedAt: now
        ),
        ProviderUsage(
          provider: .gitHubCopilot,
          title: "GitHub Copilot",
          subtitle: "pro",
          metrics: [
            UsageMetric(
              id: "premium",
              label: "Premium requests",
              remainingPercent: clamp(58 + usageOffset),
              usedDisplay: "126",
              totalDisplay: "300",
              resetIn: "4d 6h"
            )
          ],
          maxUsagePercent: 42,
          fetchedAt: now
        )
      ],
      failures: []
    )
  }
}
