import Foundation

enum SharedConstants {
  static let appGroupIdentifier = "group.ch.lkmc.opencodequota"
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
    guard
      let url = FileManager.default.containerURL(
        forSecurityApplicationGroupIdentifier: SharedConstants.appGroupIdentifier
      )
    else {
      throw NSError(
        domain: "OpenCodeQuota",
        code: 1001,
        userInfo: [NSLocalizedDescriptionKey: "Unable to resolve App Group container URL."]
      )
    }
    return url
  }

  static func snapshotFileURL() throws -> URL {
    try appGroupDirectory().appendingPathComponent(SharedConstants.snapshotFileName)
  }

  static func settingsFileURL() throws -> URL {
    try appGroupDirectory().appendingPathComponent(SharedConstants.settingsFileName)
  }
}
