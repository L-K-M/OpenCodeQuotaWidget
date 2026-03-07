import SwiftUI
import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
  func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    true
  }
}

@main
struct OpenCodeQuotaApp: App {
  @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
  @StateObject private var model = AppModel()

  var body: some Scene {
    WindowGroup {
      SettingsView(model: model)
        .frame(minWidth: 1020, minHeight: 640)
        .task {
          await model.bootstrap()
        }
    }
  }
}
