import SwiftUI
import AppKit

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

    MenuBarExtra("OpenCode Quota", systemImage: "chart.bar.fill") {
      MenuBarContent(model: model)
    }
  }
}

private struct MenuBarContent: View {
  @Environment(\.openWindow) private var openWindow
  @ObservedObject var model: AppModel

  var body: some View {
    Button("Open Settings") {
      openWindow(id: "settings")
      NSApplication.shared.activate(ignoringOtherApps: true)
    }
    .keyboardShortcut(",", modifiers: .command)

    Button("Refresh Now") {
      Task {
        await model.refreshNow()
      }
    }
    .keyboardShortcut("r", modifiers: .command)
    .disabled(model.isRefreshing)

    Divider()

    Toggle("Launch at Login", isOn: model.launchAtLoginBinding())

    Divider()

    Button("Quit OpenCode Quota") {
      NSApplication.shared.terminate(nil)
    }
    .keyboardShortcut("q", modifiers: .command)
  }
}
