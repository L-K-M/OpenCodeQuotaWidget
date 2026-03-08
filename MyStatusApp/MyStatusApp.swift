import SwiftUI
import AppKit
import QuotaCore

final class AppDelegate: NSObject, NSApplicationDelegate {
  func applicationDidFinishLaunching(_ notification: Notification) {
    // The settings window should start hidden — users open it from the menu bar.
    DispatchQueue.main.async {
      for window in NSApplication.shared.windows where window.canBecomeMain {
        window.close()
      }
    }
  }

  func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    false
  }

  func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
    if !flag {
      for window in sender.windows where window.canBecomeMain {
        window.makeKeyAndOrderFront(nil)
        NSApplication.shared.activate(ignoringOtherApps: true)
        return true
      }
    }
    return true
  }
}

@main
struct OpenCodeQuotaApp: App {
  @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
  @StateObject private var model = AppModel()

  var body: some Scene {
    Window("OpenCode Quota", id: "settings") {
      SettingsView(model: model)
        .frame(minWidth: 1020, minHeight: 640)
    }

    MenuBarExtra {
      MenuBarContent(model: model)
    } label: {
      MenuBarIcon(snapshot: model.snapshot, widgetStyle: model.widgetStyle, providerStyleSettings: model.providerStyleSettings)
    }
  }
}

// MARK: - Menu Bar Icon

private struct MenuBarIcon: View {
  let snapshot: QuotaSnapshot?
  let widgetStyle: WidgetStyleSettings
  let providerStyleSettings: [QuotaProvider: ProviderStyleSettings]

  var body: some View {
    Image(nsImage: renderBarGraphIcon())
  }

  private func renderBarGraphIcon() -> NSImage {
    let barWidth: CGFloat = 3
    let barSpacing: CGFloat = 1.5
    let height: CGFloat = 16
    let cornerRadius: CGFloat = 1

    guard let snapshot, !snapshot.providers.isEmpty else {
      return fallbackIcon()
    }

    let providers = snapshot.providers
    let totalWidth = CGFloat(providers.count) * barWidth + CGFloat(max(0, providers.count - 1)) * barSpacing

    let image = NSImage(size: NSSize(width: totalWidth, height: height), flipped: false) { rect in
      for (index, provider) in providers.enumerated() {
        let x = CGFloat(index) * (barWidth + barSpacing)
        let percent = CGFloat(max(0, min(100, provider.maxUsagePercent.map { 100 - $0 } ?? 100))) / 100.0
        let barHeight = max(2, percent * height)

        let barRect = NSRect(x: x, y: 0, width: barWidth, height: barHeight)
        let barPath = NSBezierPath(roundedRect: barRect, xRadius: cornerRadius, yRadius: cornerRadius)

        let color = self.barColor(for: provider)
        color.setFill()
        barPath.fill()
      }
      return true
    }

    image.isTemplate = false
    return image
  }

  private func fallbackIcon() -> NSImage {
    let image = NSImage(systemSymbolName: "chart.bar.fill", accessibilityDescription: "OpenCode Quota")
      ?? NSImage(size: NSSize(width: 18, height: 16))
    image.isTemplate = true
    return image
  }

  private func barColor(for provider: ProviderUsage) -> NSColor {
    let style = effectiveStyle(for: provider.provider)
    let ringColors = style.ringColors
    let remaining = provider.metrics.first?.remainingPercent ?? 100
    let hex: String
    if remaining >= 70 {
      hex = ringColors.outerHighHexColor
    } else if remaining >= 40 {
      hex = ringColors.outerMediumHexColor
    } else {
      hex = ringColors.outerLowHexColor
    }
    return NSColor(hexString: hex) ?? .white
  }

  private func effectiveStyle(for provider: QuotaProvider) -> WidgetStyleSettings {
    if let override = providerStyleSettings[provider], override.useCustomStyle {
      return WidgetStyleSettings(
        backgroundHexColor: override.style.backgroundHexColor ?? widgetStyle.backgroundHexColor,
        ringColors: override.style.ringColors,
        useTransparentBackground: override.style.useTransparentBackground
      )
    }
    return widgetStyle
  }
}

// MARK: - Menu Bar Content

private struct MenuBarContent: View {
  @Environment(\.openWindow) private var openWindow
  @ObservedObject var model: AppModel

