import Foundation
import SwiftUI
import AppKit
import UniformTypeIdentifiers
import WidgetKit
import QuotaCore

@MainActor
final class AppModel: ObservableObject {
  @Published var refreshIntervalMinutes: Int = 30
  @Published var widgetStyle: WidgetStyleSettings = .default
  @Published var providerStyleSettings: [QuotaProvider: ProviderStyleSettings]
  @Published var credentialStatuses: [ProviderCredentialStatus] = []
  @Published var authAccessGranted = false
  @Published var authAccessSummary = "OpenCode auth access not checked yet"
  @Published var authAccessDetail = ""
  @Published var snapshot: QuotaSnapshot?
  @Published var statusMessage: String = ""
  @Published var isRefreshing = false

  private let settingsStore: SettingsStore
  private let snapshotStore: SnapshotStore
  private let refreshService: RefreshService
  private let credentialLoader: OpenCodeCredentialLoader
  private let sandboxAccess: OpenCodeSandboxAccess

  init() {
    let baseDirectory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
      ?? FileManager.default.temporaryDirectory
    let urls: (settings: URL, snapshot: URL) = (
      baseDirectory.appendingPathComponent(SharedConstants.settingsFileName),
      baseDirectory.appendingPathComponent(SharedConstants.snapshotFileName)
    )

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
    self.providerStyleSettings = Dictionary(
      uniqueKeysWithValues: QuotaProvider.allCases.map {
        ($0, ProviderStyleSettings.defaultValue(for: $0))
      }
    )
  }

  func bootstrap() async {
    await loadConfiguration()

    do {
      snapshot = try loadSnapshotFromPreferredStore()
    } catch {
      statusMessage = "Could not load snapshot: \(error.localizedDescription)"
    }

    reloadCredentialStatuses()
  }

  func loadConfiguration() async {
    let settings: AppSettings
    do {
      settings = try loadSettingsFromPreferredStore()
    } catch {
      settings = .default
      statusMessage = "Could not load settings. Using defaults."
    }

    refreshIntervalMinutes = max(15, settings.refreshIntervalMinutes)
    widgetStyle = settings.widgetStyle
    providerStyleSettings = Dictionary(
      uniqueKeysWithValues: QuotaProvider.allCases.map { provider in
        (provider, settings.styleOverride(for: provider))
      }
    )
  }

  func saveConfiguration(showSuccessMessage: Bool = false) {
    do {
      let settings = currentSettings()

      try settingsStore.save(settings)
      let widgetSyncReady = syncSettingsToWidgetStore(settings)
      reloadWidgetTimelines()
      if !widgetSyncReady {
        statusMessage = "Settings saved locally. Widget sync unavailable (App Group access missing)."
      } else if showSuccessMessage {
        statusMessage = "Configuration saved"
      }
    } catch {
      statusMessage = "Save failed: \(error.localizedDescription)"
    }
  }

  func refreshNow() async {
    saveConfiguration()
    isRefreshing = true
    defer { isRefreshing = false }

    let loaded = credentialLoader.load(providerEnabled: allProvidersEnabled())
    credentialStatuses = loaded.statuses
    applyAuthAccess(loaded.authAccess)

    let enabledConfigs = loaded.runtimeConfigurations.filter(\.isEnabled)
    guard !enabledConfigs.isEmpty else {
      statusMessage = "No providers with readable credentials found in OpenCode config files."
      return
    }

    do {
      let refreshed = try await refreshService.refresh(configurations: enabledConfigs)
      let widgetSyncReady = syncSnapshotToWidgetStore(refreshed)
      reloadWidgetTimelines()
      snapshot = refreshed
      if widgetSyncReady {
        statusMessage = "Refreshed \(refreshed.providers.count) provider(s), \(refreshed.failures.count) failure(s)"
      } else {
        statusMessage = "Refreshed \(refreshed.providers.count) provider(s), \(refreshed.failures.count) failure(s). Widget sync unavailable (App Group access missing)."
      }
    } catch {
      statusMessage = "Refresh failed: \(error.localizedDescription)"
    }
  }

  func reloadCredentialStatuses() {
    let loaded = credentialLoader.load(providerEnabled: allProvidersEnabled())
    credentialStatuses = loaded.statuses
    applyAuthAccess(loaded.authAccess)
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
    saveConfiguration()

    if saved > 0, issues.isEmpty {
      statusMessage = "Granted access to \(saved) OpenCode config file(s)."
    } else if saved > 0 {
      statusMessage = "Granted access to \(saved) file(s). Issues: \(issues.joined(separator: " | "))"
    } else if !issues.isEmpty {
      statusMessage = issues.joined(separator: " | ")
    } else {
      statusMessage = "No matching OpenCode config files selected."
    }

    if saved > 0 {
      Task {
        await refreshNow()
      }
    }
  }

  func refreshIntervalBinding() -> Binding<Int> {
    Binding(
      get: { self.refreshIntervalMinutes },
      set: { newValue in
        self.refreshIntervalMinutes = max(15, newValue)
        self.saveConfiguration()
      }
    )
  }

  func widgetShowBackgroundBinding() -> Binding<Bool> {
    Binding(
      get: { self.widgetStyle.showBackground },
      set: { newValue in
        self.widgetStyle.showBackground = newValue
        self.saveConfiguration()
      }
    )
  }

