import Foundation
import Darwin
import QuotaCore

final class OpenCodeSandboxAccess {
  enum BookmarkKey: String {
    case authFile = "sandbox.bookmark.authFile"
    case antigravityFile = "sandbox.bookmark.antigravityFile"
    case copilotPATFile = "sandbox.bookmark.copilotPATFile"
  }

  private let defaults: UserDefaults

  private struct ResolvedAccess {
    let url: URL
    let requiresSecurityScope: Bool
  }

  init(defaults: UserDefaults = .standard) {
    self.defaults = defaults
  }

  func saveBookmark(for key: BookmarkKey, url: URL) throws {
    let data = try url.bookmarkData(
      options: [.withSecurityScope, .securityScopeAllowOnlyReadAccess],
      includingResourceValuesForKeys: nil,
      relativeTo: nil
    )
    let pathKey = bookmarkPathKey(for: key)
    defaults.set(data, forKey: key.rawValue)
    defaults.set(url.path, forKey: pathKey)
  }

  func resolveURL(for key: BookmarkKey) -> URL? {
    resolveAccess(for: key)?.url
  }

  func resolveCandidate(for key: BookmarkKey) -> (url: URL, requiresSecurityScope: Bool)? {
    guard let resolved = resolveAccess(for: key) else {
      return nil
    }
    return (resolved.url, resolved.requiresSecurityScope)
  }

  private func resolveAccess(for key: BookmarkKey) -> ResolvedAccess? {
    let pathKey = bookmarkPathKey(for: key)
    let fallbackPath = defaults.string(forKey: pathKey)
    let primaryData = defaults.data(forKey: key.rawValue)
    guard let data = primaryData else {
      if let fallbackPath, isAllowedFallbackPath(fallbackPath, for: key) {
        return ResolvedAccess(url: URL(fileURLWithPath: fallbackPath), requiresSecurityScope: false)
      }
      return nil
    }

    var stale = false
    guard let url = try? URL(
      resolvingBookmarkData: data,
      options: [.withSecurityScope, .withoutUI],
      relativeTo: nil,
      bookmarkDataIsStale: &stale
    ) else {
      if let fallbackPath, isAllowedFallbackPath(fallbackPath, for: key) {
        return ResolvedAccess(url: URL(fileURLWithPath: fallbackPath), requiresSecurityScope: false)
      }
      return nil
    }

    if stale {
      try? saveBookmark(for: key, url: url)
    }

    if !isAllowedFallbackPath(url.path, for: key) {
      if let fallbackPath, isAllowedFallbackPath(fallbackPath, for: key) {
        return ResolvedAccess(url: URL(fileURLWithPath: fallbackPath), requiresSecurityScope: false)
      }

      defaults.removeObject(forKey: key.rawValue)
      defaults.removeObject(forKey: pathKey)
      return nil
    }

    if fallbackPath == nil {
      defaults.set(url.path, forKey: pathKey)
    }

    return ResolvedAccess(url: url, requiresSecurityScope: true)
  }

  func hasStoredBookmark(for key: BookmarkKey) -> Bool {
    defaults.data(forKey: key.rawValue) != nil
  }

  private func bookmarkPathKey(for key: BookmarkKey) -> String {
    "\(key.rawValue).path"
  }

  private func isAllowedFallbackPath(_ path: String, for key: BookmarkKey) -> Bool {
    let normalized = path.lowercased()
    switch key {
    case .authFile:
      return normalized.hasSuffix("/.local/share/opencode/auth.json")
        || normalized.hasSuffix("/.config/opencode/auth.json")
    case .antigravityFile:
      return normalized.hasSuffix("/.config/opencode/antigravity-accounts.json")
    case .copilotPATFile:
      return normalized.hasSuffix("/.config/opencode/copilot-quota-token.json")
    }
  }

  static func bookmarkKey(forFileName fileName: String) -> BookmarkKey? {
    switch fileName {
    case "auth.json":
      return .authFile
    case "antigravity-accounts.json":
      return .antigravityFile
    case "copilot-quota-token.json":
      return .copilotPATFile
    default:
      return nil
    }
  }
}

