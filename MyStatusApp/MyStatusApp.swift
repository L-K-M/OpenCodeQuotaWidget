import SwiftUI

@main
struct OpenCodeQuotaApp: App {
  @StateObject private var model = AppModel()

  var body: some Scene {
    WindowGroup {
      SettingsView(model: model)
        .frame(minWidth: 780, minHeight: 760)
        .task {
          await model.bootstrap()
        }
    }
  }
}
