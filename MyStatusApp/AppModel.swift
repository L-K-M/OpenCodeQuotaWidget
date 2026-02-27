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
  @Published var widgetVisibility: WidgetVisibilitySettings = .default
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
  private var cachedAppGroupSettingsStore: SettingsStore?
  private var cachedAppGroupSnapshotStore: SnapshotStore?
  private var autoRefreshTask: Task<Void, Never>?

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
    restartAutoRefreshLoop()

    if shouldRefreshOnBootstrap() {
      await refreshNow()
    }
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
    widgetVisibility = settings.widgetVisibility
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
      if widgetSyncReady {
        reloadWidgetTimelines()
      }
      if !widgetSyncReady {
        statusMessage = "Settings saved locally. Widget sync unavailable."
      } else if showSuccessMessage {
        statusMessage = "Configuration saved"
      }
    } catch {
      statusMessage = "Save failed: \(error.localizedDescription)"
    }
  }

  func refreshNow() async {
    guard !isRefreshing else {
      return
    }

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
      if widgetSyncReady {
        reloadWidgetTimelines()
      }
      snapshot = refreshed
      if widgetSyncReady {
        statusMessage = "Refreshed \(refreshed.providers.count) provider(s), \(refreshed.failures.count) failure(s)"
      } else {
        statusMessage = "Refreshed \(refreshed.providers.count) provider(s), \(refreshed.failures.count) failure(s). Widget sync unavailable."
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
        self.restartAutoRefreshLoop()
      }
    )
  }

  func widgetVisibilityBinding(
    for keyPath: WritableKeyPath<WidgetVisibilitySettings, Bool>
  ) -> Binding<Bool> {
    Binding(
      get: { self.widgetVisibility[keyPath: keyPath] },
      set: { newValue in
        self.widgetVisibility[keyPath: keyPath] = newValue
        self.saveConfiguration()
      }
    )
  }

  func widgetVisibilityIntBinding(
    for keyPath: WritableKeyPath<WidgetVisibilitySettings, Int>,
    range: ClosedRange<Int>
  ) -> Binding<Int> {
    Binding(
      get: { self.widgetVisibility[keyPath: keyPath] },
      set: { newValue in
        let clamped = min(max(newValue, range.lowerBound), range.upperBound)
        self.widgetVisibility[keyPath: keyPath] = clamped
        self.saveConfiguration()
      }
    )
  }

  func widgetBackgroundColorBinding() -> Binding<Color> {
    Binding(
      get: { Self.color(fromHex: self.widgetStyle.backgroundHexColor) },
      set: { newValue in
        self.widgetStyle.backgroundHexColor = Self.hexColor(from: newValue, allowTransparency: true)
        self.widgetStyle.useTransparentBackground = false
        self.saveConfiguration()
      }
    )
  }

  func widgetTransparentBackgroundBinding() -> Binding<Bool> {
    Binding(
      get: { self.widgetStyle.useTransparentBackground },
      set: { newValue in
        self.widgetStyle.useTransparentBackground = newValue
        self.saveConfiguration()
      }
    )
  }

  func widgetRingColorBinding(
    for role: WidgetRingColorRole,
    layer: WidgetRingLayer
  ) -> Binding<Color> {
    Binding(
      get: {
        let hex = self.widgetStyle.ringColors.hexColor(for: role, layer: layer)
        return Self.color(fromHex: hex)
      },
      set: { newValue in
        guard let hex = Self.hexColor(from: newValue, allowTransparency: false) else {
          return
        }

        self.widgetStyle.ringColors.setHexColor(hex, for: role, layer: layer)
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

    guard providerStyle.useCustomStyle else {
      return widgetStyle
    }

    return WidgetStyleSettings(
      backgroundHexColor: providerStyle.style.backgroundHexColor ?? widgetStyle.backgroundHexColor,
      ringColors: providerStyle.style.ringColors,
      useTransparentBackground: providerStyle.style.useTransparentBackground
    )
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

  func providerBackgroundColorBinding(for provider: QuotaProvider) -> Binding<Color> {
    Binding(
      get: {
        let providerStyle = self.providerStyle(for: provider).style
        let resolvedHex = providerStyle.backgroundHexColor ?? self.widgetStyle.backgroundHexColor
        return Self.color(fromHex: resolvedHex)
      },
      set: { newValue in
        self.updateProviderStyle(for: provider) { style in
          style.style.backgroundHexColor = Self.hexColor(from: newValue, allowTransparency: true)
          style.style.useTransparentBackground = false
        }
      }
    )
  }

  func providerTransparentBackgroundBinding(for provider: QuotaProvider) -> Binding<Bool> {
    Binding(
      get: { self.providerStyle(for: provider).style.useTransparentBackground },
      set: { newValue in
        self.updateProviderStyle(for: provider) { style in
          style.style.useTransparentBackground = newValue
        }
      }
    )
  }

  func providerRingColorBinding(
    for provider: QuotaProvider,
    role: WidgetRingColorRole,
    layer: WidgetRingLayer
  ) -> Binding<Color> {
    Binding(
      get: {
        let hex = self.providerStyle(for: provider).style.ringColors.hexColor(for: role, layer: layer)
        return Self.color(fromHex: hex)
      },
      set: { newValue in
        guard let hex = Self.hexColor(from: newValue, allowTransparency: false) else {
          return
        }

        self.updateProviderStyle(for: provider) { style in
          style.style.ringColors.setHexColor(hex, for: role, layer: layer)
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
      },
      widgetVisibility: widgetVisibility
    )
  }

  private func restartAutoRefreshLoop() {
    autoRefreshTask?.cancel()

    autoRefreshTask = Task { [weak self] in
      while !Task.isCancelled {
        guard let self else {
          return
        }

        let intervalNanoseconds = await self.autoRefreshIntervalNanoseconds()
        do {
          try await Task.sleep(nanoseconds: intervalNanoseconds)
        } catch {
          return
        }

        if Task.isCancelled {
          return
        }

        await self.refreshNow()
      }
    }
  }

  private func autoRefreshIntervalNanoseconds() -> UInt64 {
    let seconds = UInt64(max(15, refreshIntervalMinutes) * 60)
    return seconds * 1_000_000_000
  }

  private func shouldRefreshOnBootstrap(now: Date = Date()) -> Bool {
    guard let snapshot else {
      return true
    }

    let maxAgeSeconds = TimeInterval(max(15, refreshIntervalMinutes) * 60)
    return now.timeIntervalSince(snapshot.generatedAt) >= maxAgeSeconds
  }

  private static func color(fromHex hex: String?) -> Color {
    guard let components = parseHexColor(hex) else {
      return .clear
    }

    return Color(
      red: components.red,
      green: components.green,
      blue: components.blue,
      opacity: components.alpha
    )
  }

  private static func hexColor(from color: Color, allowTransparency: Bool) -> String? {
    guard let components = rgbaComponents(from: color) else {
      return nil
    }

    if allowTransparency && components.alpha <= 0.01 {
      return nil
    }

    let red = clampColorByte(components.red)
    let green = clampColorByte(components.green)
    let blue = clampColorByte(components.blue)

    if allowTransparency {
      let alpha = clampColorByte(components.alpha)
      return String(format: "#%02X%02X%02X%02X", red, green, blue, alpha)
    }

    return String(format: "#%02X%02X%02X", red, green, blue)
  }

  private static func rgbaComponents(from color: Color) -> (
    red: Double,
    green: Double,
    blue: Double,
    alpha: Double
  )? {
    let nsColor = NSColor(color)
    guard let converted = nsColor.usingColorSpace(.extendedSRGB) ?? nsColor.usingColorSpace(.sRGB) else {
      return nil
    }

    return (
      red: Double(converted.redComponent),
      green: Double(converted.greenComponent),
      blue: Double(converted.blueComponent),
      alpha: Double(converted.alphaComponent)
    )
  }

  private static func parseHexColor(_ value: String?) -> (
    red: Double,
    green: Double,
    blue: Double,
    alpha: Double
  )? {
    guard var raw = value?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else {
      return nil
    }

    if raw.hasPrefix("#") {
      raw.removeFirst()
    }

    if raw.count == 3 || raw.count == 4 {
      raw = raw.map { "\($0)\($0)" }.joined()
    }

    guard raw.count == 6 || raw.count == 8, let parsed = UInt64(raw, radix: 16) else {
      return nil
    }

    if raw.count == 6 {
      let red = Double((parsed >> 16) & 0xFF) / 255.0
      let green = Double((parsed >> 8) & 0xFF) / 255.0
      let blue = Double(parsed & 0xFF) / 255.0
      return (red: red, green: green, blue: blue, alpha: 1)
    }

    let red = Double((parsed >> 24) & 0xFF) / 255.0
    let green = Double((parsed >> 16) & 0xFF) / 255.0
    let blue = Double((parsed >> 8) & 0xFF) / 255.0
    let alpha = Double(parsed & 0xFF) / 255.0
    return (red: red, green: green, blue: blue, alpha: alpha)
  }

  private static func clampColorByte(_ value: Double) -> Int {
    Int((max(0, min(1, value)) * 255.0).rounded())
  }

  @discardableResult
  private func syncSettingsToWidgetStore(_ settings: AppSettings) -> Bool {
    for attempt in 1...2 {
      guard let appGroupStore = appGroupSettingsStore() else {
        print("[OpenCodeQuota] Settings sync failed: no App Group settings store available")
        invalidateAppGroupStores()
        continue
      }

      do {
        try appGroupStore.save(settings)
        print("[OpenCodeQuota] Settings synced to widget store successfully")
        return true
      } catch {
        print("[OpenCodeQuota] Settings sync attempt \(attempt) failed: \(error.localizedDescription)")
        invalidateAppGroupStores()
      }
    }

    return false
  }

  @discardableResult
  private func syncSnapshotToWidgetStore(_ snapshot: QuotaSnapshot) -> Bool {
    for attempt in 1...2 {
      guard let appGroupStore = appGroupSnapshotStore() else {
        print("[OpenCodeQuota] Widget sync failed: no App Group store available")
        invalidateAppGroupStores()
        continue
      }

      do {
        try appGroupStore.save(snapshot)
        print("[OpenCodeQuota] Snapshot synced to widget store successfully")
        print("[OpenCodeQuota] Debug info:\n\(appGroupStore.debugInfo())")
        return true
      } catch {
        print("[OpenCodeQuota] Widget sync attempt \(attempt) failed: \(error.localizedDescription)")
        invalidateAppGroupStores()
      }
    }

    return false
  }

  private func appGroupSettingsStore() -> SettingsStore? {
    resolveAppGroupStoresIfNeeded()
    return cachedAppGroupSettingsStore
  }

  private func appGroupSnapshotStore() -> SnapshotStore? {
    resolveAppGroupStoresIfNeeded()
    return cachedAppGroupSnapshotStore
  }

  private func resolveAppGroupStoresIfNeeded() {
    guard cachedAppGroupSettingsStore == nil || cachedAppGroupSnapshotStore == nil else {
      return
    }

    do {
      let settingsURL = try SharedPaths.settingsFileURL()
      let snapshotURL = try SharedPaths.snapshotFileURL()
      cachedAppGroupSettingsStore = SettingsStore(fileURL: settingsURL)
      cachedAppGroupSnapshotStore = SnapshotStore(
        fileURL: snapshotURL,
        appGroupIdentifier: SharedConstants.appGroupIdentifier
      )
      print("[OpenCodeQuota] App Group container resolved: \(snapshotURL.deletingLastPathComponent().path)")
    } catch {
      print("[OpenCodeQuota] Failed to resolve App Group container: \(error.localizedDescription)")
      invalidateAppGroupStores()
    }
  }

  private func invalidateAppGroupStores() {
    cachedAppGroupSettingsStore = nil
    cachedAppGroupSnapshotStore = nil
  }

  private func reloadWidgetTimelines() {
    WidgetCenter.shared.reloadAllTimelines()
  }
}