  func widgetBackgroundStyleBinding() -> Binding<WidgetBackgroundStyle> {
    Binding(
      get: { self.widgetStyle.backgroundStyle },
      set: { newValue in
        self.widgetStyle.backgroundStyle = newValue
        self.saveConfiguration()
      }
    )
  }

  func widgetRingPaletteBinding() -> Binding<WidgetRingPalette> {
    Binding(
      get: { self.widgetStyle.ringPalette },
      set: { newValue in
        self.widgetStyle.ringPalette = newValue
        self.saveConfiguration()
      }
    )
  }

  func providerStyle(for provider: QuotaProvider) -> ProviderStyleSettings {
    providerStyleSettings[provider]
      ?? ProviderStyleSettings.defaultValue(for: provider, fallbackStyle: widgetStyle)
  }

  func effectiveStyle(for provider: QuotaProvider) -> WidgetStyleSettings {
    let providerStyle = providerStyle(for: provider)
    return providerStyle.useCustomStyle ? providerStyle.style : widgetStyle
  }

  func providerOverrideEnabledBinding(for provider: QuotaProvider) -> Binding<Bool> {
    Binding(
      get: { self.providerStyle(for: provider).useCustomStyle },
      set: { newValue in
        self.updateProviderStyle(for: provider) { style in
          style.useCustomStyle = newValue
          if newValue {
            style.style = self.widgetStyle
          }
        }
      }
    )
  }

  func providerShowBackgroundBinding(for provider: QuotaProvider) -> Binding<Bool> {
    Binding(
      get: { self.providerStyle(for: provider).style.showBackground },
      set: { newValue in
        self.updateProviderStyle(for: provider) { style in
          style.style.showBackground = newValue
        }
      }
    )
  }

  func providerBackgroundStyleBinding(for provider: QuotaProvider) -> Binding<WidgetBackgroundStyle> {
    Binding(
      get: { self.providerStyle(for: provider).style.backgroundStyle },
      set: { newValue in
        self.updateProviderStyle(for: provider) { style in
          style.style.backgroundStyle = newValue
        }
      }
    )
  }

  func providerRingPaletteBinding(for provider: QuotaProvider) -> Binding<WidgetRingPalette> {
    Binding(
      get: { self.providerStyle(for: provider).style.ringPalette },
      set: { newValue in
        self.updateProviderStyle(for: provider) { style in
          style.style.ringPalette = newValue
        }
      }
    )
  }

  func status(for provider: QuotaProvider) -> ProviderCredentialStatus? {
    credentialStatuses.first(where: { $0.provider == provider })
  }

  func isProviderAvailable(_ provider: QuotaProvider) -> Bool {
    status(for: provider)?.available ?? false
  }

  private func allProvidersEnabled() -> [QuotaProvider: Bool] {
    Dictionary(uniqueKeysWithValues: QuotaProvider.allCases.map { ($0, true) })
  }

  private func applyAuthAccess(_ status: OpenCodeAuthAccessStatus) {
    authAccessGranted = status.granted
    authAccessSummary = status.summary
    authAccessDetail = status.detail
  }

  private func updateProviderStyle(
    for provider: QuotaProvider,
    mutate: (inout ProviderStyleSettings) -> Void
  ) {
    var style = providerStyle(for: provider)
    mutate(&style)
    providerStyleSettings[provider] = style
    saveConfiguration()
  }

  private func loadSettingsFromPreferredStore() throws -> AppSettings {
    return try settingsStore.load()
  }

  private func loadSnapshotFromPreferredStore() throws -> QuotaSnapshot? {
    return try snapshotStore.load()
  }

  private func currentSettings() -> AppSettings {
    AppSettings(
      refreshIntervalMinutes: refreshIntervalMinutes,
      providers: QuotaProvider.allCases.map {
        ProviderSettings(provider: $0, isEnabled: true)
      },
      widgetStyle: widgetStyle,
      providerStyleSettings: QuotaProvider.allCases.map { provider in
        providerStyle(for: provider)
      }
    )
  }

  @discardableResult
  private func syncSettingsToWidgetStore(_ settings: AppSettings) -> Bool {
    guard let appGroupStore = appGroupSettingsStore() else { return false }

    do {
      try appGroupStore.save(settings)
      return true
    } catch {
      return false
    }
  }

  @discardableResult
  private func syncSnapshotToWidgetStore(_ snapshot: QuotaSnapshot) -> Bool {
    guard let appGroupStore = appGroupSnapshotStore() else { return false }

    do {
      try appGroupStore.save(snapshot)
      return true
    } catch {
      return false
    }
  }

  private func appGroupSettingsStore() -> SettingsStore? {
    guard let url = try? SharedPaths.settingsFileURL() else { return nil }
    return SettingsStore(fileURL: url)
  }

  private func appGroupSnapshotStore() -> SnapshotStore? {
    guard let url = try? SharedPaths.snapshotFileURL() else { return nil }
    return SnapshotStore(fileURL: url)
  }

  private func reloadWidgetTimelines() {
    for kind in SharedConstants.allWidgetKinds {
      WidgetCenter.shared.reloadTimelines(ofKind: kind)
    }
    WidgetCenter.shared.reloadAllTimelines()

    DispatchQueue.main.asyncAfter(deadline: .now() + 0.75) {
      for kind in SharedConstants.allWidgetKinds {
        WidgetCenter.shared.reloadTimelines(ofKind: kind)
      }
      WidgetCenter.shared.reloadAllTimelines()
    }
  }
}
