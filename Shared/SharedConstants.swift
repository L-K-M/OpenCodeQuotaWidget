import Foundation

enum SharedConstants {
  static let sharedDataDirectoryName = "opencodequota"
  static let snapshotFileName = "quota-snapshot.json"
  static let settingsFileName = "quota-settings.json"
  static let widgetKind = "OpenCodeQuotaWidget"
  static let openAIWidgetKind = "OpenCodeQuotaWidget.openai"
  static let zhipuWidgetKind = "OpenCodeQuotaWidget.zhipu"
  static let zaiWidgetKind = "OpenCodeQuotaWidget.zai"
  static let googleWidgetKind = "OpenCodeQuotaWidget.google"
  static let copilotWidgetKind = "OpenCodeQuotaWidget.copilot"

  static let allWidgetKinds: [String] = [
    widgetKind,
    openAIWidgetKind,
    zhipuWidgetKind,
    zaiWidgetKind,
    googleWidgetKind,
    copilotWidgetKind
  ]
}

enum SharedPaths {
  static func appGroupDirectory() throws -> URL {
    let home = NSHomeDirectory()
    guard !home.isEmpty else {
      throw NSError(
        domain: "OpenCodeQuota",
        code: 1001,
        userInfo: [NSLocalizedDescriptionKey: "Unable to resolve user home directory."]
      )
    }

    return URL(fileURLWithPath: home, isDirectory: true)
      .appendingPathComponent(".local", isDirectory: true)
      .appendingPathComponent("share", isDirectory: true)
      .appendingPathComponent(SharedConstants.sharedDataDirectoryName, isDirectory: true)
  }

  static func snapshotFileURL() throws -> URL {
    try appGroupDirectory().appendingPathComponent(SharedConstants.snapshotFileName)
  }

  static func settingsFileURL() throws -> URL {
    try appGroupDirectory().appendingPathComponent(SharedConstants.settingsFileName)
  }
}
