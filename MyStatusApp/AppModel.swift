import Foundation
import SwiftUI
import AppKit
import UniformTypeIdentifiers
import WidgetKit
import ServiceManagement
import QuotaCore

@MainActor
final class AppModel: ObservableObject {
  @Published var refreshIntervalMinutes: Int = 30
  @Published var widgetStyle: WidgetStyleSettings = .default
  @Published var widgetBackgroundSettings: WidgetBackgroundSettings = .default
  @Published var widgetVisibility: WidgetVisibilitySettings = .default
  @Published var providerStyleSettings: [QuotaProvider: ProviderStyleSettings]
  @Published var providerEnabled: [QuotaProvider: Bool]
  @Published var credentialStatuses: [ProviderCredentialStatus] = []
  @Published var authAccessGranted = false
  @Published var authAccessSummary = "OpenCode auth access not checked yet"
  @Published var authAccessDetail = ""
  @Published var snapshot: QuotaSnapshot?
  @Published var statusMessage: String = ""
  @Published var isRefreshing = false
  @Published var launchAtLogin = false

  private let settingsStore: SettingsStore
  private let snapshotStore: SnapshotStore
  private let historyStore: QuotaHistoryStore
  private let refreshService: RefreshService
  private let credentialLoader: OpenCodeCredentialLoader
  private let sandboxAccess: OpenCodeSandboxAccess
  private var cachedAppGroupSettingsStore: SettingsStore?
  private var cachedAppGroupSnapshotStore: SnapshotStore?
  private var cachedAppGroupHistoryStore: QuotaHistoryStore?
  private var autoRefreshTask: Task<Void, Never>?
  private var hasBootstrapped = false

  init() {
    let baseDirectory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
      ?? FileManager.default.temporaryDirectory
    let urls: (settings: URL, snapshot: URL, history: URL) = (
      baseDirectory.appendingPathComponent(SharedConstants.settingsFileName),
      baseDirectory.appendingPathComponent(SharedConstants.snapshotFileName),
      baseDirectory.appendingPathComponent(SharedConstants.historyFileName)
    )

    let settingsStore = SettingsStore(fileURL: urls.settings)
    let snapshotStore = SnapshotStore(fileURL: urls.snapshot)
    let historyStore = QuotaHistoryStore(fileURL: urls.history)
    let sandboxAccess = OpenCodeSandboxAccess()

    self.settingsStore = settingsStore
    self.snapshotStore = snapshotStore
    self.historyStore = historyStore
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
    self.providerEnabled = Dictionary(
      uniqueKeysWithValues: QuotaProvider.allCases.map { ($0, true) }
    )

    self.launchAtLogin = SMAppService.mainApp.status == .enabled

    Task { @MainActor [weak self] in
      await self?.bootstrap()
    }
  }