struct ProviderCredentialStatus: Identifiable, Hashable {
  let provider: QuotaProvider
  let available: Bool
  let enabled: Bool
  let source: String
  let detail: String

  var id: String { provider.rawValue }
}

struct OpenCodeAuthAccessStatus: Hashable {
  let granted: Bool
  let summary: String
  let detail: String
}

struct OpenCodeCredentialLoadResult {
  let runtimeConfigurations: [ProviderRuntimeConfiguration]
  let statuses: [ProviderCredentialStatus]
  let authAccess: OpenCodeAuthAccessStatus
}

final class OpenCodeCredentialLoader {
  private struct CandidateURL {
    let url: URL
    let requiresSecurityScope: Bool
  }

  private struct JSONLookup {
    let object: [String: Any]?
    let sourceSummary: String
    let diagnostics: String
  }

  private let fileManager: FileManager
  private let sandboxAccess: OpenCodeSandboxAccess

  init(
    fileManager: FileManager = .default,
    sandboxAccess: OpenCodeSandboxAccess = OpenCodeSandboxAccess()
  ) {
    self.fileManager = fileManager
    self.sandboxAccess = sandboxAccess
  }

  func load(providerEnabled: [QuotaProvider: Bool]) -> OpenCodeCredentialLoadResult {
    let authLookup = loadJSONFromCandidates(authCandidates(), label: "auth.json")
    let antigravityLookup = loadJSONFromCandidates(
      antigravityCandidates(),
      label: "antigravity-accounts.json"
    )

    let authAccess = authAccessStatus(from: authLookup)
    let copilotPATLookup = loadJSONFromCandidates(
      copilotPATCandidates(),
      label: "copilot-quota-token.json"
    )

    var configurations: [ProviderRuntimeConfiguration] = []
    var statuses: [ProviderCredentialStatus] = []

    for provider in QuotaProvider.allCases {
      let enabled = providerEnabled[provider] ?? true
      let credentials: [String: String]
      let source: String
      let detail: String

      switch provider {
      case .openAI:
        let data = parseOpenAICredentials(from: authLookup.object)
        credentials = data.credentials
        source = authLookup.sourceSummary
        detail = mergeDetails(parseDetail: data.detail, lookupDiagnostics: authLookup.diagnostics)
      case .zhipu:
        let data = parseAPIKeyCredentials(
          from: authLookup.object,
          authKey: "zhipuai-coding-plan",
          credentialField: CredentialField.zhipuAPIKey,
          providerName: provider.displayName
        )
        credentials = data.credentials
        source = authLookup.sourceSummary
        detail = mergeDetails(parseDetail: data.detail, lookupDiagnostics: authLookup.diagnostics)
      case .zai:
        let data = parseAPIKeyCredentials(
          from: authLookup.object,
          authKey: "zai-coding-plan",
          credentialField: CredentialField.zaiAPIKey,
          providerName: provider.displayName
        )
        credentials = data.credentials
        source = authLookup.sourceSummary
        detail = mergeDetails(parseDetail: data.detail, lookupDiagnostics: authLookup.diagnostics)
      case .googleAntigravity:
        let data = parseGoogleCredentials(from: antigravityLookup.object)
        credentials = data.credentials
        source = antigravityLookup.sourceSummary
        detail = mergeDetails(parseDetail: data.detail, lookupDiagnostics: antigravityLookup.diagnostics)
      case .gitHubCopilot:
        let data = parseCopilotCredentials(auth: authLookup.object, pat: copilotPATLookup.object)
        credentials = data.credentials
        source = "PAT: \(copilotPATLookup.sourceSummary) | OAuth: \(authLookup.sourceSummary)"
        detail = [
          data.detail,
          "PAT: \(copilotPATLookup.diagnostics)",
          "OAuth: \(authLookup.diagnostics)"
        ].joined(separator: " | ")
      }

      let available = !credentials.isEmpty
      configurations.append(
        ProviderRuntimeConfiguration(
          provider: provider,
          isEnabled: enabled && available,
          credentials: credentials
        )
      )

      statuses.append(
        ProviderCredentialStatus(
          provider: provider,
          available: available,
          enabled: enabled,
          source: source,
          detail: detail
        )
      )
    }

    return OpenCodeCredentialLoadResult(
      runtimeConfigurations: configurations,
      statuses: statuses,
      authAccess: authAccess
    )
  }