  var body: some View {
    if let snapshot = model.snapshot, !snapshot.providers.isEmpty {
      ForEach(snapshot.providers, id: \.provider) { provider in
        MenuBarProviderSection(
          provider: provider,
          widgetStyle: model.widgetStyle,
          providerStyleSettings: model.providerStyleSettings
        )
      }

      if !snapshot.failures.isEmpty {
        Divider()
        ForEach(snapshot.failures, id: \.provider) { failure in
          Text("\(failure.provider.displayName): \(failure.message)")
            .font(.caption)
        }
      }

      if let generatedAt = formattedTimestamp(snapshot.generatedAt) {
        Divider()
        Text("Updated \(generatedAt)")
          .font(.caption)
      }
    } else {
      Text("No quota data yet")
        .font(.caption)
    }

    Divider()

    Button("Refresh Now") {
      Task {
        await model.refreshNow()
      }
    }
    .keyboardShortcut("r", modifiers: .command)
    .disabled(model.isRefreshing)

    Button("Open Settings") {
      openWindow(id: "settings")
      NSApplication.shared.activate(ignoringOtherApps: true)
    }
    .keyboardShortcut(",", modifiers: .command)

    Divider()

    Toggle("Launch at Login", isOn: model.launchAtLoginBinding())

    Divider()

    Button("Quit OpenCode Quota") {
      NSApplication.shared.terminate(nil)
    }
    .keyboardShortcut("q", modifiers: .command)
  }

  private func formattedTimestamp(_ date: Date) -> String? {
    let formatter = RelativeDateTimeFormatter()
    formatter.unitsStyle = .abbreviated
    return formatter.localizedString(for: date, relativeTo: Date())
  }
}

// MARK: - Provider Section in Menu

private struct MenuBarProviderSection: View {
  let provider: ProviderUsage
  let widgetStyle: WidgetStyleSettings
  let providerStyleSettings: [QuotaProvider: ProviderStyleSettings]

  var body: some View {
    Section {
      ForEach(provider.metrics) { metric in
        menuItem(for: metric)
      }
    } header: {
      HStack(spacing: 4) {
        Circle()
          .fill(Color(nsColor: headerColor()))
          .frame(width: 6, height: 6)
        Text(providerTitle)
      }
    }
  }

  private var providerTitle: String {
    if let subtitle = provider.subtitle, !subtitle.isEmpty {
      return "\(provider.title) (\(subtitle))"
    }
    return provider.title
  }

  private func menuItem(for metric: UsageMetric) -> some View {
    let remaining = metric.remainingPercent
    let barText: String
    if metric.isUnlimited {
      barText = "\(metric.label): Unlimited"
    } else if let pct = remaining {
      let usagePart = metric.usageLine ?? "\(pct)% left"
      barText = "\(metric.label): \(usagePart)"
    } else {
      barText = metric.label
    }

    let resetPart: String? = metric.resetIn

    return VStack(alignment: .leading, spacing: 0) {
      Text(barText)
      if let resetPart {
        Text("Resets in \(resetPart)")
          .font(.caption)
          .foregroundStyle(.secondary)
      }
    }
  }

  private func headerColor() -> NSColor {
    let style = effectiveStyle(for: provider.provider)
    let ringColors = style.ringColors
    let remaining = provider.metrics.first?.remainingPercent ?? 100
    let hex: String
    if provider.metrics.first?.isUnlimited == true {
      hex = ringColors.outerUnlimitedHexColor
    } else if remaining >= 70 {
      hex = ringColors.outerHighHexColor
    } else if remaining >= 40 {
      hex = ringColors.outerMediumHexColor
    } else {
      hex = ringColors.outerLowHexColor
    }
    return NSColor(hexString: hex) ?? .white
  }

  private func effectiveStyle(for provider: QuotaProvider) -> WidgetStyleSettings {
    if let override = providerStyleSettings[provider], override.useCustomStyle {
      return WidgetStyleSettings(
        backgroundHexColor: override.style.backgroundHexColor ?? widgetStyle.backgroundHexColor,
        ringColors: override.style.ringColors,
        useTransparentBackground: override.style.useTransparentBackground
      )
    }
    return widgetStyle
  }
}

// MARK: - NSColor Hex Parsing

private extension NSColor {
  convenience init?(hexString: String) {
    var hex = hexString.trimmingCharacters(in: .whitespacesAndNewlines)
    if hex.hasPrefix("#") { hex.removeFirst() }

    if hex.count == 3 || hex.count == 4 {
      hex = hex.map { "\($0)\($0)" }.joined()
    }

    guard hex.count == 6 || hex.count == 8, let value = UInt64(hex, radix: 16) else {
      return nil
    }

    if hex.count == 6 {
      self.init(
        red: CGFloat((value >> 16) & 0xFF) / 255,
        green: CGFloat((value >> 8) & 0xFF) / 255,
        blue: CGFloat(value & 0xFF) / 255,
        alpha: 1
      )
    } else {
      self.init(
        red: CGFloat((value >> 24) & 0xFF) / 255,
        green: CGFloat((value >> 16) & 0xFF) / 255,
        blue: CGFloat((value >> 8) & 0xFF) / 255,
        alpha: CGFloat(value & 0xFF) / 255
      )
    }
  }
}