  func bootstrap() async {
    guard !hasBootstrapped else { return }
    hasBootstrapped = true

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
    widgetBackgroundSettings = settings.widgetBackgroundSettings
    widgetVisibility = settings.widgetVisibility
    providerStyleSettings = Dictionary(
      uniqueKeysWithValues: QuotaProvider.allCases.map { provider in
        (provider, settings.styleOverride(for: provider))
      }
    )
    providerEnabled = Dictionary(
      uniqueKeysWithValues: QuotaProvider.allCases.map { provider in
        (provider, settings.isEnabled(provider))
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

    let loaded = credentialLoader.load(providerEnabled: providerEnabled)
    credentialStatuses = loaded.statuses
    applyAuthAccess(loaded.authAccess)

    let enabledConfigs = loaded.runtimeConfigurations.filter(\.isEnabled)
    guard !enabledConfigs.isEmpty else {
      statusMessage = "No providers with readable credentials found in OpenCode config files."
      return
    }

    do {
      let refreshed = try await refreshService.refresh(configurations: enabledConfigs)
      do {
        try historyStore.append(refreshed)
      } catch {
        print("[OpenCodeQuota] Local history append failed: \(error.localizedDescription)")
      }

      let widgetSyncReady = syncSnapshotToWidgetStore(refreshed)
      let historySyncReady = syncHistoryToWidgetStore(refreshed)

      if widgetSyncReady || historySyncReady {
        reloadWidgetTimelines()
      }

      snapshot = refreshed

      if widgetSyncReady && historySyncReady {
        statusMessage = "Refreshed \(refreshed.providers.count) provider(s), \(refreshed.failures.count) failure(s)"
      } else {
        statusMessage = "Refreshed \(refreshed.providers.count) provider(s), \(refreshed.failures.count) failure(s). Widget sync partially unavailable."
      }
    } catch {
      statusMessage = "Refresh failed: \(error.localizedDescription)"
    }
  }

  func reloadCredentialStatuses() {
    let loaded = credentialLoader.load(providerEnabled: providerEnabled)
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

  func launchAtLoginBinding() -> Binding<Bool> {
    Binding(
      get: { self.launchAtLogin },
      set: { newValue in
        self.setLaunchAtLogin(newValue)
      }
    )
  }

  func setLaunchAtLogin(_ enabled: Bool) {
    do {
      if enabled {
        try SMAppService.mainApp.register()
      } else {
        try SMAppService.mainApp.unregister()
      }
    } catch {
      statusMessage = "Login item update failed: \(error.localizedDescription)"
    }
    launchAtLogin = SMAppService.mainApp.status == .enabled
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

  var stylePresets: [WidgetStylePreset] {
    WidgetStylePreset.all
  }

  var customStylePresetID: String {
    WidgetStylePreset.customID
  }

  func widgetStylePresetBinding() -> Binding<String> {
    Binding(
      get: { WidgetStylePreset.id(for: self.widgetStyle) },
      set: { newValue in
        guard let preset = WidgetStylePreset.preset(withID: newValue) else {
          return
        }

        self.widgetStyle = preset.style
        self.saveConfiguration()
      }
    )
  }

  func providerStylePresetBinding(for provider: QuotaProvider) -> Binding<String> {
    Binding(
      get: { WidgetStylePreset.id(for: self.providerStyle(for: provider).style) },
      set: { newValue in
        guard let preset = WidgetStylePreset.preset(withID: newValue) else {
          return
        }

        self.updateProviderStyle(for: provider) { style in
          style.useCustomStyle = true
          style.style = preset.style
        }
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

  enum WidgetBackgroundTarget {
    case dashboard
    case trend
  }

  func widgetBackgroundOverride(for target: WidgetBackgroundTarget) -> WidgetBackgroundOverride {
    switch target {
    case .dashboard:
      return widgetBackgroundSettings.dashboard
    case .trend:
      return widgetBackgroundSettings.trend
    }
  }

  func widgetBackgroundOverrideBinding(for target: WidgetBackgroundTarget) -> Binding<Bool> {
    Binding(
      get: { self.widgetBackgroundOverride(for: target).useCustomBackground },
      set: { newValue in
        self.updateWidgetBackgroundOverride(for: target) { override in
          override.useCustomBackground = newValue
        }
      }
    )
  }

  func widgetBackgroundColorBinding(for target: WidgetBackgroundTarget) -> Binding<Color> {
    Binding(
      get: {
        let override = self.widgetBackgroundOverride(for: target)
        let resolvedHex = override.backgroundHexColor ?? self.widgetStyle.backgroundHexColor
        return Self.color(fromHex: resolvedHex)
      },
      set: { newValue in
        self.updateWidgetBackgroundOverride(for: target) { override in
          override.useCustomBackground = true
          override.backgroundHexColor = Self.hexColor(from: newValue, allowTransparency: true)
          override.useTransparentBackground = false
        }
      }
    )
  }

  func widgetTransparentBackgroundBinding(for target: WidgetBackgroundTarget) -> Binding<Bool> {
    Binding(
      get: { self.widgetBackgroundOverride(for: target).useTransparentBackground },
      set: { newValue in
        self.updateWidgetBackgroundOverride(for: target) { override in
          override.useCustomBackground = true
          override.useTransparentBackground = newValue
        }
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

  func isProviderEnabled(_ provider: QuotaProvider) -> Bool {
    providerEnabled[provider] ?? true
  }

  func providerEnabledBinding(for provider: QuotaProvider) -> Binding<Bool> {
    Binding(
      get: { self.isProviderEnabled(provider) },
      set: { newValue in
        self.providerEnabled[provider] = newValue
        self.saveConfiguration()
        Task {
          await self.refreshNow()
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

  private func updateWidgetBackgroundOverride(
    for target: WidgetBackgroundTarget,
    mutate: (inout WidgetBackgroundOverride) -> Void
  ) {
    switch target {
    case .dashboard:
      var override = widgetBackgroundSettings.dashboard
      mutate(&override)
      widgetBackgroundSettings.dashboard = override
    case .trend:
      var override = widgetBackgroundSettings.trend
      mutate(&override)
      widgetBackgroundSettings.trend = override
    }

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
        ProviderSettings(provider: $0, isEnabled: providerEnabled[$0] ?? true)
      },
      widgetStyle: widgetStyle,
      widgetBackgroundSettings: widgetBackgroundSettings,
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

        let intervalNanoseconds = self.autoRefreshIntervalNanoseconds()
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

  private func appGroupHistoryStore() -> QuotaHistoryStore? {
    resolveAppGroupStoresIfNeeded()
    return cachedAppGroupHistoryStore
  }

  private func resolveAppGroupStoresIfNeeded() {
    guard
      cachedAppGroupSettingsStore == nil
        || cachedAppGroupSnapshotStore == nil
        || cachedAppGroupHistoryStore == nil
    else {
      return
    }

    do {
      let settingsURL = try SharedPaths.settingsFileURL()
      let snapshotURL = try SharedPaths.snapshotFileURL()
      let historyURL = try SharedPaths.historyFileURL()
      cachedAppGroupSettingsStore = SettingsStore(fileURL: settingsURL)
      cachedAppGroupSnapshotStore = SnapshotStore(
        fileURL: snapshotURL,
        appGroupIdentifier: SharedConstants.appGroupIdentifier
      )
      cachedAppGroupHistoryStore = QuotaHistoryStore(fileURL: historyURL)
      print("[OpenCodeQuota] App Group container resolved: \(snapshotURL.deletingLastPathComponent().path)")
    } catch {
      print("[OpenCodeQuota] Failed to resolve App Group container: \(error.localizedDescription)")
      invalidateAppGroupStores()
    }
  }

  private func invalidateAppGroupStores() {
    cachedAppGroupSettingsStore = nil
    cachedAppGroupSnapshotStore = nil
    cachedAppGroupHistoryStore = nil
  }

  @discardableResult
  private func syncHistoryToWidgetStore(_ snapshot: QuotaSnapshot) -> Bool {
    for attempt in 1...2 {
      guard let appGroupStore = appGroupHistoryStore() else {
        print("[OpenCodeQuota] History sync failed: no App Group history store available")
        invalidateAppGroupStores()
        continue
      }

      do {
        try appGroupStore.append(snapshot)
        return true
      } catch {
        print("[OpenCodeQuota] History sync attempt \(attempt) failed: \(error.localizedDescription)")
        invalidateAppGroupStores()
      }
    }

    return false
  }

  private func reloadWidgetTimelines() {
    WidgetCenter.shared.reloadAllTimelines()
  }
}

struct WidgetStylePreset: Identifiable, Hashable {
  let id: String
  let displayName: String
  let style: WidgetStyleSettings

  static let customID = "__custom__"

  static let all: [WidgetStylePreset] = [
    WidgetStylePreset(
      id: "default",
      displayName: "Default",
      style: style(nil, .default)
    ),
    WidgetStylePreset(
      id: "classic",
      displayName: "Classic",
      style: style("#475270", .default)
    ),
    WidgetStylePreset(
      id: "graphite",
      displayName: "Graphite",
      style: style(
        "#333A4A",
        rings(outerHigh: "#E5ECFA", outerMedium: "#A7B3CB", outerLow: "#6E7A96", outerUnlimited: "#C7D4F0")
      )
    ),
    WidgetStylePreset(
      id: "ocean",
      displayName: "Ocean",
      style: style(
        "#1B6CB9",
        rings(outerHigh: "#66E1FF", outerMedium: "#30B4FF", outerLow: "#147FE6", outerUnlimited: "#A3F0FF")
      )
    ),
    WidgetStylePreset(
      id: "forest",
      displayName: "Forest",
      style: style(
        "#1F7A4D",
        rings(outerHigh: "#9BF5B4", outerMedium: "#58D886", outerLow: "#2FA05B", outerUnlimited: "#D8FFE4")
      )
    ),
    WidgetStylePreset(
      id: "sunset",
      displayName: "Sunset",
      style: style(
        "#C45A3A",
        rings(outerHigh: "#FFD06A", outerMedium: "#FF9E4A", outerLow: "#FF5E4A", outerUnlimited: "#FFF0A6")
      )
    ),
    WidgetStylePreset(
      id: "midnight",
      displayName: "Midnight",
      style: style(
        "#1D2340",
        rings(outerHigh: "#A3B7FF", outerMedium: "#6D8FFF", outerLow: "#4E67C9", outerUnlimited: "#D5E1FF")
      )
    ),
    WidgetStylePreset(
      id: "royal-velvet",
      displayName: "Royal Velvet",
      style: style(
        "#4D2D8A",
        rings(outerHigh: "#D8B7FF", outerMedium: "#A67CFF", outerLow: "#7A4DDB", outerUnlimited: "#EFD9FF")
      )
    ),
    WidgetStylePreset(
      id: "purple-nurple",
      displayName: "Purple Nurple",
      style: style(
        "#6A38B5",
        rings(
          outerHigh: "#E8D4FF",
          outerMedium: "#C396FF",
          outerLow: "#8E59E8",
          outerUnlimited: "#F2E4FF",
          innerHigh: "#F4E9FF",
          innerMedium: "#D9B7FF",
          innerLow: "#A674F4",
          innerUnlimited: "#FAF2FF"
        )
      )
    ),
    WidgetStylePreset(
      id: "copper-ember",
      displayName: "Copper Ember",
      style: style(
        "#8B4A2F",
        rings(outerHigh: "#FFC18C", outerMedium: "#E58A5B", outerLow: "#BD5A3A", outerUnlimited: "#FFDDB7")
      )
    ),
    WidgetStylePreset(
      id: "glacier",
      displayName: "Glacier",
      style: style(
        "#3A87A8",
        rings(outerHigh: "#D9F8FF", outerMedium: "#9DDEFF", outerLow: "#5BB4E2", outerUnlimited: "#FFFFFF")
      )
    ),
    WidgetStylePreset(
      id: "mint-pop",
      displayName: "Mint Pop",
      style: style(
        "#1F8A74",
        rings(outerHigh: "#B6FFE8", outerMedium: "#63E6C5", outerLow: "#22B18D", outerUnlimited: "#E6FFF7")
      )
    ),
    WidgetStylePreset(
      id: "rose-quartz",
      displayName: "Rose Quartz",
      style: style(
        "#A6527A",
        rings(outerHigh: "#FFD5E8", outerMedium: "#F89DC4", outerLow: "#D96A99", outerUnlimited: "#FFEAF4")
      )
    ),
    WidgetStylePreset(
      id: "neon-pulse",
      displayName: "Neon Pulse",
      style: style(
        "#22203E",
        rings(
          outerHigh: "#36FCD0",
          outerMedium: "#00D8FF",
          outerLow: "#FF48A6",
          outerUnlimited: "#A4FF41",
          innerHigh: "#7DFFE7",
          innerMedium: "#8CF1FF",
          innerLow: "#FF8BC7",
          innerUnlimited: "#CCFF8A"
        )
      )
    ),
    WidgetStylePreset(
      id: "synthwave-80s",
      displayName: "Synthwave 80s",
      style: style(
        "#402060",
        rings(
          outerHigh: "#FF8A00",
          outerMedium: "#FF2E88",
          outerLow: "#8B2FFF",
          outerUnlimited: "#18F8FF",
          innerHigh: "#FFBE5C",
          innerMedium: "#FF74B5",
          innerLow: "#B67BFF",
          innerUnlimited: "#83F9FF"
        )
      )
    ),
    WidgetStylePreset(
      id: "cyberpunk",
      displayName: "Cyberpunk",
      style: style(
        "#161923",
        rings(
          outerHigh: "#F5FF2B",
          outerMedium: "#00F7FF",
          outerLow: "#FF2674",
          outerUnlimited: "#A855FF",
          innerHigh: "#FBFF83",
          innerMedium: "#83FCFF",
          innerLow: "#FF80AF",
          innerUnlimited: "#CF9CFF"
        )
      )
    ),
    WidgetStylePreset(
      id: "crazy-banana",
      displayName: "Crazy Banana",
      style: style(
        "#D9B21B",
        rings(
          outerHigh: "#FFF9B1",
          outerMedium: "#FFE45E",
          outerLow: "#FF9D00",
          outerUnlimited: "#A5FF3C",
          innerHigh: "#FFFFD6",
          innerMedium: "#FFEF8A",
          innerLow: "#FFBD52",
          innerUnlimited: "#D3FF87"
        )
      )
    ),
    WidgetStylePreset(
      id: "lime-laser",
      displayName: "Lime Laser",
      style: style(
        "#3F6B1A",
        rings(
          outerHigh: "#D8FF43",
          outerMedium: "#A6F222",
          outerLow: "#69C30F",
          outerUnlimited: "#F0FF8A",
          innerHigh: "#EDFF92",
          innerMedium: "#C5FF5A",
          innerLow: "#89DB2D",
          innerUnlimited: "#F8FFBE"
        )
      )
    ),
    WidgetStylePreset(
      id: "lava-burst",
      displayName: "Lava Burst",
      style: style(
        "#8A2E21",
        rings(
          outerHigh: "#FFD16B",
          outerMedium: "#FF7A2F",
          outerLow: "#E12F1F",
          outerUnlimited: "#FFF2A8",
          innerHigh: "#FFE3A0",
          innerMedium: "#FFA364",
          innerLow: "#FF5B43",
          innerUnlimited: "#FFF8CD"
        )
      )
    ),
    WidgetStylePreset(
      id: "aurora",
      displayName: "Aurora",
      style: style(
        "#255A6A",
        rings(
          outerHigh: "#70F2FF",
          outerMedium: "#65D1A5",
          outerLow: "#6E95FF",
          outerUnlimited: "#CCFFEE",
          innerHigh: "#A8F8FF",
          innerMedium: "#A6F2D4",
          innerLow: "#A7BEFF",
          innerUnlimited: "#ECFFF8"
        )
      )
    ),
    WidgetStylePreset(
      id: "desert-bloom",
      displayName: "Desert Bloom",
      style: style(
        "#A5713D",
        rings(
          outerHigh: "#FFE4A8",
          outerMedium: "#F4B96B",
          outerLow: "#D97A41",
          outerUnlimited: "#FFF2CE",
          innerHigh: "#FFEFCB",
          innerMedium: "#FFD392",
          innerLow: "#EB9968",
          innerUnlimited: "#FFF8E0"
        )
      )
    ),
    WidgetStylePreset(
      id: "candy-pop",
      displayName: "Candy Pop",
      style: style(
        "#B34FA2",
        rings(
          outerHigh: "#8CFFF3",
          outerMedium: "#7DB0FF",
          outerLow: "#FF6FB5",
          outerUnlimited: "#FFE95A",
          innerHigh: "#B9FFF7",
          innerMedium: "#ADC9FF",
          innerLow: "#FFA3D0",
          innerUnlimited: "#FFF4A8"
        )
      )
    ),
    WidgetStylePreset(
      id: "monochrome-ice",
      displayName: "Monochrome Ice",
      style: style(
        "#4F5A72",
        rings(
          outerHigh: "#FFFFFF",
          outerMedium: "#DCE4F5",
          outerLow: "#A6B4CF",
          outerUnlimited: "#F4F8FF",
          innerHigh: "#FFFFFF",
          innerMedium: "#EAF0FF",
          innerLow: "#C1CCE4",
          innerUnlimited: "#FBFDFF"
        )
      )
    ),
    WidgetStylePreset(
      id: "crystal-clear",
      displayName: "Crystal Clear",
      style: style(nil, .default, transparent: true)
    )
  ]

  static func preset(withID id: String) -> WidgetStylePreset? {
    all.first(where: { $0.id == id })
  }

  static func id(for style: WidgetStyleSettings) -> String {
    all.first(where: { $0.style == style })?.id ?? customID
  }
}

private extension WidgetStylePreset {
  static func style(
    _ backgroundHexColor: String?,
    _ ringColors: WidgetRingColors,
    transparent: Bool = false
  ) -> WidgetStyleSettings {
    WidgetStyleSettings(
      backgroundHexColor: backgroundHexColor,
      ringColors: ringColors,
      useTransparentBackground: transparent
    )
  }

  static func rings(
    outerHigh: String,
    outerMedium: String,
    outerLow: String,
    outerUnlimited: String,
    innerHigh: String? = nil,
    innerMedium: String? = nil,
    innerLow: String? = nil,
    innerUnlimited: String? = nil
  ) -> WidgetRingColors {
    WidgetRingColors(
      outerHighHexColor: outerHigh,
      outerMediumHexColor: outerMedium,
      outerLowHexColor: outerLow,
      outerUnlimitedHexColor: outerUnlimited,
      innerHighHexColor: innerHigh ?? outerHigh,
      innerMediumHexColor: innerMedium ?? outerMedium,
      innerLowHexColor: innerLow ?? outerLow,
      innerUnlimitedHexColor: innerUnlimited ?? outerUnlimited
    )
  }
}