  private func authAccessStatus(from lookup: JSONLookup) -> OpenCodeAuthAccessStatus {
    if lookup.object != nil {
      return OpenCodeAuthAccessStatus(
        granted: true,
        summary: "OpenCode auth access granted",
        detail: lookup.diagnostics
      )
    }

    if lookup.sourceSummary == "Existing auth.json file found" {
      return OpenCodeAuthAccessStatus(
        granted: false,
        summary: "auth.json exists but is not readable in this app sandbox",
        detail: "Use Grant File Access and select ~/.local/share/opencode/auth.json. \(lookup.diagnostics)"
      )
    }

    return OpenCodeAuthAccessStatus(
      granted: false,
      summary: "No readable auth.json found",
      detail: "Expected location: ~/.local/share/opencode/auth.json. \(lookup.diagnostics)"
    )
  }

  private func mergeDetails(parseDetail: String, lookupDiagnostics: String) -> String {
    "\(parseDetail) | \(lookupDiagnostics)"
  }

  private func parseOpenAICredentials(from authObject: [String: Any]?) -> (credentials: [String: String], detail: String) {
    guard
      let authObject,
      let openAI = authObject["openai"] as? [String: Any],
      (openAI["type"] as? String) == "oauth",
      let access = openAI["access"] as? String,
      !access.isEmpty
    else {
      return ([:], "No OpenAI OAuth token found")
    }

    var credentials: [String: String] = [CredentialField.openAIAccessToken: access]
    if let accountID = extractOpenAIAccountID(from: access) {
      credentials[CredentialField.openAIAccountID] = accountID
    }

    return (credentials, "Loaded OAuth access token")
  }

  private func parseAPIKeyCredentials(
    from authObject: [String: Any]?,
    authKey: String,
    credentialField: String,
    providerName: String
  ) -> (credentials: [String: String], detail: String) {
    guard
      let authObject,
      let provider = authObject[authKey] as? [String: Any],
      (provider["type"] as? String) == "api",
      let key = provider["key"] as? String,
      !key.isEmpty
    else {
      return ([:], "No \(providerName) API key found")
    }

    return ([credentialField: key], "Loaded API key")
  }

  private func parseGoogleCredentials(from antigravityObject: [String: Any]?) -> (credentials: [String: String], detail: String) {
    guard
      let antigravityObject,
      let accounts = antigravityObject["accounts"] as? [[String: Any]],
      !accounts.isEmpty
    else {
      return ([:], "No antigravity accounts found")
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
      return ([:], "Accounts exist but no usable refresh token + project ID")
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

    return (credentials, "Loaded most recently used antigravity account")
  }

  private func parseCopilotCredentials(
    auth: [String: Any]?,
    pat: [String: Any]?
  ) -> (credentials: [String: String], detail: String) {
    var credentials: [String: String] = [:]
    var parts: [String] = []

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
        parts.append("Loaded PAT config with tier")
      } else {
        parts.append("Loaded PAT config (no tier)")
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
        parts.append("Loaded OAuth token")
      }
    }

    if credentials.isEmpty {
      return ([:], "No Copilot credentials found")
    }

