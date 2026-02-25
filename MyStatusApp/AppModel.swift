import Foundation
import SwiftUI
import AppKit
import UniformTypeIdentifiers
import QuotaCore

@MainActor
final class AppModel: ObservableObject {
  @Published var refreshIntervalMinutes: Int = 30
  @Published var providerEnabled: [QuotaProvider: Bool]
  @Published var credentialStatuses: [ProviderCredentialStatus] = []
  @Published var snapshot: QuotaSnapshot?
  @Published var statusMessage: String = ""
  @Published var isRefreshing = false

  private let settingsStore: SettingsStore
  private let snapshotStore: SnapshotStore
  private let refreshService: RefreshService
  private let credentialLoader: OpenCodeCredentialLoader
  private let sandboxAccess: OpenCodeSandboxAccess

  init() {
    let urls: (settings: URL, snapshot: URL) = {
      do {
        return (try SharedPaths.settingsFileURL(), try SharedPaths.snapshotFileURL())
      } catch {
        let fallback = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
          ?? FileManager.default.temporaryDirectory
        return (
          fallback.appendingPathComponent(SharedConstants.settingsFileName),
          fallback.appendingPathComponent(SharedConstants.snapshotFileName)
        )
      }
    }()

    let settingsStore = SettingsStore(fileURL: urls.settings)
    let snapshotStore = SnapshotStore(fileURL: urls.snapshot)
    let sandboxAccess = OpenCodeSandboxAccess()

    self.settingsStore = settingsStore
    self.snapshotStore = snapshotStore
    self.refreshService = RefreshService(
      coordinator: QuotaCoordinator.live(),
      snapshotStore: snapshotStore
    )
    self.sandboxAccess = sandboxAccess
    self.credentialLoader = OpenCodeCredentialLoader(sandboxAccess: sandboxAccess)
    self.providerEnabled = Dictionary(uniqueKeysWithValues: QuotaProvider.allCases.map { ($0, true) })
  }

  func bootstrap() async {
    await loadConfiguration()

    do {
      snapshot = try snapshotStore.load()
    } catch {
      statusMessage = "Could not load snapshot: \(error.localizedDescription)"
    }

    reloadCredentialStatuses()
  }

  func loadConfiguration() async {
    let settings: AppSettings
    do {
      settings = try settingsStore.load()
    } catch {
      settings = .default
      statusMessage = "Could not load settings. Using defaults."
    }

    refreshIntervalMinutes = max(15, settings.refreshIntervalMinutes)
    providerEnabled = Dictionary(
      uniqueKeysWithValues: QuotaProvider.allCases.map { provider in
        (provider, settings.isEnabled(provider))
      }
    )
  }

  func saveConfiguration() async {
    do {
      let settings = AppSettings(
        refreshIntervalMinutes: refreshIntervalMinutes,
        providers: QuotaProvider.allCases.map {
          ProviderSettings(provider: $0, isEnabled: providerEnabled[$0] ?? true)
        }
      )

      try settingsStore.save(settings)
      statusMessage = "Configuration saved"
    } catch {
      statusMessage = "Save failed: \(error.localizedDescription)"
    }
  }

  func refreshNow() async {
    await saveConfiguration()
    isRefreshing = true
    defer { isRefreshing = false }

    let loaded = credentialLoader.load(providerEnabled: providerEnabled)
    credentialStatuses = loaded.statuses

    let enabledConfigs = loaded.runtimeConfigurations.filter(\.isEnabled)
    guard !enabledConfigs.isEmpty else {
      statusMessage = "No enabled providers with credentials found in OpenCode config files."
      return
    }

    do {
      let refreshed = try await refreshService.refresh(configurations: loaded.runtimeConfigurations)
      snapshot = refreshed
      statusMessage = "Refreshed \(refreshed.providers.count) provider(s), \(refreshed.failures.count) failure(s)"
    } catch {
      statusMessage = "Refresh failed: \(error.localizedDescription)"
    }
  }

  func reloadCredentialStatuses() {
    credentialStatuses = credentialLoader.load(providerEnabled: providerEnabled).statuses
  }

  func grantOpenCodeFileAccess() {
    let panel = NSOpenPanel()
    panel.title = "Grant Access to OpenCode Config Files"
    panel.message = "Select auth.json, antigravity-accounts.json, and/or copilot-quota-token.json."
    panel.canChooseDirectories = false
    panel.canChooseFiles = true
    panel.allowsMultipleSelection = true
    panel.directoryURL = URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true)
    panel.allowedContentTypes = [UTType.json]

    guard panel.runModal() == .OK else {
      return
    }

    var saved = 0
    var issues: [String] = []

    for url in panel.urls {
      guard let key = OpenCodeSandboxAccess.bookmarkKey(forFileName: url.lastPathComponent) else {
        issues.append("Ignored \(url.lastPathComponent)")
        continue
      }

      do {
        try sandboxAccess.saveBookmark(for: key, url: url)
        saved += 1
      } catch {
        issues.append("\(url.lastPathComponent): \(error.localizedDescription)")
      }
    }

    reloadCredentialStatuses()

    if saved > 0, issues.isEmpty {
      statusMessage = "Granted access to \(saved) OpenCode config file(s)."
    } else if saved > 0 {
      statusMessage = "Granted access to \(saved) file(s). Issues: \(issues.joined(separator: " | "))"
    } else if !issues.isEmpty {
      statusMessage = issues.joined(separator: " | ")
    } else {
      statusMessage = "No matching OpenCode config files selected."
    }
  }

  func enabledBinding(for provider: QuotaProvider) -> Binding<Bool> {
    Binding(
      get: { self.providerEnabled[provider] ?? true },
      set: { newValue in
        self.providerEnabled[provider] = newValue
        self.reloadCredentialStatuses()
      }
    )
  }

  func status(for provider: QuotaProvider) -> ProviderCredentialStatus? {
    credentialStatuses.first(where: { $0.provider == provider })
  }
}
