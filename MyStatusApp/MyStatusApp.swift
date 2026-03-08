import SwiftUI
import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
  func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    false
  }

  func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
    if !flag {
      for window in sender.windows {
        if window.canBecomeMain {
          window.makeKeyAndOrderFront(nil)
          break
        }
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
        .task {
          await model.bootstrap()
        }
    }

    MenuBarExtra("OpenCode Quota", systemImage: "chart.bar.fill") {
      Button("Open Settings") {
        NSApplication.shared.activate(ignoringOtherApps: true)
        for window in NSApplication.shared.windows {
          if window.canBecomeMain {
            window.makeKeyAndOrderFront(nil)
            break
          }
        }
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

      Button("Quit OpenCode Quota") {
        NSApplication.shared.terminate(nil)
      }
      .keyboardShortcut("q", modifiers: .command)
    }
  }
}