    return (credentials, parts.joined(separator: " + "))
  }

  private func loadJSONFromCandidates(_ candidates: [CandidateURL], label: String) -> JSONLookup {
    let uniqueCandidates = uniqueCandidates(candidates)
    if uniqueCandidates.isEmpty {
      return JSONLookup(
        object: nil,
        sourceSummary: "No \(label) file found",
        diagnostics: "No granted file access for \(label). Use Grant File Access."
      )
    }

    var existingFileErrors: [String] = []
    var checkedPaths: [String] = []

    for candidate in uniqueCandidates {
      let url = candidate.url
      let path = url.path
      checkedPaths.append(path)

      let scoped = candidate.requiresSecurityScope && url.startAccessingSecurityScopedResource()
      defer {
        if scoped {
          url.stopAccessingSecurityScopedResource()
        }
      }

      do {
        if (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true {
          continue
        }

        let data = try Data(contentsOf: url)
        let object = try JSONSerialization.jsonObject(with: data)
        guard let dictionary = object as? [String: Any] else {
          existingFileErrors.append("\(path): JSON top-level is not an object")
          continue
        }

        return JSONLookup(
          object: dictionary,
          sourceSummary: path,
          diagnostics: "Loaded \(label) from \(path)"
        )
      } catch {
        if fileManager.fileExists(atPath: path) || scoped {
          if fileManager.isReadableFile(atPath: path) {
            existingFileErrors.append("\(path): \(error.localizedDescription)")
          } else {
            existingFileErrors.append("\(path): file exists but is not readable (sandbox/permissions)")
          }
        } else if (error as NSError).code != NSFileReadNoSuchFileError {
          existingFileErrors.append("\(path): \(error.localizedDescription)")
        }
      }
    }

    if !existingFileErrors.isEmpty {
      return JSONLookup(
        object: nil,
        sourceSummary: "Existing \(label) file found",
        diagnostics: existingFileErrors.joined(separator: " | ")
      )
    }

    return JSONLookup(
      object: nil,
      sourceSummary: "No \(label) file found",
      diagnostics: "Checked paths: \(checkedPaths.joined(separator: ", "))"
    )
  }

  private func uniqueCandidates(_ candidates: [CandidateURL]) -> [CandidateURL] {
    var merged: [String: CandidateURL] = [:]
    var order: [String] = []

    for candidate in candidates {
      let key = candidate.url.path
      if let existing = merged[key] {
        merged[key] = CandidateURL(
          url: existing.url,
          requiresSecurityScope: existing.requiresSecurityScope || candidate.requiresSecurityScope
        )
      } else {
        merged[key] = candidate
        order.append(key)
      }
    }

    return order.compactMap { merged[$0] }
  }

  private func uniquePaths(_ urls: [URL]) -> [URL] {
    var seen: Set<String> = []
    var output: [URL] = []

    for url in urls {
      let key = url.path
      if seen.contains(key) {
        continue
      }
      seen.insert(key)
      output.append(url)
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

    if let resolved = sandboxAccess.resolveCandidate(for: .authFile) {
      candidates.append(
        CandidateURL(
          url: resolved.url,
          requiresSecurityScope: resolved.requiresSecurityScope
        )
      )
    }

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

    if let resolved = sandboxAccess.resolveCandidate(for: .antigravityFile) {
      candidates.append(
        CandidateURL(
          url: resolved.url,
          requiresSecurityScope: resolved.requiresSecurityScope
        )
      )
    }

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

    if let resolved = sandboxAccess.resolveCandidate(for: .copilotPATFile) {
      candidates.append(
        CandidateURL(
          url: resolved.url,
          requiresSecurityScope: resolved.requiresSecurityScope
        )
      )
    }

    return candidates
  }

  private func xdgPath(envKey: String, tail: String) -> URL? {
    guard
      let root = ProcessInfo.processInfo.environment[envKey],
      !root.isEmpty
    else {
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

    if
      let envHome = ProcessInfo.processInfo.environment["HOME"],
      !envHome.isEmpty
    {
      homes.append(URL(fileURLWithPath: envHome, isDirectory: true))
    }

    homes.append(fileManager.homeDirectoryForCurrentUser)

    let username = NSUserName()
    if !username.isEmpty {
      homes.append(URL(fileURLWithPath: "/Users/\(username)", isDirectory: true))
    }

    return uniquePaths(homes)
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

  private func extractOpenAIAccountID(from jwt: String) -> String? {
    let parts = jwt.split(separator: ".")
    guard parts.count == 3 else { return nil }

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
